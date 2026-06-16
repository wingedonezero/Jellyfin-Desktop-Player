#include "ScreenSaverInhibitor.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDebug>

namespace {
const QString kAppName = QStringLiteral("Jellyfin Desktop");
const QString kReason = QStringLiteral("Playing video");
} // namespace

ScreenSaverInhibitor::ScreenSaverInhibitor(QObject *parent)
    : QObject(parent)
{
    // freedesktop inhibition endpoints, in priority order. Both expose
    // Inhibit(string app, string reason) -> uint cookie / UnInhibit(uint).
    m_targets = {
        { QStringLiteral("org.freedesktop.ScreenSaver"),
          QStringLiteral("/org/freedesktop/ScreenSaver"),
          QStringLiteral("org.freedesktop.ScreenSaver"), 0, false },
        { QStringLiteral("org.freedesktop.PowerManagement.Inhibit"),
          QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"),
          QStringLiteral("org.freedesktop.PowerManagement.Inhibit"), 0, false },
    };
}

ScreenSaverInhibitor::~ScreenSaverInhibitor()
{
    release();
}

void ScreenSaverInhibitor::setInhibited(bool on)
{
    if (on == m_inhibited)
        return;
    m_inhibited = on;
    if (on)
        acquire();
    else
        release();
    emit inhibitedChanged();
}

void ScreenSaverInhibitor::acquire()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning() << "[inhibit] no D-Bus session bus; screen may sleep during playback";
        return;
    }
    for (Target &t : m_targets) {
        if (t.held)
            continue;
        QDBusInterface iface(t.service, t.path, t.iface, bus);
        if (!iface.isValid())
            continue; // service absent on this desktop — fall back to the next
        QDBusReply<uint> reply = iface.call(QStringLiteral("Inhibit"), kAppName, kReason);
        if (reply.isValid()) {
            t.cookie = reply.value();
            t.held = true;
            qInfo().noquote() << "[inhibit] held" << t.service << "(cookie" << t.cookie << ")";
        } else {
            qWarning() << "[inhibit]" << t.service << "Inhibit failed:" << reply.error().message();
        }
    }
}

void ScreenSaverInhibitor::release()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    for (Target &t : m_targets) {
        if (!t.held)
            continue;
        if (bus.isConnected()) {
            QDBusInterface iface(t.service, t.path, t.iface, bus);
            if (iface.isValid())
                iface.call(QStringLiteral("UnInhibit"), t.cookie);
        }
        qInfo().noquote() << "[inhibit] released" << t.service;
        t.cookie = 0;
        t.held = false;
    }
}
