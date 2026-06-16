#pragma once

#include <QtQml/qqmlregistration.h>

#include <QObject>
#include <QList>
#include <QString>

// ----------------------------------------------------------------------------
// ScreenSaverInhibitor — keep the screen + monitors awake while video plays.
//
// We embed libmpv via the GL render API, so mpv owns no window of its own and
// its built-in `stop-screensaver` can't reach the compositor. The host must
// inhibit instead (as every embedded-mpv player does). We hold the freedesktop
// D-Bus inhibitions while a file is actively playing (released on pause/stop,
// matching mpv): org.freedesktop.ScreenSaver (lock/blank, provided by kwin) and
// org.freedesktop.PowerManagement.Inhibit (idle screen-off/suspend, PowerDevil).
// Both are best-effort — absent services are skipped (graceful fallback), and a
// session-global inhibition keeps *all* monitors awake, not just the video one.
// ----------------------------------------------------------------------------

class ScreenSaverInhibitor : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool inhibited READ inhibited WRITE setInhibited NOTIFY inhibitedChanged)

public:
    explicit ScreenSaverInhibitor(QObject *parent = nullptr);
    ~ScreenSaverInhibitor() override;

    bool inhibited() const { return m_inhibited; }
    void setInhibited(bool on);

Q_SIGNALS:
    void inhibitedChanged();

private:
    void acquire();
    void release();

    struct Target {
        QString service;
        QString path;
        QString iface;
        uint cookie = 0;
        bool held = false;
    };

    QList<Target> m_targets;
    bool m_inhibited = false;
};
