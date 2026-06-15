#include "AppConfig.h"

#include "Paths.h"

#include <QFile>
#include <QSettings>

AppConfig::AppConfig(QObject *parent)
    : QObject(parent)
{
}

QString AppConfig::version() const
{
    return QStringLiteral(PROJECT_VERSION);
}

QString AppConfig::mpvConfPath() const
{
    return Paths::configDir() + QStringLiteral("/mpv.conf");
}

QVariant AppConfig::value(const QString &key, const QVariant &def) const
{
    return QSettings().value(key, def);
}

void AppConfig::setValue(const QString &key, const QVariant &val)
{
    QSettings().setValue(key, val);
}

QString AppConfig::readMpvConf() const
{
    Paths::ensureDefaultMpvConfig();
    QFile f(mpvConfPath());
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }
    return QString::fromUtf8(f.readAll());
}

bool AppConfig::writeMpvConf(const QString &text) const
{
    QFile f(mpvConfPath());
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        return false;
    }
    f.write(text.toUtf8());
    return true;
}
