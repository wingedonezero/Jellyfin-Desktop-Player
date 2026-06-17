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
    Q_PROPERTY(bool isAdmin READ isAdmin NOTIFY authenticatedChanged)
    Q_PROPERTY(QVariantMap userConfig READ userConfig NOTIFY userConfigChanged)

public:
    explicit JellyfinClient(QObject *parent = nullptr);

    QString serverUrl() const { return m_serverUrl; }
    void setServerUrl(const QString &url);

    bool isAuthenticated() const { return !m_token.isEmpty(); }
    QString userName() const { return m_userName; }
    bool isAdmin() const { return m_isAdmin; }
    QVariantMap userConfig() const { return m_userConfig; }

    // Raw GET for admin/dashboard endpoints — emits jsonReady(tag, <array|object>).
    Q_INVOKABLE void getJson(const QString &path, const QString &requestTag);

    // --- auth ---
    Q_INVOKABLE void authenticate(const QString &username, const QString &password);
    Q_INVOKABLE void logout();
    Q_INVOKABLE bool restoreSession(); // load a saved server+token; true if signed back in

    // --- browse (each emits itemsReady with a requestTag to route the result) ---
    Q_INVOKABLE void fetchUserViews(const QString &requestTag = QStringLiteral("views"));
    Q_INVOKABLE void fetchResume(const QString &requestTag = QStringLiteral("resume"));
    Q_INVOKABLE void fetchNextUp(const QString &requestTag = QStringLiteral("nextup"),
                                 const QString &seriesId = QString());
    Q_INVOKABLE void fetchLatest(const QString &parentId,
                                 const QString &requestTag = QStringLiteral("latest"));
    Q_INVOKABLE void fetchItems(const QString &parentId,
                                const QString &requestTag = QStringLiteral("items"),
                                const QString &sortBy = QStringLiteral("SortName"),
                                const QString &sortOrder = QStringLiteral("Ascending"),
                                const QString &extraQuery = QString()); // &Filters=/&GenreIds=/&Recursive=true/...
    Q_INVOKABLE void fetchItem(const QString &itemId,
                               const QString &requestTag = QStringLiteral("item"));
    Q_INVOKABLE void fetchSeasons(const QString &seriesId,
                                  const QString &requestTag = QStringLiteral("seasons"));
    Q_INVOKABLE void fetchEpisodes(const QString &seriesId, const QString &seasonId,
                                   const QString &requestTag = QStringLiteral("episodes"),
                                   const QString &startItemId = QString());
    Q_INVOKABLE void fetchSimilar(const QString &itemId,
                                  const QString &requestTag = QStringLiteral("similar"));
    Q_INVOKABLE void fetchFavorites(const QString &requestTag = QStringLiteral("favorites"));
    Q_INVOKABLE void search(const QString &query,
                            const QString &requestTag = QStringLiteral("search"));
    Q_INVOKABLE void fetchByPerson(const QString &personId,
                                   const QString &requestTag = QStringLiteral("person"));
    Q_INVOKABLE void fetchGenres(const QString &parentId,
                                 const QString &requestTag = QStringLiteral("genres"));
    Q_INVOKABLE void fetchStudios(const QString &parentId,
                                  const QString &requestTag = QStringLiteral("studios"));
    Q_INVOKABLE void fetchCollections(const QString &requestTag = QStringLiteral("collections"));
    Q_INVOKABLE void fetchUpcoming(const QString &requestTag = QStringLiteral("upcoming"));
    // /Movies/Recommendations → emits categoriesReady(tag, [{title, items:[...]}, ...])
    Q_INVOKABLE void fetchRecommendations(const QString &parentId,
                                          const QString &requestTag = QStringLiteral("recommendations"));

    // --- url helpers (usable directly from QML Image / the player) ---
    Q_INVOKABLE QUrl imageUrl(const QString &itemId,
                              const QString &imageType = QStringLiteral("Primary"),
                              int maxHeight = 0,
                              const QString &tag = QString()) const;
    Q_INVOKABLE QUrl streamUrl(const QString &itemId) const;
    // One trickplay tile sheet (a grid of thumbnails) at the given resolution width.
    Q_INVOKABLE QUrl trickplayUrl(const QString &itemId, int width, int index) const;
    // Media segments (intro/outro/recap/preview/commercial) for skip prompts.
    // includeTypes = comma-separated MediaSegmentType names. Emits mediaSegmentsReady.
    Q_INVOKABLE void fetchMediaSegments(const QString &itemId, const QString &includeTypes);

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

    // --- user configuration (server-side prefs: audio/subtitle language + mode, ...) ---
    Q_INVOKABLE void fetchUserConfig();
    Q_INVOKABLE void setUserConfig(const QString &key, const QVariant &value);

    // Quick Connect: authorize a code shown on another device (this user must be signed in).
    Q_INVOKABLE void authorizeQuickConnect(const QString &code);

    // Server actions (admin) — destructive; the UI confirms before calling these.
    Q_INVOKABLE void scanAllLibraries();
    Q_INVOKABLE void restartServer();
    Q_INVOKABLE void shutdownServer();
    Q_INVOKABLE void runScheduledTask(const QString &taskId);
    Q_INVOKABLE void stopScheduledTask(const QString &taskId);
    Q_INVOKABLE void setUserPolicy(const QString &userId, const QVariantMap &policy);
    Q_INVOKABLE void deleteUser(const QString &userId);
    Q_INVOKABLE void createUser(const QString &name, const QString &password); // POST /Users/New
    Q_INVOKABLE void setUserPassword(const QString &userId, const QString &newPw, bool reset); // admin set/reset another user's password
    // Devices / API keys / plugins / tasks / library refresh (fire-and-forget; UI confirms first)
    Q_INVOKABLE void renameDevice(const QString &deviceId, const QString &customName);
    Q_INVOKABLE void deleteDevice(const QString &deviceId);
    Q_INVOKABLE void createApiKey(const QString &app);
    Q_INVOKABLE void revokeApiKey(const QString &accessToken);
    Q_INVOKABLE void updateTaskTriggers(const QString &taskId, const QVariantList &triggers);
    Q_INVOKABLE void refreshItem(const QString &itemId);
    Q_INVOKABLE void setPluginEnabled(const QString &pluginId, const QString &version, bool enabled);
    Q_INVOKABLE void uninstallPlugin(const QString &pluginId, const QString &version);
    Q_INVOKABLE void installPackage(const QString &name, const QString &guid, const QString &version, const QString &repoUrl);
    Q_INVOKABLE void setRepositories(const QVariantList &repos);
    // Raw-text GET (e.g. a log file) → textReady(tag, content)
    Q_INVOKABLE void getText(const QString &path, const QString &requestTag);
    // Generic JSON POST — server-config editors POST the WHOLE config object back.
    Q_INVOKABLE void postJson(const QString &path, const QVariantMap &body);

    // Libraries (virtual folders) — admin; the UI confirms before calling these.
    Q_INVOKABLE void addVirtualFolder(const QString &name, const QString &collectionType, const QString &path);
    Q_INVOKABLE void removeVirtualFolder(const QString &name);
    Q_INVOKABLE void renameVirtualFolder(const QString &name, const QString &newName);
    Q_INVOKABLE void addMediaPath(const QString &name, const QString &path);
    Q_INVOKABLE void removeMediaPath(const QString &name, const QString &path);
    Q_INVOKABLE void updateLibraryOptions(const QString &id, const QVariantMap &options);

    // --- detail extras + collection/playlist actions ---
    Q_INVOKABLE void fetchSpecialFeatures(const QString &itemId,
                                          const QString &requestTag = QStringLiteral("extras"));
    Q_INVOKABLE void fetchPlaylists(const QString &requestTag = QStringLiteral("playlists"));
    Q_INVOKABLE void addToPlaylist(const QString &playlistId, const QString &itemId);
    Q_INVOKABLE void createPlaylist(const QString &name, const QString &itemId);
    Q_INVOKABLE void addToCollection(const QString &collectionId, const QString &itemId);
    Q_INVOKABLE void createCollection(const QString &name, const QString &itemId);

