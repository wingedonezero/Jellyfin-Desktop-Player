#include "JellyfinClient.h"

#include <QClipboard>
#include <QCryptographicHash>
#include <QDateTime>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QSysInfo>
#include <QUrlQuery>

namespace {
const QString kClientName = QStringLiteral("Jellyfin Desktop");
const QString kVersion = QStringLiteral(PROJECT_VERSION);

// Extra item fields + image types we want on browse queries (beyond defaults).
const QString kItemFields = QStringLiteral(
    "Fields=PrimaryImageAspectRatio,RunTimeTicks,ProductionYear,CommunityRating,"
    "OfficialRating,SeriesName,Overview");
const QString kImageTypes = QStringLiteral("EnableImageTypes=Primary,Thumb,Backdrop");

// Fuller field set for a single detail page (cast, studios, tagline, etc.).
const QString kDetailFields = QStringLiteral(
    "Fields=Overview,Genres,People,Studios,Taglines,RunTimeTicks,ProductionYear,"
    "CommunityRating,CriticRating,OfficialRating,SeriesName,MediaSources,ExternalUrls,"
    "Tags,ProductionLocations,PremiereDate");

// A stable per-machine device id so the server recognises this client across runs.
QString makeDeviceId()
{
    QByteArray seed = QSysInfo::machineUniqueId();
    if (seed.isEmpty()) {
        seed = QSysInfo::machineHostName().toUtf8();
    }
    seed += "::jellyfin-desktop";
    return QString::fromLatin1(QCryptographicHash::hash(seed, QCryptographicHash::Sha1).toHex());
}
} // namespace

JellyfinClient::JellyfinClient(QObject *parent)
    : QObject(parent)
    , m_net(new QNetworkAccessManager(this))
    , m_deviceId(makeDeviceId())
    , m_deviceName(QSysInfo::machineHostName())
{
    // Abort a request if no data transfers for 20s, instead of hanging forever
    // and holding one of Qt's 6 per-host connection slots (which, once enough
    // stall, starves every later request → blank admin panels).
    m_net->setTransferTimeout(20000);
}

void JellyfinClient::setServerUrl(const QString &url)
{
    QString trimmed = url.trimmed();
    while (trimmed.endsWith(QLatin1Char('/'))) {
        trimmed.chop(1);
    }
    if (!trimmed.isEmpty() && !trimmed.startsWith(QLatin1String("http://"))
        && !trimmed.startsWith(QLatin1String("https://"))) {
        trimmed.prepend(QStringLiteral("http://"));
    }
    if (trimmed == m_serverUrl) {
        return;
    }
    m_serverUrl = trimmed;
    Q_EMIT serverUrlChanged();
}

QString JellyfinClient::authHeader() const
{
    return QStringLiteral("MediaBrowser Token=\"%1\", Client=\"%2\", Device=\"%3\", DeviceId=\"%4\", Version=\"%5\"")
        .arg(m_token, kClientName, m_deviceName, m_deviceId, kVersion);
}

QNetworkReply *JellyfinClient::get(const QString &pathWithQuery) const
{
    QNetworkRequest req{QUrl(m_serverUrl + pathWithQuery)};
    req.setRawHeader("Authorization", authHeader().toUtf8());
    return m_net->get(req);
}

QNetworkReply *JellyfinClient::post(const QString &pathWithQuery, const QByteArray &json) const
{
    QNetworkRequest req{QUrl(m_serverUrl + pathWithQuery)};
    req.setRawHeader("Authorization", authHeader().toUtf8());
    req.setHeader(QNetworkRequest::ContentTypeHeader, QByteArrayLiteral("application/json"));
    return m_net->post(req, json);
}

QNetworkReply *JellyfinClient::del(const QString &pathWithQuery) const
{
    QNetworkRequest req{QUrl(m_serverUrl + pathWithQuery)};
    req.setRawHeader("Authorization", authHeader().toUtf8());
    return m_net->deleteResource(req);
}

// --- auth -------------------------------------------------------------------

void JellyfinClient::authenticate(const QString &username, const QString &password)
{
    if (m_serverUrl.isEmpty()) {
        Q_EMIT authenticationFailed(tr("No server URL set"));
        return;
    }

    const QJsonObject body{{QStringLiteral("Username"), username}, {QStringLiteral("Pw"), password}};
    QNetworkReply *reply = post(QStringLiteral("/Users/AuthenticateByName"), QJsonDocument(body).toJson(QJsonDocument::Compact));

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            Q_EMIT authenticationFailed(reply->errorString());
            return;
        }
        const QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
        m_token = obj.value(QStringLiteral("AccessToken")).toString();
        const QJsonObject user = obj.value(QStringLiteral("User")).toObject();
        m_userId = user.value(QStringLiteral("Id")).toString();
        m_userName = user.value(QStringLiteral("Name")).toString();
        m_userConfig = user.value(QStringLiteral("Configuration")).toObject().toVariantMap();

        if (m_token.isEmpty() || m_userId.isEmpty()) {
            Q_EMIT authenticationFailed(tr("Server did not return an access token"));
            return;
        }
        saveSession();
        Q_EMIT authenticatedChanged();
        Q_EMIT userConfigChanged();
    });
}

void JellyfinClient::logout()
{
    m_token.clear();
    m_userId.clear();
    m_userName.clear();
    QSettings().remove(QStringLiteral("session"));
    Q_EMIT authenticatedChanged();
}

void JellyfinClient::getJson(const QString &path, const QString &requestTag)
{
    getJsonAttempt(path, requestTag, 1); // one retry on transient failure
}

