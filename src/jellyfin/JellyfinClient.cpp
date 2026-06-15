#include "JellyfinClient.h"

#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
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

        if (m_token.isEmpty() || m_userId.isEmpty()) {
            Q_EMIT authenticationFailed(tr("Server did not return an access token"));
            return;
        }
        Q_EMIT authenticatedChanged();
    });
}

void JellyfinClient::logout()
{
    m_token.clear();
    m_userId.clear();
    m_userName.clear();
    Q_EMIT authenticatedChanged();
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

void JellyfinClient::fetchNextUp(const QString &requestTag)
{
    requestItems(QStringLiteral("/Shows/NextUp?userId=%1&Limit=24&%2&%3")
                     .arg(m_userId, kItemFields, kImageTypes),
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
                                const QString &sortBy, const QString &sortOrder)
{
    requestItems(QStringLiteral("/Users/%1/Items?ParentId=%2&SortBy=%3&SortOrder=%4&%5&%6")
                     .arg(m_userId).arg(parentId).arg(sortBy).arg(sortOrder).arg(kItemFields).arg(kImageTypes),
                 requestTag);
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
    m[QStringLiteral("overview")] = o.value(QStringLiteral("Overview")).toString();
    m[QStringLiteral("productionYear")] = o.value(QStringLiteral("ProductionYear")).toInt();
    m[QStringLiteral("runTimeTicks")] = o.value(QStringLiteral("RunTimeTicks")).toDouble();
    m[QStringLiteral("communityRating")] = o.value(QStringLiteral("CommunityRating")).toDouble();
    m[QStringLiteral("officialRating")] = o.value(QStringLiteral("OfficialRating")).toString();
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
    m[QStringLiteral("hasBackdrop")] = !o.value(QStringLiteral("BackdropImageTags")).toArray().isEmpty();

    // genres
    QVariantList genres;
    const QJsonArray genreArr = o.value(QStringLiteral("Genres")).toArray();
    for (const QJsonValue &g : genreArr) {
        genres.append(g.toString());
    }
    m[QStringLiteral("genres")] = genres;

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
                             const QString &tag) const
{
    QUrl url{m_serverUrl + QStringLiteral("/Items/%1/Images/%2").arg(itemId, imageType)};
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

QUrl JellyfinClient::streamUrl(const QString &itemId) const
{
    // Direct play: mpv handles essentially every codec/container, so we ask the
    // server for the original file (static=true) rather than a transcode.
    QUrl url{m_serverUrl + QStringLiteral("/Videos/%1/stream").arg(itemId)};
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("static"), QStringLiteral("true"));
    q.addQueryItem(QStringLiteral("mediaSourceId"), itemId);
    q.addQueryItem(QStringLiteral("deviceId"), m_deviceId);
    q.addQueryItem(QStringLiteral("api_key"), m_token);
    url.setQuery(q);
    return url;
}

// --- progress reporting -----------------------------------------------------

void JellyfinClient::reportPlaybackStart(const QString &itemId)
{
    const QJsonObject body{{QStringLiteral("ItemId"), itemId}};
    QNetworkReply *reply = post(QStringLiteral("/Sessions/Playing"), QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
}

void JellyfinClient::reportPlaybackProgress(const QString &itemId, qint64 positionTicks, bool paused)
{
    const QJsonObject body{
        {QStringLiteral("ItemId"), itemId},
        {QStringLiteral("PositionTicks"), positionTicks},
        {QStringLiteral("IsPaused"), paused},
    };
    QNetworkReply *reply = post(QStringLiteral("/Sessions/Playing/Progress"), QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
}

void JellyfinClient::reportPlaybackStopped(const QString &itemId, qint64 positionTicks)
{
    const QJsonObject body{
        {QStringLiteral("ItemId"), itemId},
        {QStringLiteral("PositionTicks"), positionTicks},
    };
    QNetworkReply *reply = post(QStringLiteral("/Sessions/Playing/Stopped"), QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
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
