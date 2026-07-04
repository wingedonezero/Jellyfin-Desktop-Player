#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>

#include <clocale>

int main(int argc, char *argv[])
{
    // The QML scene graph runs on OpenGL; mpv renders separately with Vulkan
    // (gpu-next) into a wl_subsurface of our window (see MpvVideoItem) on native
    // Wayland, composited *below* the Qt window. The window needs an alpha
    // channel so the video shows through the transparent player region — enable
    // it before the first QQuickWindow. (On an X11 session the item falls back
    // to a child-window embed.)
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QQuickWindow::setDefaultAlphaBuffer(true);

    // QApplication (not QGuiApplication): the mpv video surface is hosted in a
    // native QWidget window.
    QApplication app(argc, argv);
    // JFD_PROFILE=<name> sandboxes ALL persistent state (QSettings session +
    // settings, and the AppConfigLocation mpv.conf/input.conf dir) under
    // jellyfin-desktop-<name>, so a dev/test login can never touch the real
    // config. Absent => the normal jellyfin-desktop config.
    QString appName = QStringLiteral("jellyfin-desktop");
    const QString profile = qEnvironmentVariable("JFD_PROFILE");
    if (!profile.isEmpty())
        appName += QLatin1Char('-') + profile;
    QGuiApplication::setApplicationName(appName);
    QGuiApplication::setOrganizationName(appName); // QSettings path
    QGuiApplication::setApplicationVersion(QStringLiteral(PROJECT_VERSION));

    // libmpv requires LC_NUMERIC to be "C", but QGuiApplication initialises the
    // locale from the environment. Reset it before any mpv handle is created.
    std::setlocale(LC_NUMERIC, "C");

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

    // Dev/test convenience: seed the login form and optionally auto-login /
    // auto-play from the environment (JFD_SERVER / JFD_USER / JFD_PASS /
    // JFD_AUTOPLAY). All absent => normal interactive login.
    QQmlContext *ctx = engine.rootContext();
    ctx->setContextProperty(QStringLiteral("initialServer"), qEnvironmentVariable("JFD_SERVER"));
    ctx->setContextProperty(QStringLiteral("initialUser"), qEnvironmentVariable("JFD_USER"));
    ctx->setContextProperty(QStringLiteral("initialPass"), qEnvironmentVariable("JFD_PASS"));
    ctx->setContextProperty(QStringLiteral("autoPlay"), qEnvironmentVariable("JFD_AUTOPLAY") == QLatin1String("1"));
    // JFD_AUTOSTOP=<secs>: back out of playback automatically after N seconds
    // (dev/test hook for the stop → report → refresh path). 0/absent = off.
    ctx->setContextProperty(QStringLiteral("autoStopSecs"), qEnvironmentVariable("JFD_AUTOSTOP").toInt());

    engine.loadFromModule("JellyfinDesktop", "Main");

    return app.exec();
}