// A GET that emits jsonReady only on a genuinely valid response, and retries
// once on a transient failure — a stalled/reset/half-closed keep-alive
// connection can "finish" with NoError but an EMPTY body, which previously got
// handed to QML as empty data (panels rendered blank). We treat empty/invalid
// bodies as failures, retry once on a fresh connection, and never retry a real
// client error (status >= 400). Every outcome is logged for diagnosis.
void JellyfinClient::getJsonAttempt(const QString &path, const QString &requestTag, int triesLeft)
{
    QNetworkReply *reply = get(path);
    connect(reply, &QNetworkReply::finished, this, [this, reply, path, requestTag, triesLeft]() {
        reply->deleteLater();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray body = reply->readAll();
        const QNetworkReply::NetworkError err = reply->error();
        const QVariant data = QJsonDocument::fromJson(body).toVariant();
        if (err == QNetworkReply::NoError && data.isValid()) {
            if (qEnvironmentVariableIsSet("JFD_NETLOG")) // opt-in full request trace
                qInfo().noquote() << "[net] GET" << path << "->" << status << body.size() << "bytes ok";
            Q_EMIT jsonReady(requestTag, data);
            return;
        }
        const bool willRetry = triesLeft > 0 && status < 400;
        qWarning().noquote() << "[net] GET" << path << "status" << status
                             << "err" << int(err) << reply->errorString()
                             << "body" << body.size() << "bytes"
                             << (willRetry ? "— retrying" : "— FAILED");
        if (willRetry) {
            getJsonAttempt(path, requestTag, triesLeft - 1);
            return;
        }
        Q_EMIT errorOccurred(reply->errorString().isEmpty()
                                 ? QStringLiteral("Empty/invalid response for %1 (HTTP %2)").arg(path).arg(status)
                                 : reply->errorString());
    });
}

void JellyfinClient::fetchUserConfig()
{
    if (m_userId.isEmpty())
        return;
    QNetworkReply *reply = get(QStringLiteral("/Users/%1").arg(m_userId));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            Q_EMIT errorOccurred(reply->errorString());
            return;
        }
        const QJsonObject user = QJsonDocument::fromJson(reply->readAll()).object();
        m_userConfig = user.value(QStringLiteral("Configuration")).toObject().toVariantMap();
        Q_EMIT userConfigChanged();
    });
}

// Mutate one field of the cached UserConfiguration and POST the whole object
// back (matches jellyfin-web's updateUserConfiguration). Optimistic: the UI sees
// the change immediately via userConfigChanged.
void JellyfinClient::setUserConfig(const QString &key, const QVariant &value)
{
    if (m_userId.isEmpty())
        return;
    m_userConfig.insert(key, value);
    Q_EMIT userConfigChanged();
    const QJsonObject body = QJsonObject::fromVariantMap(m_userConfig);
    QNetworkReply *reply = post(QStringLiteral("/Users/%1/Configuration").arg(m_userId),
                                QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError)
            Q_EMIT errorOccurred(reply->errorString());
    });
}

void JellyfinClient::authorizeQuickConnect(const QString &code)
{
    const QString c = QString::fromUtf8(QUrl::toPercentEncoding(code));
    QNetworkReply *reply = post(QStringLiteral("/QuickConnect/Authorize?code=%1").arg(c), QByteArray());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        const bool ok = reply->error() == QNetworkReply::NoError;
        Q_EMIT quickConnectResult(ok, ok ? tr("Device authorized — it can now sign in.")
                                         : tr("Invalid or expired code."));
    });
}

void JellyfinClient::saveSession() const
{
    QSettings s;
    s.beginGroup(QStringLiteral("session"));
    s.setValue(QStringLiteral("server"), m_serverUrl);
    s.setValue(QStringLiteral("token"), m_token);
    s.setValue(QStringLiteral("userId"), m_userId);
    s.setValue(QStringLiteral("userName"), m_userName);
    s.endGroup();
}

bool JellyfinClient::restoreSession()
{
    QSettings s;
    s.beginGroup(QStringLiteral("session"));
    const QString server = s.value(QStringLiteral("server")).toString();
    const QString token = s.value(QStringLiteral("token")).toString();
    const QString userId = s.value(QStringLiteral("userId")).toString();
    const QString userName = s.value(QStringLiteral("userName")).toString();
    s.endGroup();

    if (server.isEmpty() || token.isEmpty() || userId.isEmpty())
        return false;

    m_serverUrl = server;
    m_token = token;
    m_userId = userId;
    m_userName = userName;
    Q_EMIT serverUrlChanged();
    Q_EMIT authenticatedChanged();
    return true;
}

// --- browse -----------------------------------------------------------------

void JellyfinClient::requestItems(const QString &pathWithQuery, const QString &requestTag)
{
    QNetworkReply *reply = get(pathWithQuery);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestTag]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            Q_EMIT errorOccurred(reply->errorString());
            return;
        }
        Q_EMIT itemsReady(requestTag, parseItems(reply->readAll()));
    });
}

void JellyfinClient::fetchUserViews(const QString &requestTag)
{
    requestItems(QStringLiteral("/UserViews?userId=%1").arg(m_userId), requestTag);
}

void JellyfinClient::fetchResume(const QString &requestTag)
{
    requestItems(QStringLiteral("/Users/%1/Items/Resume?Limit=24&MediaTypes=Video&%2&%3")
                     .arg(m_userId, kItemFields, kImageTypes),
                 requestTag);
}

void JellyfinClient::fetchNextUp(const QString &requestTag, const QString &seriesId)
{
    const QSettings cfg;
    QString extra;
    if (!seriesId.isEmpty()) {
        // a series' own Next Up (detail row / series Play) — no date cutoff
        extra += QStringLiteral("&SeriesId=%1").arg(seriesId);
    } else {
        // Home row: honor the user's Display prefs (Settings → Display) — cap how
        // far back a show stays in Next Up. web default = 365 days; 0 = no limit.
        const int maxDays = cfg.value(QStringLiteral("display/maxDaysNextUp"), 365).toInt();
        if (maxDays > 0)
            extra += QStringLiteral("&NextUpDateCutoff=%1")
                         .arg(QDateTime::currentDateTimeUtc().addDays(-maxDays).toString(Qt::ISODate));
    }
    if (cfg.value(QStringLiteral("display/rewatchingNextUp"), false).toBool())
        extra += QStringLiteral("&EnableRewatching=true");

    requestItems(QStringLiteral("/Shows/NextUp?userId=%1&Limit=24&%2&%3%4")
                     .arg(m_userId, kItemFields, kImageTypes, extra),
                 requestTag);
}

