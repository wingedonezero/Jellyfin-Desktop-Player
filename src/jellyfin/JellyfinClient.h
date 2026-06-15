#pragma once

#include <QtQml/qqmlregistration.h>

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantList>

class QNetworkAccessManager;
class QNetworkReply;

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

    // --- browse (each emits itemsReady with a requestTag to route the result) ---
    Q_INVOKABLE void fetchUserViews(const QString &requestTag = QStringLiteral("views"));
    Q_INVOKABLE void fetchResume(const QString &requestTag = QStringLiteral("resume"));
    Q_INVOKABLE void fetchItems(const QString &parentId,
                                const QString &requestTag = QStringLiteral("items"));

    // --- url helpers (usable directly from QML Image / the player) ---
    Q_INVOKABLE QUrl imageUrl(const QString &itemId,
                              const QString &imageType = QStringLiteral("Primary"),
                              int maxHeight = 0) const;
    Q_INVOKABLE QUrl streamUrl(const QString &itemId) const;

    // --- playback progress reporting ---
    Q_INVOKABLE void reportPlaybackStart(const QString &itemId);
    Q_INVOKABLE void reportPlaybackProgress(const QString &itemId, qint64 positionTicks, bool paused);
    Q_INVOKABLE void reportPlaybackStopped(const QString &itemId, qint64 positionTicks);

Q_SIGNALS:
    void serverUrlChanged();
    void authenticatedChanged();
    void authenticationFailed(const QString &reason);
    void itemsReady(const QString &requestTag, const QVariantList &items);
    void errorOccurred(const QString &message);

private:
    QString authHeader() const; // "MediaBrowser Token=..., Client=..., ..."
    QNetworkReply *get(const QString &pathWithQuery) const;
    QNetworkReply *post(const QString &pathWithQuery, const QByteArray &json) const;
    void requestItems(const QString &pathWithQuery, const QString &requestTag);
    static QVariantList parseItems(const QByteArray &json);

    QNetworkAccessManager *m_net;
    QString m_serverUrl; // no trailing slash
    QString m_token;
    QString m_userId;
    QString m_userName;
    QString m_deviceId;
    QString m_deviceName;
};
