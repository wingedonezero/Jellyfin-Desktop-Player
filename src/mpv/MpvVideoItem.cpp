#include "MpvVideoItem.h"

#include "Paths.h"

#include <QByteArray>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QPointer>
#include <QQuickWindow>
#include <QVariant>
#include <QVector>
#include <QtGlobal>

namespace {
// Recursively convert an mpv_node into a QVariant (used for track-list, etc.).
QVariant nodeToVariant(const mpv_node *node)
{
    switch (node->format) {
    case MPV_FORMAT_STRING:
        return QString::fromUtf8(node->u.string);
    case MPV_FORMAT_FLAG:
        return node->u.flag != 0;
    case MPV_FORMAT_INT64:
        return static_cast<qlonglong>(node->u.int64);
    case MPV_FORMAT_DOUBLE:
        return node->u.double_;
    case MPV_FORMAT_NODE_ARRAY: {
        QVariantList list;
        mpv_node_list *l = node->u.list;
        for (int i = 0; i < l->num; ++i) {
            list.append(nodeToVariant(&l->values[i]));
        }
        return list;
    }
    case MPV_FORMAT_NODE_MAP: {
        QVariantMap map;
        mpv_node_list *l = node->u.list;
        for (int i = 0; i < l->num; ++i) {
            map.insert(QString::fromUtf8(l->keys[i]), nodeToVariant(&l->values[i]));
        }
        return map;
    }
    default:
        return {};
    }
}
} // namespace

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

    // Observe the playback state we expose as bindable properties.
    mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(handle, 0, "volume", MPV_FORMAT_DOUBLE);
    mpv_observe_property(handle, 0, "mute", MPV_FORMAT_FLAG);
    mpv_observe_property(handle, 0, "track-list", MPV_FORMAT_NODE);
    mpv_observe_property(handle, 0, "speed", MPV_FORMAT_DOUBLE);
    mpv_observe_property(handle, 0, "chapter", MPV_FORMAT_INT64);
    mpv_observe_property(handle, 0, "chapter-list", MPV_FORMAT_NODE);
    mpv_observe_property(handle, 0, "sub-delay", MPV_FORMAT_DOUBLE);
    mpv_observe_property(handle, 0, "audio-delay", MPV_FORMAT_DOUBLE);
    mpv_observe_property(handle, 0, "demuxer-cache-state", MPV_FORMAT_NODE);

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

void MpvVideoItem::seek(double seconds)
{
    command({QStringLiteral("seek"), QString::number(seconds), QStringLiteral("absolute")});
}

void MpvVideoItem::setPaused(bool paused)
{
    if (m_mpv && m_mpv->handle) {
        int flag = paused ? 1 : 0;
        mpv_set_property(m_mpv->handle, "pause", MPV_FORMAT_FLAG, &flag);
    }
}

void MpvVideoItem::skip(double seconds)
{
    command({QStringLiteral("seek"), QString::number(seconds), QStringLiteral("relative")});
}

void MpvVideoItem::setVolume(double volume)
{
    if (m_mpv && m_mpv->handle) {
        double v = volume;
        mpv_set_property(m_mpv->handle, "volume", MPV_FORMAT_DOUBLE, &v);
    }
}

void MpvVideoItem::setMuted(bool muted)
{
    if (m_mpv && m_mpv->handle) {
        int flag = muted ? 1 : 0;
        mpv_set_property(m_mpv->handle, "mute", MPV_FORMAT_FLAG, &flag);
    }
}

void MpvVideoItem::setAudioTrack(int id)
{
    setOption(QStringLiteral("aid"), id < 0 ? QStringLiteral("no") : QString::number(id));
}

void MpvVideoItem::setSubtitleTrack(int id)
{
    setOption(QStringLiteral("sid"), id < 0 ? QStringLiteral("no") : QString::number(id));
}

void MpvVideoItem::setSpeed(double speed)
{
    if (m_mpv && m_mpv->handle) {
        double v = speed;
        mpv_set_property(m_mpv->handle, "speed", MPV_FORMAT_DOUBLE, &v);
    }
}

void MpvVideoItem::setChapter(int index)
{
    if (m_mpv && m_mpv->handle) {
        int64_t v = index;
        mpv_set_property(m_mpv->handle, "chapter", MPV_FORMAT_INT64, &v);
    }
}

void MpvVideoItem::setSubDelay(double seconds)
{
    if (m_mpv && m_mpv->handle) {
        double v = seconds;
        mpv_set_property(m_mpv->handle, "sub-delay", MPV_FORMAT_DOUBLE, &v);
    }
}

void MpvVideoItem::setAudioDelay(double seconds)
{
    if (m_mpv && m_mpv->handle) {
        double v = seconds;
        mpv_set_property(m_mpv->handle, "audio-delay", MPV_FORMAT_DOUBLE, &v);
    }
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
        case MPV_EVENT_PROPERTY_CHANGE:
            handlePropertyChange(static_cast<mpv_event_property *>(event->data));
            break;
        default:
            break;
        }
    }
}

void MpvVideoItem::scheduleUpdate()
{
    update();
}