void JellyfinClient::fetchLatest(const QString &parentId, const QString &requestTag)
{
    // NB: /Items/Latest returns a bare JSON array (not {Items:[...]}); parseItems handles both.
    requestItems(QStringLiteral("/Users/%1/Items/Latest?ParentId=%2&Limit=20&%3&%4")
                     .arg(m_userId, parentId, kItemFields, kImageTypes),
                 requestTag);
}

void JellyfinClient::fetchItems(const QString &parentId, const QString &requestTag,
                                const QString &sortBy, const QString &sortOrder,
                                const QString &extraQuery)
{
    requestItems(QStringLiteral("/Users/%1/Items?ParentId=%2&SortBy=%3&SortOrder=%4&%5&%6%7")
                     .arg(m_userId).arg(parentId).arg(sortBy).arg(sortOrder)
                     .arg(kItemFields).arg(kImageTypes).arg(extraQuery),
                 requestTag);
}

void JellyfinClient::fetchItemsPaged(const QString &parentId, const QString &requestTag,
                                     const QString &sortBy, const QString &sortOrder,
                                     const QString &extraQuery, int startIndex, int limit)
{
    QString q = QStringLiteral("/Users/%1/Items?ParentId=%2&SortBy=%3&SortOrder=%4&%5&%6&StartIndex=%7&EnableTotalRecordCount=true%8")
                    .arg(m_userId).arg(parentId).arg(sortBy).arg(sortOrder)
                    .arg(kItemFields).arg(kImageTypes).arg(startIndex).arg(extraQuery);
    if (limit > 0)
        q += QStringLiteral("&Limit=%1").arg(limit);
    QNetworkReply *reply = get(q);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestTag, startIndex]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) { Q_EMIT errorOccurred(reply->errorString()); return; }
        const QByteArray body = reply->readAll();
        const QVariantList items = parseItems(body);
        const int total = QJsonDocument::fromJson(body).object()
                              .value(QStringLiteral("TotalRecordCount")).toInt(int(items.size()));
        Q_EMIT itemsPageReady(requestTag, items, total, startIndex);
    });
}

void JellyfinClient::fetchItem(const QString &itemId, const QString &requestTag)
{
    // Single item (/Users/{id}/Items/{id}) returns a bare object; wrap as a
    // one-element list so the UI consumes it via the same itemsReady path.
    QNetworkReply *reply = get(QStringLiteral("/Users/%1/Items/%2?%3&%4")
                                   .arg(m_userId, itemId, kDetailFields, kImageTypes));
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestTag]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            Q_EMIT errorOccurred(reply->errorString());
            return;
        }
        const QJsonObject o = QJsonDocument::fromJson(reply->readAll()).object();
        Q_EMIT itemsReady(requestTag, QVariantList{parseItem(o)});
    });
}

void JellyfinClient::fetchSeasons(const QString &seriesId, const QString &requestTag)
{
    requestItems(QStringLiteral("/Shows/%1/Seasons?userId=%2&%3")
                     .arg(seriesId, m_userId, kImageTypes),
                 requestTag);
}

void JellyfinClient::fetchEpisodes(const QString &seriesId, const QString &seasonId,
                                   const QString &requestTag, const QString &startItemId)
{
    QString path = QStringLiteral("/Shows/%1/Episodes?userId=%2&%3&%4")
                       .arg(seriesId, m_userId, kItemFields, kImageTypes);
    if (!seasonId.isEmpty())
        path += QStringLiteral("&seasonId=%1").arg(seasonId);
    // startItemId returns the series' episodes from that one onward (across
    // seasons) — used to auto-queue when a single episode is played, like web.
    if (!startItemId.isEmpty())
        path += QStringLiteral("&startItemId=%1&Limit=100").arg(startItemId);
    requestItems(path, requestTag);
}

void JellyfinClient::fetchSimilar(const QString &itemId, const QString &requestTag)
{
    requestItems(QStringLiteral("/Items/%1/Similar?userId=%2&Limit=14&%3&%4")
                     .arg(itemId, m_userId, kItemFields, kImageTypes),
                 requestTag);
}

void JellyfinClient::fetchMediaSegments(const QString &itemId, const QString &includeTypes)
{
    QString path = QStringLiteral("/MediaSegments/%1").arg(itemId);
    if (!includeTypes.isEmpty())
        path += QStringLiteral("?includeSegmentTypes=%1").arg(includeTypes);
    QNetworkReply *reply = get(path);
    connect(reply, &QNetworkReply::finished, this, [this, reply, itemId]() {
        reply->deleteLater();
        QVariantList segments;
        const QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
        const QJsonArray items = obj.value(QStringLiteral("Items")).toArray();
        for (const QJsonValue &v : items) {
            const QJsonObject s = v.toObject();
            segments.append(QVariantMap{
                {QStringLiteral("type"), s.value(QStringLiteral("Type")).toString()},
                {QStringLiteral("startTicks"), s.value(QStringLiteral("StartTicks")).toDouble()},
                {QStringLiteral("endTicks"), s.value(QStringLiteral("EndTicks")).toDouble()}});
        }
        Q_EMIT mediaSegmentsReady(itemId, segments);
    });
}

void JellyfinClient::fetchFavorites(const QString &requestTag)
{
    requestItems(QStringLiteral("/Users/%1/Items?Filters=IsFavorite&Recursive=true&SortBy=SortName"
                                "&IncludeItemTypes=Movie,Series,Episode&%2&%3")
                     .arg(m_userId, kItemFields, kImageTypes),
                 requestTag);
}

void JellyfinClient::search(const QString &query, const QString &requestTag)
{
    const QString q = QString::fromUtf8(QUrl::toPercentEncoding(query));
    requestItems(QStringLiteral("/Users/%1/Items?searchTerm=%2&Recursive=true&Limit=48"
                                "&IncludeItemTypes=Movie,Series,Episode&%3&%4")
                     .arg(m_userId, q, kItemFields, kImageTypes),
                 requestTag);
}

