#pragma once

#include <QtQml/qqmlregistration.h>

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantList>

class QNetworkAccessManager;
class QNetworkReply;
class QJsonObject;

// ----------------------------------------------------------------------------
// JellyfinClient — our own Jellyfin client over Qt's networking. No SDK.
//
// Talks to a Jellyfin server's REST API: authenticate, browse libraries/items,
// build image + direct-play stream URLs, and report playback progress. Results
// are emitted as QVariantList of QVariantMap so QML can consume them directly
// (typed models come with the real UI). Everything is async + signal-based.
// ----------------------------------------------------------------------------

class JellyfinClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString serverUrl READ serverUrl WRITE setServerUrl NOTIFY serverUrlChanged)
    Q_PROPERTY(bool authenticated READ isAuthenticated NOTIFY authenticatedChanged)
    Q_PROPERTY(QString userName READ userName NOTIFY authenticatedChanged)

public:
    explicit JellyfinClient(QObject *parent = nullptr);

    QString serverUrl() const { return m_serverUrl; }
    void setServerUrl(const QString &url);

    bool isAuthenticated() const { return !m_token.isEmpty(); }
    QString userName() const { return m_userName; }

    // --- auth ---
    Q_INVOKABLE void authenticate(const QString &username, const QString &password);
    Q_INVOKABLE void logout();
    Q_INVOKABLE bool restoreSession(); // load a saved server+token; true if signed back in

    // --- browse (each emits itemsReady with a requestTag to route the result) ---
    Q_INVOKABLE void fetchUserViews(const QString &requestTag = QStringLiteral("views"));
    Q_INVOKABLE void fetchResume(const QString &requestTag = QStringLiteral("resume"));
    Q_INVOKABLE void fetchNextUp(const QString &requestTag = QStringLiteral("nextup"));
    Q_INVOKABLE void fetchLatest(const QString &parentId,
                                 const QString &requestTag = QStringLiteral("latest"));
    Q_INVOKABLE void fetchItems(const QString &parentId,
                                const QString &requestTag = QStringLiteral("items"),
                                const QString &sortBy = QStringLiteral("SortName"),
                                const QString &sortOrder = QStringLiteral("Ascending"));
    Q_INVOKABLE void fetchItem(const QString &itemId,
                               const QString &requestTag = QStringLiteral("item"));
    Q_INVOKABLE void fetchSeasons(const QString &seriesId,
                                  const QString &requestTag = QStringLiteral("seasons"));
    Q_INVOKABLE void fetchEpisodes(const QString &seriesId, const QString &seasonId,
                                   const QString &requestTag = QStringLiteral("episodes"));
    Q_INVOKABLE void fetchSimilar(const QString &itemId,
                                  const QString &requestTag = QStringLiteral("similar"));
    Q_INVOKABLE void fetchFavorites(const QString &requestTag = QStringLiteral("favorites"));
    Q_INVOKABLE void search(const QString &query,
                            const QString &requestTag = QStringLiteral("search"));
    Q_INVOKABLE void fetchByPerson(const QString &personId,
                                   const QString &requestTag = QStringLiteral("person"));
    Q_INVOKABLE void fetchGenres(const QString &parentId,
                                 const QString &requestTag = QStringLiteral("genres"));
    Q_INVOKABLE void fetchItemsInGenre(const QString &parentId, const QString &genreId,
                                       const QString &requestTag = QStringLiteral("genreItems"),
                                       const QString &sortBy = QStringLiteral("SortName"),
                                       const QString &sortOrder = QStringLiteral("Ascending"));

    // --- url helpers (usable directly from QML Image / the player) ---
    Q_INVOKABLE QUrl imageUrl(const QString &itemId,
                              const QString &imageType = QStringLiteral("Primary"),
                              int maxHeight = 0,
                              const QString &tag = QString()) const;
    Q_INVOKABLE QUrl streamUrl(const QString &itemId) const;

    // Resolve a playable URL via /Items/{id}/PlaybackInfo: direct-play when the
    // source fits (maxBitrate <= 0 = Auto), otherwise an HLS transcode URL.
    // Emits streamReady(requestTag, {url, isTranscode, playSessionId}).
    Q_INVOKABLE void requestStream(const QString &itemId, int maxBitrate, qint64 startTicks,
                                   const QString &requestTag = QStringLiteral("stream"));

    // --- playback progress reporting ---
    Q_INVOKABLE void reportPlaybackStart(const QString &itemId);
    Q_INVOKABLE void reportPlaybackProgress(const QString &itemId, qint64 positionTicks, bool paused);
    Q_INVOKABLE void reportPlaybackStopped(const QString &itemId, qint64 positionTicks);

    // --- user data (fire-and-forget; UI updates optimistically) ---
    Q_INVOKABLE void setFavorite(const QString &itemId, bool favorite);
    Q_INVOKABLE void setWatched(const QString &itemId, bool watched);
    Q_INVOKABLE void copyStreamUrl(const QString &itemId) const; // → clipboard
    Q_INVOKABLE void changePassword(const QString &currentPw, const QString &newPw);

Q_SIGNALS:
    void serverUrlChanged();
    void authenticatedChanged();
    void authenticationFailed(const QString &reason);
    void itemsReady(const QString &requestTag, const QVariantList &items);
    void streamReady(const QString &requestTag, const QVariantMap &info);
    void passwordChanged(bool ok, const QString &message);
    void errorOccurred(const QString &message);

private:
    QString authHeader() const; // "MediaBrowser Token=..., Client=..., ..."
    QNetworkReply *get(const QString &pathWithQuery) const;
    QNetworkReply *post(const QString &pathWithQuery, const QByteArray &json) const;
    QNetworkReply *del(const QString &pathWithQuery) const;
    void requestItems(const QString &pathWithQuery, const QString &requestTag);
    void saveSession() const;  // persist server+token to QSettings
    static QVariantList parseItems(const QByteArray &json);
    static QVariantMap parseItem(const QJsonObject &o);
    QJsonObject deviceProfile() const; // capabilities sent to PlaybackInfo

    QNetworkAccessManager *m_net;
    QString m_serverUrl; // no trailing slash
    QString m_token;
    QString m_userId;
    QString m_userName;
    QString m_deviceId;
    QString m_deviceName;

    // current playback session (for progress reports + transcode teardown)
    QString m_playSessionId;
    QString m_mediaSourceId;
    bool m_transcoding = false;
};
