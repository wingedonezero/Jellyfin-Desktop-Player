#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>

#include <clocale>

int main(int argc, char *argv[])
{
    // MpvVideoItem renders through mpv's OpenGL render API into a
    // QQuickFramebufferObject, so the Qt Quick scene graph MUST run on OpenGL.
    // This has to happen before the first QQuickWindow is constructed.
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);

    QGuiApplication app(argc, argv);
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