void JellyfinClient::fetchByPerson(const QString &personId, const QString &requestTag)
{
    requestItems(QStringLiteral("/Users/%1/Items?personIds=%2&Recursive=true"
                                "&SortBy=PremiereDate&SortOrder=Descending"
                                "&IncludeItemTypes=Movie,Series&%3&%4")
                     .arg(m_userId, personId, kItemFields, kImageTypes),
                 requestTag);
}

void JellyfinClient::fetchGenres(const QString &parentId, const QString &requestTag)
{
    requestItems(QStringLiteral("/Genres?parentId=%1&userId=%2&SortBy=SortName&%3")
                     .arg(parentId, m_userId, kImageTypes),
                 requestTag);
}

void JellyfinClient::fetchStudios(const QString &parentId, const QString &requestTag)
{
    requestItems(QStringLiteral("/Studios?parentId=%1&userId=%2&%3")
                     .arg(parentId, m_userId, kImageTypes),
                 requestTag);
}

void JellyfinClient::fetchCollections(const QString &requestTag)
{
    requestItems(QStringLiteral("/Users/%1/Items?Recursive=true&IncludeItemTypes=BoxSet"
                                "&SortBy=SortName&SortOrder=Ascending&%2&%3")
                     .arg(m_userId, kItemFields, kImageTypes),
                 requestTag);
}

void JellyfinClient::fetchUpcoming(const QString &requestTag)
{
    requestItems(QStringLiteral("/Shows/Upcoming?userId=%1&Limit=40&%2&%3")
                     .arg(m_userId, kItemFields, kImageTypes),
                 requestTag);
}

void JellyfinClient::fetchSpecialFeatures(const QString &itemId, const QString &requestTag)
{
    // returns a bare array; parseItems handles that
    requestItems(QStringLiteral("/Users/%1/Items/%2/SpecialFeatures").arg(m_userId, itemId), requestTag);
}

void JellyfinClient::fetchPlaylists(const QString &requestTag)
{
    requestItems(QStringLiteral("/Users/%1/Items?Recursive=true&IncludeItemTypes=Playlist"
                                "&SortBy=SortName&%2&%3")
                     .arg(m_userId, kItemFields, kImageTypes),
                 requestTag);
}

void JellyfinClient::addToPlaylist(const QString &playlistId, const QString &itemId)
{
    QNetworkReply *reply = post(QStringLiteral("/Playlists/%1/Items?ids=%2&userId=%3")
                                    .arg(playlistId, itemId, m_userId),
                                QByteArray());
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
}

void JellyfinClient::createPlaylist(const QString &name, const QString &itemId)
{
    QNetworkReply *reply = post(QStringLiteral("/Playlists?Name=%1&Ids=%2&userId=%3")
                                    .arg(QString::fromUtf8(QUrl::toPercentEncoding(name)), itemId, m_userId),
                                QByteArray());
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
}

void JellyfinClient::addToCollection(const QString &collectionId, const QString &itemId)
{
    QNetworkReply *reply = post(QStringLiteral("/Collections/%1/Items?ids=%2").arg(collectionId, itemId),
                                QByteArray());
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
}

void JellyfinClient::createCollection(const QString &name, const QString &itemId)
{
    QNetworkReply *reply = post(QStringLiteral("/Collections?Name=%1&Ids=%2")
                                    .arg(QString::fromUtf8(QUrl::toPercentEncoding(name)), itemId),
                                QByteArray());
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
}

void JellyfinClient::fetchRecommendations(const QString &parentId, const QString &requestTag)
{
    QNetworkReply *reply = get(QStringLiteral("/Movies/Recommendations?userId=%1&parentId=%2"
                                              "&categoryLimit=6&itemLimit=16&%3&%4")
                                   .arg(m_userId, parentId, kItemFields, kImageTypes));
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestTag]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            Q_EMIT errorOccurred(reply->errorString());
            return;
        }
        const QJsonArray cats = QJsonDocument::fromJson(reply->readAll()).array();
        QVariantList out;
        for (const QJsonValue &cv : cats) {
            const QJsonObject c = cv.toObject();
            QVariantList items;
            const QJsonArray arr = c.value(QStringLiteral("Items")).toArray();
            for (const QJsonValue &iv : arr) {
                items.append(parseItem(iv.toObject()));
            }
            if (items.isEmpty()) {
                continue;
            }
            const QString rt = c.value(QStringLiteral("RecommendationType")).toString();
            const QString base = c.value(QStringLiteral("BaselineItemName")).toString();
            QString title;
            if (rt.contains(QLatin1String("Director")) && !base.isEmpty())
                title = tr("Directed by %1").arg(base);
            else if (rt.contains(QLatin1String("Actor")) && !base.isEmpty())
                title = tr("Starring %1").arg(base);
            else if (!base.isEmpty())
                title = tr("Because you watched %1").arg(base);
            else
                title = tr("Recommended");
            QVariantMap cat;
            cat[QStringLiteral("title")] = title;
            cat[QStringLiteral("items")] = items;
            out.append(cat);
        }
        Q_EMIT categoriesReady(requestTag, out);
    });
}

QVariantList JellyfinClient::parseItems(const QByteArray &json)
{
    // Most endpoints return {Items:[...]}; /Items/Latest returns a bare array.
    const QJsonDocument doc = QJsonDocument::fromJson(json);
    const QJsonArray items = doc.isArray() ? doc.array()
                                           : doc.object().value(QStringLiteral("Items")).toArray();
    QVariantList out;
    out.reserve(items.size());
    for (const QJsonValue &v : items) {
        out.append(parseItem(v.toObject()));
    }
    return out;
}

