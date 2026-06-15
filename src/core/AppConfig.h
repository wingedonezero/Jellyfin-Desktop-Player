#pragma once

#include <QtQml/qqmlregistration.h>

#include <QObject>
#include <QString>
#include <QVariant>

// ----------------------------------------------------------------------------
// AppConfig — app-side settings exposed to QML: QSettings-backed preferences,
// the app version, and direct read/write of the user's mpv.conf (our
// "fully configurable mpv" surface). Instantiated once in Main.
// ----------------------------------------------------------------------------
class AppConfig : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(QString mpvConfPath READ mpvConfPath CONSTANT)

public:
    explicit AppConfig(QObject *parent = nullptr);

    QString version() const;
    QString mpvConfPath() const;

    // generic preference store (keys like "playback/maxBitrate")
    Q_INVOKABLE QVariant value(const QString &key, const QVariant &def = QVariant()) const;
    Q_INVOKABLE void setValue(const QString &key, const QVariant &val);

    // mpv.conf editing (seeds the documented default first if missing)
    Q_INVOKABLE QString readMpvConf() const;
    Q_INVOKABLE bool writeMpvConf(const QString &text) const;
};
