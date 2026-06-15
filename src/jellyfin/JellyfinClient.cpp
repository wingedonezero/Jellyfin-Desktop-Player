#include "JellyfinClient.h"

#include <QClipboard>
#include <QCryptographicHash>
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
    "CommunityRating,OfficialRating,SeriesName");

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
        saveSession();
        Q_EMIT authenticatedChanged();
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
                                   const QString &requestTag)
{
    requestItems(QStringLiteral("/Shows/%1/Episodes?seasonId=%2&userId=%3&%4&%5")
                     .arg(seriesId).arg(seasonId).arg(m_userId).arg(kItemFields).arg(kImageTypes),
                 requestTag);
}

void JellyfinClient::fetchSimilar(const QString &itemId, const QString &requestTag)
{
    requestItems(QStringLiteral("/Items/%1/Similar?userId=%2&Limit=14&%3&%4")
                     .arg(itemId, m_userId, kItemFields, kImageTypes),
                 requestTag);
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

void JellyfinClient::fetchItemsInGenre(const QString &parentId, const QString &genreId,
                                       const QString &requestTag, const QString &sortBy,
                                       const QString &sortOrder)
{
    requestItems(QStringLiteral("/Users/%1/Items?ParentId=%2&GenreIds=%3&Recursive=true"
                                "&SortBy=%4&SortOrder=%5&%6&%7")
                     .arg(m_userId).arg(parentId).arg(genreId).arg(sortBy).arg(sortOrder)
                     .arg(kItemFields).arg(kImageTypes),
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

    // studios + tagline (detail)
    QVariantList studios;
    const QJsonArray studioArr = o.value(QStringLiteral("Studios")).toArray();
    for (const QJsonValue &s : studioArr) {
        studios.append(s.toObject().value(QStringLiteral("Name")).toString());
    }
    m[QStringLiteral("studios")] = studios;
    const QJsonArray taglines = o.value(QStringLiteral("Taglines")).toArray();
    m[QStringLiteral("tagline")] = taglines.isEmpty() ? QString() : taglines.first().toString();

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

QJsonObject JellyfinClient::deviceProfile() const
{
    // mpv direct-plays essentially everything; the transcode target is HLS
    // (h264/aac) so the server can downscale when a bitrate cap forces it.
    const QJsonObject videoDirect{
        {QStringLiteral("Container"), QStringLiteral("mp4,m4v,mkv,webm,avi,mov,ts,m2ts,flv,wmv,asf,mpg,mpeg,3gp,ogv")},
        {QStringLiteral("Type"), QStringLiteral("Video")}};
    const QJsonObject audioDirect{
        {QStringLiteral("Container"), QStringLiteral("mp3,aac,flac,alac,ogg,oga,wav,wma,opus,m4a,mka")},
        {QStringLiteral("Type"), QStringLiteral("Audio")}};
    const QJsonObject hls{
        {QStringLiteral("Container"), QStringLiteral("ts")},
        {QStringLiteral("Type"), QStringLiteral("Video")},
        {QStringLiteral("AudioCodec"), QStringLiteral("aac,mp3")},
        {QStringLiteral("VideoCodec"), QStringLiteral("h264")},
        {QStringLiteral("Context"), QStringLiteral("Streaming")},
        {QStringLiteral("Protocol"), QStringLiteral("hls")},
        {QStringLiteral("MaxAudioChannels"), QStringLiteral("2")},
        {QStringLiteral("MinSegments"), 1},
        {QStringLiteral("BreakOnNonKeyFrames"), true}};
    const auto subtitle = [](const QString &fmt) {
        return QJsonObject{{QStringLiteral("Format"), fmt}, {QStringLiteral("Method"), QStringLiteral("External")}};
    };
    QJsonObject p;
    p[QStringLiteral("DirectPlayProfiles")] = QJsonArray{videoDirect, audioDirect};
    p[QStringLiteral("TranscodingProfiles")] = QJsonArray{hls};
    p[QStringLiteral("CodecProfiles")] = QJsonArray{};
    p[QStringLiteral("ContainerProfiles")] = QJsonArray{};
    p[QStringLiteral("ResponseProfiles")] = QJsonArray{};
    p[QStringLiteral("SubtitleProfiles")] = QJsonArray{
        subtitle(QStringLiteral("srt")), subtitle(QStringLiteral("ass")),
        subtitle(QStringLiteral("subrip")), subtitle(QStringLiteral("vtt"))};
    return p;
}

void JellyfinClient::requestStream(const QString &itemId, int maxBitrate, qint64 startTicks,
                                   const QString &requestTag)
{
    if (maxBitrate <= 0) {
        // Auto: mpv direct-plays the original file — no server transcode, no
        // PlaybackInfo round-trip. (The server reports direct-play unsupported
        // for our generic profile, but mpv handles every codec, so we trust it.)
        m_playSessionId.clear();
        m_mediaSourceId = itemId;
        m_transcoding = false;
        QVariantMap info;
        info[QStringLiteral("url")] = streamUrl(itemId).toString();
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

    const QString path = QStringLiteral("/Items/%1/PlaybackInfo?userId=%2").arg(itemId, m_userId);
    QNetworkReply *reply = post(path, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestTag, itemId, maxBitrate]() {
        reply->deleteLater();
        QVariantMap info;
        if (reply->error() != QNetworkReply::NoError) {
            // PlaybackInfo failed → fall back to direct play.
            m_playSessionId.clear();
            m_mediaSourceId = itemId;
            m_transcoding = false;
            info[QStringLiteral("url")] = streamUrl(itemId).toString();
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
            url = streamUrl(itemId).toString();              // Auto + fits → direct
        } else if (!transcodingUrl.isEmpty()) {
            url = m_serverUrl + transcodingUrl;              // server-provided HLS transcode
            isTranscode = true;
        } else {
            url = streamUrl(itemId).toString();              // last-resort direct
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