QVariantMap JellyfinClient::parseItem(const QJsonObject &o)
{
    QVariantMap m;
    m[QStringLiteral("id")] = o.value(QStringLiteral("Id")).toString();
    m[QStringLiteral("name")] = o.value(QStringLiteral("Name")).toString();
    m[QStringLiteral("type")] = o.value(QStringLiteral("Type")).toString();
    m[QStringLiteral("isFolder")] = o.value(QStringLiteral("IsFolder")).toBool();
    m[QStringLiteral("collectionType")] = o.value(QStringLiteral("CollectionType")).toString();
    m[QStringLiteral("canDelete")] = o.value(QStringLiteral("CanDelete")).toBool();
    m[QStringLiteral("overview")] = o.value(QStringLiteral("Overview")).toString();
    m[QStringLiteral("productionYear")] = o.value(QStringLiteral("ProductionYear")).toInt();
    m[QStringLiteral("runTimeTicks")] = o.value(QStringLiteral("RunTimeTicks")).toDouble();
    m[QStringLiteral("communityRating")] = o.value(QStringLiteral("CommunityRating")).toDouble();
    m[QStringLiteral("criticRating")] = o.value(QStringLiteral("CriticRating")).toDouble();
    m[QStringLiteral("officialRating")] = o.value(QStringLiteral("OfficialRating")).toString();
    m[QStringLiteral("premiereDate")] = o.value(QStringLiteral("PremiereDate")).toString(); // person birthday too
    m[QStringLiteral("endDate")] = o.value(QStringLiteral("EndDate")).toString();           // person death too
    m[QStringLiteral("seriesName")] = o.value(QStringLiteral("SeriesName")).toString();
    m[QStringLiteral("seriesId")] = o.value(QStringLiteral("SeriesId")).toString();
    m[QStringLiteral("seasonId")] = o.value(QStringLiteral("SeasonId")).toString();
    m[QStringLiteral("parentId")] = o.value(QStringLiteral("ParentId")).toString();
    if (o.contains(QStringLiteral("IndexNumber")))
        m[QStringLiteral("indexNumber")] = o.value(QStringLiteral("IndexNumber")).toInt();
    if (o.contains(QStringLiteral("ParentIndexNumber")))
        m[QStringLiteral("parentIndexNumber")] = o.value(QStringLiteral("ParentIndexNumber")).toInt();

    // images: tag lets us request the right cached image; thumb/backdrop for 16:9 cards
    const QJsonObject tags = o.value(QStringLiteral("ImageTags")).toObject();
    m[QStringLiteral("imageTag")] = tags.value(QStringLiteral("Primary")).toString();
    m[QStringLiteral("imageTagThumb")] = tags.value(QStringLiteral("Thumb")).toString();
    m[QStringLiteral("logoTag")] = tags.value(QStringLiteral("Logo")).toString();
    m[QStringLiteral("hasBackdrop")] = !o.value(QStringLiteral("BackdropImageTags")).toArray().isEmpty();

    // genres
    QVariantList genres;
    const QJsonArray genreArr = o.value(QStringLiteral("Genres")).toArray();
    for (const QJsonValue &g : genreArr) {
        genres.append(g.toString());
    }
    m[QStringLiteral("genres")] = genres;

    // tags (detail)
    QVariantList tagList;
    const QJsonArray tagArr = o.value(QStringLiteral("Tags")).toArray();
    for (const QJsonValue &t : tagArr)
        tagList.append(t.toString());
    m[QStringLiteral("tags")] = tagList;

    // studios + tagline (detail)
    QVariantList studios;
    const QJsonArray studioArr = o.value(QStringLiteral("Studios")).toArray();
    for (const QJsonValue &s : studioArr) {
        studios.append(s.toObject().value(QStringLiteral("Name")).toString());
    }
    m[QStringLiteral("studios")] = studios;
    QVariantList prodLocs;
    const QJsonArray plArr = o.value(QStringLiteral("ProductionLocations")).toArray();
    for (const QJsonValue &p : plArr)
        prodLocs.append(p.toString());
    m[QStringLiteral("productionLocations")] = prodLocs;
    const QJsonArray taglines = o.value(QStringLiteral("Taglines")).toArray();
    m[QStringLiteral("tagline")] = taglines.isEmpty() ? QString() : taglines.first().toString();

    // external links (IMDb/TMDb/…) for the detail page
    QVariantList externalUrls;
    const QJsonArray urlArr = o.value(QStringLiteral("ExternalUrls")).toArray();
    for (const QJsonValue &lv : urlArr) {
        const QJsonObject l = lv.toObject();
        externalUrls.append(QVariantMap{{QStringLiteral("name"), l.value(QStringLiteral("Name")).toString()},
                                        {QStringLiteral("url"), l.value(QStringLiteral("Url")).toString()}});
    }
    m[QStringLiteral("externalUrls")] = externalUrls;

    // media sources (versions) — full array for the detail version/track selectors;
    // each stream keeps its server Index so the player can pre-select a track.
    const QJsonArray sources = o.value(QStringLiteral("MediaSources")).toArray();
    QVariantList sourceList;
    for (const QJsonValue &srcV : sources) {
        const QJsonObject src = srcV.toObject();
        QVariantList streams;
        const QJsonArray streamArr = src.value(QStringLiteral("MediaStreams")).toArray();
        for (const QJsonValue &sv : streamArr) {
            const QJsonObject s = sv.toObject();
            streams.append(QVariantMap{
                {QStringLiteral("type"), s.value(QStringLiteral("Type")).toString()},
                {QStringLiteral("codec"), s.value(QStringLiteral("Codec")).toString()},
                {QStringLiteral("title"), s.value(QStringLiteral("DisplayTitle")).toString()},
                {QStringLiteral("language"), s.value(QStringLiteral("Language")).toString()},
                {QStringLiteral("width"), s.value(QStringLiteral("Width")).toInt()},
                {QStringLiteral("height"), s.value(QStringLiteral("Height")).toInt()},
                {QStringLiteral("channels"), s.value(QStringLiteral("Channels")).toInt()},
                {QStringLiteral("index"), s.value(QStringLiteral("Index")).toInt()}});
        }
        sourceList.append(QVariantMap{
            {QStringLiteral("id"), src.value(QStringLiteral("Id")).toString()},
            {QStringLiteral("name"), src.value(QStringLiteral("Name")).toString()},
            {QStringLiteral("container"), src.value(QStringLiteral("Container")).toString()},
            {QStringLiteral("sizeBytes"), src.value(QStringLiteral("Size")).toDouble()},
            {QStringLiteral("defaultAudioIndex"), src.contains(QStringLiteral("DefaultAudioStreamIndex"))
                                                  ? src.value(QStringLiteral("DefaultAudioStreamIndex")).toInt() : -1},
            {QStringLiteral("defaultSubtitleIndex"), src.contains(QStringLiteral("DefaultSubtitleStreamIndex"))
                                                     ? src.value(QStringLiteral("DefaultSubtitleStreamIndex")).toInt() : -1},
            {QStringLiteral("streams"), streams}});
    }
    m[QStringLiteral("mediaSources")] = sourceList;
    // top-level (first source) for the existing Media Info display + back-compat
    if (!sourceList.isEmpty()) {
        const QVariantMap s0 = sourceList.first().toMap();
        m[QStringLiteral("container")] = s0.value(QStringLiteral("container"));
        m[QStringLiteral("sizeBytes")] = s0.value(QStringLiteral("sizeBytes"));
        m[QStringLiteral("mediaStreams")] = s0.value(QStringLiteral("streams"));
    }

    // trickplay sheets (scrubber hover previews): { mediaSourceId: { width: info } }
    if (o.contains(QStringLiteral("Trickplay")))
        m[QStringLiteral("trickplay")] = o.value(QStringLiteral("Trickplay")).toObject().toVariantMap();

    // chapters (Scenes section): name + start + image tag (index = position)
    const QJsonArray chapArr = o.value(QStringLiteral("Chapters")).toArray();
    if (!chapArr.isEmpty()) {
        QVariantList chapters;
        for (int i = 0; i < chapArr.size(); ++i) {
            const QJsonObject c = chapArr.at(i).toObject();
            chapters.append(QVariantMap{
                {QStringLiteral("name"), c.value(QStringLiteral("Name")).toString()},
                {QStringLiteral("startTicks"), c.value(QStringLiteral("StartPositionTicks")).toDouble()},
                {QStringLiteral("imageTag"), c.value(QStringLiteral("ImageTag")).toString()},
                {QStringLiteral("index"), i}});
        }
        m[QStringLiteral("chapters")] = chapters;
    }

    // people (cast & crew) for detail pages
    QVariantList people;
    const QJsonArray peopleArr = o.value(QStringLiteral("People")).toArray();
    for (const QJsonValue &pv : peopleArr) {
        const QJsonObject p = pv.toObject();
        QVariantMap pm;
        pm[QStringLiteral("id")] = p.value(QStringLiteral("Id")).toString();
        pm[QStringLiteral("name")] = p.value(QStringLiteral("Name")).toString();
        pm[QStringLiteral("role")] = p.value(QStringLiteral("Role")).toString();
        pm[QStringLiteral("type")] = p.value(QStringLiteral("Type")).toString();
        pm[QStringLiteral("imageTag")] = p.value(QStringLiteral("PrimaryImageTag")).toString();
        people.append(pm);
    }
    m[QStringLiteral("people")] = people;

    // user data: resume position, played/favorite state, unwatched count
    const QJsonObject userData = o.value(QStringLiteral("UserData")).toObject();
    m[QStringLiteral("playbackTicks")] = userData.value(QStringLiteral("PlaybackPositionTicks")).toDouble();
    m[QStringLiteral("played")] = userData.value(QStringLiteral("Played")).toBool();
    m[QStringLiteral("isFavorite")] = userData.value(QStringLiteral("IsFavorite")).toBool();
    m[QStringLiteral("unplayedItemCount")] = userData.value(QStringLiteral("UnplayedItemCount")).toInt();
    m[QStringLiteral("playedPercentage")] = userData.value(QStringLiteral("PlayedPercentage")).toDouble();
    return m;
}

