#include "MpvVideoItem.h"

#include "Paths.h"

#include <QByteArray>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QPointer>
#include <QQuickWindow>
#include <QVector>
#include <QtGlobal>

// ----------------------------------------------------------------------------
// MpvRenderer — lives on the Qt scene-graph render thread. Owns nothing but a
// shared ref to the render resources; creates the mpv render context lazily
// (the first time the FBO exists, with a current GL context) and frees it in
// its destructor (still on the render thread). This is the canonical mpv +
// OpenGL render-API sequence.
// ----------------------------------------------------------------------------

class MpvRenderer : public QQuickFramebufferObject::Renderer
{
public:
    explicit MpvRenderer(std::shared_ptr<MpvRenderResources> res)
        : m_res(std::move(res))
    {
    }

    ~MpvRenderer() override
    {
        if (m_res) {
            m_res->freeContext();
        }
    }

    void synchronize(QQuickFramebufferObject *item) override
    {
        // Runs while the GUI thread is blocked — safe to cache the item.
        m_item = static_cast<MpvVideoItem *>(item);
    }

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        if (m_res && !m_res->renderCtx) {
            createMpvRenderContext();
        }
        return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
    }

    void render() override
    {
        if (!m_res || !m_res->renderCtx) {
            return;
        }

        QOpenGLFramebufferObject *fbo = framebufferObject();
        mpv_opengl_fbo mpfbo{static_cast<int>(fbo->handle()), fbo->width(), fbo->height(), 0};
        int flipY = 0;

        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_OPENGL_FBO, &mpfbo},
            {MPV_RENDER_PARAM_FLIP_Y, &flipY},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        mpv_render_context_render(m_res->renderCtx, params);
    }

private:
    static void *getProcAddress(void *ctx, const char *name)
    {
        Q_UNUSED(ctx)
        QOpenGLContext *glctx = QOpenGLContext::currentContext();
        if (!glctx) {
            return nullptr;
        }
        return reinterpret_cast<void *>(glctx->getProcAddress(QByteArray(name)));
    }

    static void onMpvRedraw(void *ctx)
    {
        // Called from an mpv render thread: bounce a repaint onto the GUI thread.
        auto *self = static_cast<MpvRenderer *>(ctx);
        if (self->m_item) {
            QMetaObject::invokeMethod(self->m_item.data(), "scheduleUpdate", Qt::QueuedConnection);
        }
    }

    void createMpvRenderContext()
    {
        mpv_opengl_init_params glInit{getProcAddress, nullptr};
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
            {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit},
            // TODO: pass MPV_RENDER_PARAM_WL_DISPLAY / X11_DISPLAY here when we
            // wire up hardware decoding; not needed for basic GL rendering.
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };

        if (mpv_render_context_create(&m_res->renderCtx, m_res->mpv->handle, params) < 0) {
            qWarning("MpvVideoItem: failed to create mpv render context");
            m_res->renderCtx = nullptr;
            return;
        }
        mpv_render_context_set_update_callback(m_res->renderCtx, onMpvRedraw, this);
    }

    std::shared_ptr<MpvRenderResources> m_res;
    QPointer<MpvVideoItem> m_item;
};

// ----------------------------------------------------------------------------
// MpvVideoItem
// ----------------------------------------------------------------------------

MpvVideoItem::MpvVideoItem(QQuickItem *parent)
    : QQuickFramebufferObject(parent)
{
    if (QQuickWindow::graphicsApi() != QSGRendererInterface::OpenGL) {
        qWarning("MpvVideoItem: Qt Quick scene graph is not OpenGL. Call "
                 "QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL) "
                 "before the first window, or mpv cannot render.");
    }

    mpv_handle *handle = mpv_create();
    if (!handle) {
        qFatal("MpvVideoItem: mpv_create() failed");
    }

    // Load user config from a standard, editable location
    // (~/.config/jellyfin-desktop/mpv.conf), generating a documented base file
    // on first run. libmpv does not load config by default, so opt in here.
    Paths::ensureDefaultMpvConfig();
    const QByteArray configDir = Paths::configDir().toUtf8();
    mpv_set_option_string(handle, "config-dir", configDir.constData());
    mpv_set_option_string(handle, "config", "yes");
    mpv_set_option_string(handle, "terminal", "no");

    if (mpv_initialize(handle) < 0) {
        mpv_terminate_destroy(handle);
        qFatal("MpvVideoItem: mpv_initialize() failed");
    }

    // The render-API output MUST be "libmpv" regardless of mpv.conf, or video
    // can't render into our FBO. Set it as a property after the config loads so
    // a stray `vo=` in the user's mpv.conf can't break embedding.
    mpv_set_property_string(handle, "vo", "libmpv");

    mpv_set_wakeup_callback(handle, onMpvWakeup, this);

    m_mpv = std::make_shared<MpvHandle>(handle);
    m_resources = std::make_shared<MpvRenderResources>(m_mpv);
}

MpvVideoItem::~MpvVideoItem()
{
    if (m_mpv && m_mpv->handle) {
        mpv_set_wakeup_callback(m_mpv->handle, nullptr, nullptr);
    }
    // The render context is freed by ~MpvRenderer on the render thread; the mpv
    // handle outlives it because MpvRenderResources holds a ref to MpvHandle.
}

QQuickFramebufferObject::Renderer *MpvVideoItem::createRenderer() const
{
    return new MpvRenderer(m_resources);
}

void MpvVideoItem::play(const QString &url)
{
    command({QStringLiteral("loadfile"), url});
}

void MpvVideoItem::command(const QStringList &args)
{
    if (!m_mpv || !m_mpv->handle) {
        return;
    }

    QVector<QByteArray> bytes;
    bytes.reserve(args.size());
    for (const QString &arg : args) {
        bytes.append(arg.toUtf8());
    }

    QVector<const char *> argv;
    argv.reserve(bytes.size() + 1);
    for (const QByteArray &b : bytes) {
        argv.append(b.constData());
    }
    argv.append(nullptr);

    mpv_command(m_mpv->handle, argv.data());
}

void MpvVideoItem::setOption(const QString &name, const QString &value)
{
    if (m_mpv && m_mpv->handle) {
        mpv_set_property_string(m_mpv->handle, name.toUtf8().constData(), value.toUtf8().constData());
    }
}

QString MpvVideoItem::queryProperty(const QString &name) const
{
    if (!m_mpv || !m_mpv->handle) {
        return {};
    }
    char *value = mpv_get_property_string(m_mpv->handle, name.toUtf8().constData());
    if (!value) {
        return {};
    }
    const QString result = QString::fromUtf8(value);
    mpv_free(value);
    return result;
}

void MpvVideoItem::onMpvWakeup(void *ctx)
{
    QMetaObject::invokeMethod(static_cast<MpvVideoItem *>(ctx), "pumpEvents", Qt::QueuedConnection);
}

void MpvVideoItem::pumpEvents()
{
    if (!m_mpv || !m_mpv->handle) {
        return;
    }
    while (true) {
        mpv_event *event = mpv_wait_event(m_mpv->handle, 0);
        if (event->event_id == MPV_EVENT_NONE) {
            break;
        }
        switch (event->event_id) {
        case MPV_EVENT_FILE_LOADED:
            Q_EMIT fileLoaded();
            break;
        case MPV_EVENT_END_FILE: {
            auto *ef = static_cast<mpv_event_end_file *>(event->data);
            Q_EMIT endFile(ef ? QString::number(ef->reason) : QString());
            break;
        }
        default:
            break;
        }
    }
}

void MpvVideoItem::scheduleUpdate()
{
    update();
}
