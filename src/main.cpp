#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>

#include <clocale>

int main(int argc, char *argv[])
{
    // Option A embeds mpv in our window via mpv's `--wid`, which is X11-only. So
    // the whole app must run on XWayland, and mpv must NOT see a Wayland display
    // (or its VO auto-detection picks the native Wayland backend, ignores the
    // wid, and opens its own standalone window). Force both before any Qt init.
    qputenv("QT_QPA_PLATFORM", "xcb");
    qunsetenv("WAYLAND_DISPLAY");

    // The QML scene graph runs on OpenGL; mpv renders separately with Vulkan
    // into its own embedded window (see MpvVideoItem), composited behind the Qt
    // window. The window needs an alpha channel so the video shows through the
    // transparent player region — enable it before the first QQuickWindow.
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QQuickWindow::setDefaultAlphaBuffer(true);

    // QApplication (not QGuiApplication): the mpv video surface is hosted in a
    // native QWidget window.
    QApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("jellyfin-desktop"));
    QGuiApplication::setOrganizationName(QStringLiteral("jellyfin-desktop")); // QSettings path
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

    engine.loadFromModule("JellyfinDesktop", "Main");

    return app.exec();
}