// --- url helpers ------------------------------------------------------------

QUrl JellyfinClient::imageUrl(const QString &itemId, const QString &imageType, int maxHeight,
                             const QString &tag, int index) const
{
    QString path = QStringLiteral("/Items/%1/Images/%2").arg(itemId, imageType);
    if (index >= 0)
        path += QStringLiteral("/%1").arg(index); // Chapter/{index}
    QUrl url{m_serverUrl + path};
    QUrlQuery q;
    if (maxHeight > 0) {
        q.addQueryItem(QStringLiteral("maxHeight"), QString::number(maxHeight));
    }
    if (!tag.isEmpty()) {
        q.addQueryItem(QStringLiteral("tag"), tag); // stable cache key for this exact image
    }
    url.setQuery(q);
    return url;
}

QUrl JellyfinClient::streamUrl(const QString &itemId, const QString &sourceId) const
{
    // Direct play: mpv handles essentially every codec/container, so we ask the
    // server for the original file (static=true) rather than a transcode.
    QUrl url{m_serverUrl + QStringLiteral("/Videos/%1/stream").arg(itemId)};
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("static"), QStringLiteral("true"));
    q.addQueryItem(QStringLiteral("mediaSourceId"), sourceId.isEmpty() ? itemId : sourceId);
    q.addQueryItem(QStringLiteral("deviceId"), m_deviceId);
    q.addQueryItem(QStringLiteral("api_key"), m_token);
    url.setQuery(q);
    return url;
}

QUrl JellyfinClient::trickplayUrl(const QString &itemId, int width, int index) const
{
    // A single trickplay sheet: /Videos/{id}/Trickplay/{width}/{index}.jpg.
    // Direct play uses the item id as the media source id (matches the server's
    // Trickplay map key). The OSD clips one thumbnail out of the tiled sheet.
    QUrl url{m_serverUrl + QStringLiteral("/Videos/%1/Trickplay/%2/%3.jpg")
                               .arg(itemId).arg(width).arg(index)};
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("ApiKey"), m_token);
    q.addQueryItem(QStringLiteral("MediaSourceId"), itemId);
    url.setQuery(q);
    return url;
}

