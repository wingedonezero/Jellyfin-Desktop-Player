#include <QGuiApplication>
#include <QQmlApplicationEngine>
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
    QGuiApplication::setApplicationVersion(QStringLiteral(PROJECT_VERSION));

    // libmpv requires LC_NUMERIC to be "C", but QGuiApplication initialises the
    // locale from the environment. Reset it before any mpv handle is created.
    std::setlocale(LC_NUMERIC, "C");

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    engine.loadFromModule("JellyfinDesktop", "Main");

    return app.exec();
}