void MpvVideoItem::handlePropertyChange(mpv_event_property *prop)
{
    if (!prop) {
        return;
    }
    const QByteArray name(prop->name);
    if (name == "time-pos" && prop->format == MPV_FORMAT_DOUBLE) {
        m_position = *static_cast<double *>(prop->data);
        Q_EMIT positionChanged();
    } else if (name == "duration" && prop->format == MPV_FORMAT_DOUBLE) {
        m_duration = *static_cast<double *>(prop->data);
        Q_EMIT durationChanged();
    } else if (name == "pause" && prop->format == MPV_FORMAT_FLAG) {
        m_paused = (*static_cast<int *>(prop->data) != 0);
        Q_EMIT pausedChanged();
    } else if (name == "volume" && prop->format == MPV_FORMAT_DOUBLE) {
        m_volume = *static_cast<double *>(prop->data);
        Q_EMIT volumeChanged();
    } else if (name == "mute" && prop->format == MPV_FORMAT_FLAG) {
        m_muted = (*static_cast<int *>(prop->data) != 0);
        Q_EMIT mutedChanged();
    } else if (name == "track-list" && prop->format == MPV_FORMAT_NODE) {
        updateTracks(nodeToVariant(static_cast<mpv_node *>(prop->data)).toList());
    } else if (name == "speed" && prop->format == MPV_FORMAT_DOUBLE) {
        m_speed = *static_cast<double *>(prop->data);
        Q_EMIT speedChanged();
    } else if (name == "chapter" && prop->format == MPV_FORMAT_INT64) {
        m_chapter = static_cast<int>(*static_cast<int64_t *>(prop->data));
        Q_EMIT chapterChanged();
    } else if (name == "chapter-list" && prop->format == MPV_FORMAT_NODE) {
        updateChapters(nodeToVariant(static_cast<mpv_node *>(prop->data)).toList());
    } else if (name == "sub-delay" && prop->format == MPV_FORMAT_DOUBLE) {
        m_subDelay = *static_cast<double *>(prop->data);
        Q_EMIT subDelayChanged();
    } else if (name == "audio-delay" && prop->format == MPV_FORMAT_DOUBLE) {
        m_audioDelay = *static_cast<double *>(prop->data);
        Q_EMIT audioDelayChanged();
    } else if (name == "demuxer-cache-state" && prop->format == MPV_FORMAT_NODE) {
        updateBufferedRanges(nodeToVariant(static_cast<mpv_node *>(prop->data)).toMap());
    }
}

void MpvVideoItem::updateChapters(const QVariantList &chapterList)
{
    m_chapters.clear();
    m_chapters.reserve(chapterList.size());
    for (const QVariant &cv : chapterList) {
        const QVariantMap c = cv.toMap();
        QVariantMap chapter;
        chapter[QStringLiteral("title")] = c.value(QStringLiteral("title")).toString();
        chapter[QStringLiteral("time")] = c.value(QStringLiteral("time")).toDouble();
        m_chapters.append(chapter);
    }
    Q_EMIT chaptersChanged();
}

void MpvVideoItem::updateBufferedRanges(const QVariantMap &cacheState)
{
    QVariantList ranges;
    const QVariantList seekable = cacheState.value(QStringLiteral("seekable-ranges")).toList();
    for (const QVariant &rv : seekable) {
        const QVariantMap r = rv.toMap();
        ranges.append(QVariantMap{
            {QStringLiteral("start"), r.value(QStringLiteral("start")).toDouble()},
            {QStringLiteral("end"), r.value(QStringLiteral("end")).toDouble()}});
    }
    // demuxer-cache-state ticks often; only notify QML when the ranges change
    if (ranges != m_bufferedRanges) {
        m_bufferedRanges = ranges;
        Q_EMIT bufferedRangesChanged();
    }
}

void MpvVideoItem::updateTracks(const QVariantList &trackList)
{
    m_audioTracks.clear();
    m_subtitleTracks.clear();
    for (const QVariant &tv : trackList) {
        const QVariantMap t = tv.toMap();
        const QString type = t.value(QStringLiteral("type")).toString();
        const bool isAudio = (type == QLatin1String("audio"));
        const bool isSub = (type == QLatin1String("sub"));
        if (!isAudio && !isSub) {
            continue;
        }
        const int id = t.value(QStringLiteral("id")).toInt();
        const QString title = t.value(QStringLiteral("title")).toString();
        const QString lang = t.value(QStringLiteral("lang")).toString();
        QString label;
        if (!title.isEmpty() && !lang.isEmpty()) {
            label = QStringLiteral("%1 (%2)").arg(title, lang);
        } else if (!title.isEmpty()) {
            label = title;
        } else if (!lang.isEmpty()) {
            label = lang;
        } else {
            label = QStringLiteral("Track %1").arg(id);
        }
        QVariantMap track;
        track[QStringLiteral("id")] = id;
        track[QStringLiteral("label")] = label;
        track[QStringLiteral("selected")] = t.value(QStringLiteral("selected")).toBool();
        // ffmpeg stream index — equals the Jellyfin MediaStream Index for the same
        // file, so the detail page can pre-select a track on direct play.
        track[QStringLiteral("ffIndex")] = t.value(QStringLiteral("ff-index"), -1).toInt();
        (isAudio ? m_audioTracks : m_subtitleTracks).append(track);
    }
    Q_EMIT tracksChanged();
}