QJsonObject JellyfinClient::deviceProfile() const
{
    // mpv direct-plays essentially everything; the transcode target (used only
    // when a bitrate/resolution cap forces a server transcode) is configurable
    // from Settings → Playback. Defaults reproduce the original safe h264/aac
    // HLS pipeline, so an unconfigured client behaves exactly as before.
    const QSettings cfg;
    QString vCodec = cfg.value(QStringLiteral("playback/transcodeVideoCodec")).toString();
    if (vCodec.isEmpty() || vCodec == QLatin1String("auto")) vCodec = QStringLiteral("h264");
    QString aCodec = cfg.value(QStringLiteral("playback/transcodeAudioCodec")).toString();
    if (aCodec.isEmpty() || aCodec == QLatin1String("auto")) aCodec = QStringLiteral("aac,mp3");
    int channels = cfg.value(QStringLiteral("playback/audioChannels"), 2).toInt();
    if (channels < 1) channels = 2;
    const int maxResW = cfg.value(QStringLiteral("playback/maxResolutionWidth"), 0).toInt(); // 0 = no cap
    // hevc/av1 need an fMP4 (mp4) HLS container; h264 stays in MPEG-TS.
    const QString hlsContainer = (vCodec == QLatin1String("h264")) ? QStringLiteral("ts") : QStringLiteral("mp4");

    const QJsonObject videoDirect{
        {QStringLiteral("Container"), QStringLiteral("mp4,m4v,mkv,webm,avi,mov,ts,m2ts,flv,wmv,asf,mpg,mpeg,3gp,ogv")},
        {QStringLiteral("Type"), QStringLiteral("Video")}};
    const QJsonObject audioDirect{
        {QStringLiteral("Container"), QStringLiteral("mp3,aac,flac,alac,ogg,oga,wav,wma,opus,m4a,mka")},
        {QStringLiteral("Type"), QStringLiteral("Audio")}};
    const QJsonObject hls{
        {QStringLiteral("Container"), hlsContainer},
        {QStringLiteral("Type"), QStringLiteral("Video")},
        {QStringLiteral("AudioCodec"), aCodec},
        {QStringLiteral("VideoCodec"), vCodec},
        {QStringLiteral("Context"), QStringLiteral("Streaming")},
        {QStringLiteral("Protocol"), QStringLiteral("hls")},
        {QStringLiteral("MaxAudioChannels"), QString::number(channels)},
        {QStringLiteral("MinSegments"), 1},
        {QStringLiteral("BreakOnNonKeyFrames"), true}};
    const auto subtitle = [](const QString &fmt) {
        return QJsonObject{{QStringLiteral("Format"), fmt}, {QStringLiteral("Method"), QStringLiteral("External")}};
    };

    // Resolution cap (only when set): ask the server to keep the transcode within
    // the chosen width. Auto direct-play (the common path) bypasses this entirely.
    QJsonArray codecProfiles;
    if (maxResW > 0) {
        codecProfiles.append(QJsonObject{
            {QStringLiteral("Type"), QStringLiteral("Video")},
            {QStringLiteral("Conditions"), QJsonArray{QJsonObject{
                {QStringLiteral("Condition"), QStringLiteral("LessThanEqual")},
                {QStringLiteral("Property"), QStringLiteral("Width")},
                {QStringLiteral("Value"), QString::number(maxResW)},
                {QStringLiteral("IsRequired"), false}}}}});
    }

    QJsonObject p;
    p[QStringLiteral("DirectPlayProfiles")] = QJsonArray{videoDirect, audioDirect};
    p[QStringLiteral("TranscodingProfiles")] = QJsonArray{hls};
    p[QStringLiteral("CodecProfiles")] = codecProfiles;
    p[QStringLiteral("ContainerProfiles")] = QJsonArray{};
    p[QStringLiteral("ResponseProfiles")] = QJsonArray{};
    p[QStringLiteral("SubtitleProfiles")] = QJsonArray{
        subtitle(QStringLiteral("srt")), subtitle(QStringLiteral("ass")),
        subtitle(QStringLiteral("subrip")), subtitle(QStringLiteral("vtt"))};
    return p;
}