Q_SIGNALS:
    void serverUrlChanged();
    void authenticatedChanged();
    void authenticationFailed(const QString &reason);
    void itemsReady(const QString &requestTag, const QVariantList &items);
    void mediaSegmentsReady(const QString &itemId, const QVariantList &segments);
    void streamReady(const QString &requestTag, const QVariantMap &info);
    void jsonReady(const QString &requestTag, const QVariant &data);
    void textReady(const QString &requestTag, const QString &content);
    void categoriesReady(const QString &requestTag, const QVariantList &categories);
    void passwordChanged(bool ok, const QString &message);
    void userConfigChanged();
    void quickConnectResult(bool ok, const QString &message);
    void errorOccurred(const QString &message);

private:
    QString authHeader() const; // "MediaBrowser Token=..., Client=..., ..."
    QNetworkReply *get(const QString &pathWithQuery) const;
    QNetworkReply *post(const QString &pathWithQuery, const QByteArray &json) const;
    QNetworkReply *del(const QString &pathWithQuery) const;
    void requestItems(const QString &pathWithQuery, const QString &requestTag);
    void getJsonAttempt(const QString &path, const QString &requestTag, int triesLeft);
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
    bool m_isAdmin = false;
    QVariantMap m_userConfig;

    // current playback session (for progress reports + transcode teardown)
    QString m_playSessionId;
    QString m_mediaSourceId;
    bool m_transcoding = false;
};