void JellyfinClient::requestStream(const QString &itemId, int maxBitrate, qint64 startTicks,
                                   const QString &requestTag, int audioStreamIndex,
                                   int subtitleStreamIndex, const QString &mediaSourceId)
{
    const QString srcId = mediaSourceId.isEmpty() ? itemId : mediaSourceId; // chosen version
    if (maxBitrate <= 0) {
        // Auto: mpv direct-plays the original file — no server transcode, no
        // PlaybackInfo round-trip. (The server reports direct-play unsupported
        // for our generic profile, but mpv handles every codec, so we trust it.)
        // Audio/subtitle selection is applied by the player on the loaded file.
        m_playSessionId.clear();
        m_mediaSourceId = srcId;
        m_transcoding = false;
        QVariantMap info;
        info[QStringLiteral("url")] = streamUrl(itemId, srcId).toString();
        info[QStringLiteral("isTranscode")] = false;
        Q_EMIT streamReady(requestTag, info);
        return;
    }

    QJsonObject body;
    body[QStringLiteral("DeviceProfile")] = deviceProfile();
    if (maxBitrate > 0)
        body[QStringLiteral("MaxStreamingBitrate")] = maxBitrate;
    if (startTicks > 0)
        body[QStringLiteral("StartTimeTicks")] = startTicks;
    body[QStringLiteral("EnableDirectPlay")] = (maxBitrate <= 0);
    body[QStringLiteral("EnableDirectStream")] = (maxBitrate <= 0);
    body[QStringLiteral("EnableTranscoding")] = true;
    body[QStringLiteral("AllowVideoStreamCopy")] = true;
    body[QStringLiteral("AllowAudioStreamCopy")] = true;
    if (!mediaSourceId.isEmpty())
        body[QStringLiteral("MediaSourceId")] = mediaSourceId;
    if (audioStreamIndex >= 0)
        body[QStringLiteral("AudioStreamIndex")] = audioStreamIndex;
    if (subtitleStreamIndex >= 0)
        body[QStringLiteral("SubtitleStreamIndex")] = subtitleStreamIndex;

    const QString path = QStringLiteral("/Items/%1/PlaybackInfo?userId=%2").arg(itemId, m_userId);
    QNetworkReply *reply = post(path, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestTag, itemId, srcId, maxBitrate]() {
        reply->deleteLater();
        QVariantMap info;
        if (reply->error() != QNetworkReply::NoError) {
            // PlaybackInfo failed → fall back to direct play.
            m_playSessionId.clear();
            m_mediaSourceId = srcId;
            m_transcoding = false;
            info[QStringLiteral("url")] = streamUrl(itemId, srcId).toString();
            info[QStringLiteral("isTranscode")] = false;
            Q_EMIT streamReady(requestTag, info);
            return;
        }
        const QJsonObject resp = QJsonDocument::fromJson(reply->readAll()).object();
        m_playSessionId = resp.value(QStringLiteral("PlaySessionId")).toString();
        const QJsonArray sources = resp.value(QStringLiteral("MediaSources")).toArray();
        const QJsonObject ms = sources.isEmpty() ? QJsonObject() : sources.first().toObject();
        m_mediaSourceId = ms.value(QStringLiteral("Id")).toString();
        if (m_mediaSourceId.isEmpty())
            m_mediaSourceId = itemId;

        const QString transcodingUrl = ms.value(QStringLiteral("TranscodingUrl")).toString();
        const bool supportsDirect = ms.value(QStringLiteral("SupportsDirectPlay")).toBool()
                                  || ms.value(QStringLiteral("SupportsDirectStream")).toBool();

        QString url;
        bool isTranscode = false;
        if (maxBitrate <= 0 && supportsDirect) {
            url = streamUrl(itemId, srcId).toString();       // Auto + fits → direct
        } else if (!transcodingUrl.isEmpty()) {
            url = m_serverUrl + transcodingUrl;              // server-provided HLS transcode
            isTranscode = true;
        } else {
            url = streamUrl(itemId, srcId).toString();       // last-resort direct
        }
        m_transcoding = isTranscode;
        info[QStringLiteral("url")] = url;
        info[QStringLiteral("isTranscode")] = isTranscode;
        info[QStringLiteral("playSessionId")] = m_playSessionId;
        Q_EMIT streamReady(requestTag, info);
    });
}

// --- progress reporting -----------------------------------------------------

void JellyfinClient::reportPlaybackStart(const QString &itemId)
{
    QJsonObject body{{QStringLiteral("ItemId"), itemId}};
    if (!m_playSessionId.isEmpty()) body[QStringLiteral("PlaySessionId")] = m_playSessionId;
    if (!m_mediaSourceId.isEmpty()) body[QStringLiteral("MediaSourceId")] = m_mediaSourceId;
    QNetworkReply *reply = post(QStringLiteral("/Sessions/Playing"), QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
}

void JellyfinClient::reportPlaybackProgress(const QString &itemId, qint64 positionTicks, bool paused)
{
    QJsonObject body{
        {QStringLiteral("ItemId"), itemId},
        {QStringLiteral("PositionTicks"), positionTicks},
        {QStringLiteral("IsPaused"), paused},
    };
    if (!m_playSessionId.isEmpty()) body[QStringLiteral("PlaySessionId")] = m_playSessionId;
    if (!m_mediaSourceId.isEmpty()) body[QStringLiteral("MediaSourceId")] = m_mediaSourceId;
    QNetworkReply *reply = post(QStringLiteral("/Sessions/Playing/Progress"), QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
}

void JellyfinClient::reportPlaybackStopped(const QString &itemId, qint64 positionTicks)
{
    QJsonObject body{
        {QStringLiteral("ItemId"), itemId},
        {QStringLiteral("PositionTicks"), positionTicks},
    };
    if (!m_playSessionId.isEmpty()) body[QStringLiteral("PlaySessionId")] = m_playSessionId;
    if (!m_mediaSourceId.isEmpty()) body[QStringLiteral("MediaSourceId")] = m_mediaSourceId;
    QNetworkReply *reply = post(QStringLiteral("/Sessions/Playing/Stopped"), QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);

    // Free the server-side transcode if one was running.
    if (m_transcoding && !m_playSessionId.isEmpty()) {
        QNetworkReply *d = del(QStringLiteral("/Videos/ActiveEncodings?deviceId=%1&playSessionId=%2")
                                   .arg(m_deviceId, m_playSessionId));
        connect(d, &QNetworkReply::finished, d, &QNetworkReply::deleteLater);
    }
    m_transcoding = false;
    m_playSessionId.clear();
    m_mediaSourceId.clear();
}

// --- user data -------------------------------------------------------------

void JellyfinClient::setFavorite(const QString &itemId, bool favorite)
{
    const QString path = QStringLiteral("/Users/%1/FavoriteItems/%2").arg(m_userId, itemId);
    QNetworkReply *reply = favorite ? post(path, QByteArray()) : del(path);
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
}

void JellyfinClient::setWatched(const QString &itemId, bool watched)
{
    const QString path = QStringLiteral("/Users/%1/PlayedItems/%2").arg(m_userId, itemId);
    QNetworkReply *reply = watched ? post(path, QByteArray()) : del(path);
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
}

void JellyfinClient::copyStreamUrl(const QString &itemId) const
{
    if (QClipboard *cb = QGuiApplication::clipboard())
        cb->setText(streamUrl(itemId).toString());
}

void JellyfinClient::changePassword(const QString &currentPw, const QString &newPw)
{
    const QJsonObject body{
        {QStringLiteral("CurrentPw"), currentPw},
        {QStringLiteral("NewPw"), newPw},
    };
    QNetworkReply *reply = post(QStringLiteral("/Users/%1/Password").arg(m_userId),
                                QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError)
            Q_EMIT passwordChanged(false, reply->errorString());
        else
            Q_EMIT passwordChanged(true, tr("Password updated"));
    });
}
