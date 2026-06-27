#include "MpvVideoItem.h"

#include "Paths.h"

#include <QByteArray>
#include <QGuiApplication>
#include <QQuickWindow>
#include <QVariant>
#include <QVector>
#include <QWidget>
#include <QtGlobal>

#include <QtGui/qguiapplication_platform.h>
#include <qpa/qplatformnativeinterface.h>

#include <cstdint>

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
        for (int i = 0; i < l->num; ++i)
            list.append(nodeToVariant(&l->values[i]));
        return list;
    }
    case MPV_FORMAT_NODE_MAP: {
        QVariantMap map;
        mpv_node_list *l = node->u.list;
        for (int i = 0; i < l->num; ++i)
            map.insert(QString::fromUtf8(l->keys[i]), nodeToVariant(&l->values[i]));
        return map;
    }
    default:
        return {};
    }
}

void setIntOpt(mpv_handle *mpv, const char *name, int64_t v, bool initialized)
{
    if (initialized)
        mpv_set_property(mpv, name, MPV_FORMAT_INT64, &v);
    else
        mpv_set_option(mpv, name, MPV_FORMAT_INT64, &v);
}
} // namespace

// ----------------------------------------------------------------------------
// MpvVideoItem
// ----------------------------------------------------------------------------

MpvVideoItem::MpvVideoItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    // mpv renders into its own surface, so this QML item paints nothing — it
    // exists to expose the control API and drive the geometry of mpv's surface.
    setFlag(ItemHasContents, false);

    m_wayland = QGuiApplication::platformName() == QLatin1String("wayland");

    // X11 fallback: mpv renders into a native child window (created up front so
    // its id can be handed to mpv via `wid` before init). On Wayland we instead
    // hand mpv our window's wl_surface and it makes a subsurface (deferred until
    // the surface exists — see maybeInitWayland()).
    if (!m_wayland)
        ensureHostWindow();

    m_mpv = mpv_create();
    if (!m_mpv)
        qFatal("MpvVideoItem: mpv_create() failed");

    // Load user config (~/.config/jellyfin-desktop/mpv.conf), generating a
    // documented base on first run. libmpv doesn't load config by default.
    Paths::ensureDefaultMpvConfig();
    Paths::ensureDefaultInputConf();
    const QByteArray configDir = Paths::configDir().toUtf8();
    mpv_set_option_string(m_mpv, "config-dir", configDir.constData());
    mpv_set_option_string(m_mpv, "config", "yes");
    mpv_set_option_string(m_mpv, "terminal", "no");

    if (!m_wayland && m_host) {
        int64_t wid = static_cast<int64_t>(m_host->winId());
        mpv_set_option(m_mpv, "wid", MPV_FORMAT_INT64, &wid);
    }

    // Observe the playback state we expose as bindable properties.
    mpv_observe_property(m_mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "volume", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "mute", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "track-list", MPV_FORMAT_NODE);
    mpv_observe_property(m_mpv, 0, "speed", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "chapter", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, 0, "chapter-list", MPV_FORMAT_NODE);
    mpv_observe_property(m_mpv, 0, "sub-delay", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "audio-delay", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "demuxer-cache-state", MPV_FORMAT_NODE);

    mpv_request_log_messages(m_mpv, "warn");
    mpv_set_wakeup_callback(m_mpv, onMpvWakeup, this);

    // X11: we have the wid now, so init immediately. Wayland: defer until the
    // window's wl_surface exists.
    if (!m_wayland) {
        if (mpv_initialize(m_mpv) < 0) {
            mpv_terminate_destroy(m_mpv);
            m_mpv = nullptr;
            qFatal("MpvVideoItem: mpv_initialize() failed");
        }
        m_mpvInited = true;
    }
}

MpvVideoItem::~MpvVideoItem()
{
    if (m_mpv) {
        mpv_set_wakeup_callback(m_mpv, nullptr, nullptr);
        mpv_terminate_destroy(m_mpv);
        m_mpv = nullptr;
    }
    delete m_host;
    m_host = nullptr;
}

// ----------------------------------------------------------------------------
// Wayland subsurface embedding (primary path)
// ----------------------------------------------------------------------------

void MpvVideoItem::maybeInitWayland()
{
    if (!m_wayland || m_mpvInited || !m_mpv || !window())
        return;

    QPlatformNativeInterface *ni = QGuiApplication::platformNativeInterface();
    void *surface = ni ? ni->nativeResourceForWindow("surface", window()) : nullptr;
    auto *wlApp = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
    void *display = wlApp ? static_cast<void *>(wlApp->display()) : nullptr;
    if (!surface || !display)
        return; // window not exposed yet — retry on the next frame

    int64_t d = reinterpret_cast<int64_t>(display);
    int64_t s = reinterpret_cast<int64_t>(surface);
    mpv_set_option(m_mpv, "wl-display-ptr", MPV_FORMAT_INT64, &d);
    mpv_set_option(m_mpv, "wl-parent-surface", MPV_FORMAT_INT64, &s);

    const QPointF tl = mapToScene(QPointF(0, 0));
    const qreal dpr = window()->devicePixelRatio();
    int64_t x = qRound(tl.x());
    int64_t y = qRound(tl.y());
    int64_t w = qMax<int64_t>(16, qRound(width() * dpr));
    int64_t h = qMax<int64_t>(16, qRound(height() * dpr));
    mpv_set_option(m_mpv, "wl-subsurface-x", MPV_FORMAT_INT64, &x);
    mpv_set_option(m_mpv, "wl-subsurface-y", MPV_FORMAT_INT64, &y);
    mpv_set_option(m_mpv, "wl-subsurface-w", MPV_FORMAT_INT64, &w);
    mpv_set_option(m_mpv, "wl-subsurface-h", MPV_FORMAT_INT64, &h);

    if (mpv_initialize(m_mpv) < 0) {
        qWarning("MpvVideoItem: mpv_initialize() (wayland embed) failed");
        return;
    }
    m_mpvInited = true;
}

void MpvVideoItem::syncSubsurfaceGeometry()
{
    if (!m_wayland || !m_mpvInited || !m_mpv || !window() || !isVisible())
        return;
    const QPointF tl = mapToScene(QPointF(0, 0));
    const qreal dpr = window()->devicePixelRatio();
    int64_t w = qRound(width() * dpr);
    int64_t h = qRound(height() * dpr);
    if (w <= 0 || h <= 0)
        return;
    setIntOpt(m_mpv, "wl-subsurface-x", qRound(tl.x()), true);
    setIntOpt(m_mpv, "wl-subsurface-y", qRound(tl.y()), true);
    setIntOpt(m_mpv, "wl-subsurface-w", w, true);
    setIntOpt(m_mpv, "wl-subsurface-h", h, true);
}

// ----------------------------------------------------------------------------
// X11 child-window embedding (fallback)
// ----------------------------------------------------------------------------

void MpvVideoItem::ensureHostWindow()
{
    if (m_host)
        return;
    m_host = new QWidget(nullptr, Qt::FramelessWindowHint);
    m_host->setAttribute(Qt::WA_NativeWindow);
    m_host->setAttribute(Qt::WA_DontCreateNativeAncestors);
    m_host->setAttribute(Qt::WA_NoSystemBackground);
    m_host->setAttribute(Qt::WA_OpaquePaintEvent);
    m_host->setAttribute(Qt::WA_ShowWithoutActivating);
    m_host->setFocusPolicy(Qt::NoFocus);
    m_host->setStyleSheet(QStringLiteral("background:black;"));
    m_host->resize(16, 16);
    m_host->winId();
}

void MpvVideoItem::syncHostGeometry()
{
    if (!m_host || !window() || !isVisible())
        return;
    const QPointF topLeft = mapToGlobal(QPointF(0, 0));
    const QRect r(topLeft.toPoint(), QSize(qRound(width()), qRound(height())));
    if (r.isValid() && r != m_host->geometry())
        m_host->setGeometry(r);
}

void MpvVideoItem::updateHostVisibility()
{
    if (!m_host)
        return;
    const bool shouldShow = window() && isVisible() && width() > 0 && height() > 0;
    if (shouldShow) {
        syncHostGeometry();
        if (!m_host->isVisible()) {
            m_host->show();
            m_host->lower();
            if (m_window)
                m_window->raise();
        }
    } else if (m_host->isVisible()) {
        m_host->hide();
    }
}

void MpvVideoItem::attachToWindow(QQuickWindow *w)
{
    if (m_window == w)
        return;
    if (m_window)
        disconnect(m_window, nullptr, this, nullptr);
    m_window = w;
    if (!m_window)
        return;

    if (m_wayland) {
        // Retry deferred init each frame until the wl_surface exists (cheap
        // no-op after it's done), and track the item's geometry into the
        // subsurface. Subsurface position is parent-relative, so window *moves*
        // need no resync — only size/layout changes.
        connect(m_window, &QQuickWindow::frameSwapped, this, [this] { maybeInitWayland(); });
        connect(m_window, &QWindow::widthChanged, this, [this] { syncSubsurfaceGeometry(); });
        connect(m_window, &QWindow::heightChanged, this, [this] { syncSubsurfaceGeometry(); });
        maybeInitWayland();
    } else {
        auto resync = [this] { syncHostGeometry(); };
        connect(m_window, &QWindow::xChanged, this, resync);
        connect(m_window, &QWindow::yChanged, this, resync);
        connect(m_window, &QWindow::widthChanged, this, resync);
        connect(m_window, &QWindow::heightChanged, this, resync);
        connect(m_window, &QWindow::visibilityChanged, this, [this] { updateHostVisibility(); });
        updateHostVisibility();
    }
}

void MpvVideoItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (m_wayland) {
        maybeInitWayland();
        syncSubsurfaceGeometry();
    } else {
        syncHostGeometry();
        updateHostVisibility();
    }
}

void MpvVideoItem::itemChange(ItemChange change, const ItemChangeData &data)
{
    if (change == ItemSceneChange) {
        attachToWindow(data.window);
    } else if (change == ItemVisibleHasChanged) {
        if (m_wayland) {
            maybeInitWayland();
            syncSubsurfaceGeometry();
        } else {
            updateHostVisibility();
        }
    }
    QQuickItem::itemChange(change, data);
}

// ----------------------------------------------------------------------------
// Playback control
// ----------------------------------------------------------------------------

void MpvVideoItem::play(const QString &url)
{
    if (m_wayland && !m_mpvInited)
        maybeInitWayland(); // window is exposed by now; ensure mpv is up
    command({QStringLiteral("loadfile"), url});
}

void MpvVideoItem::seek(double seconds)
{
    command({QStringLiteral("seek"), QString::number(seconds), QStringLiteral("absolute")});
}

void MpvVideoItem::setPaused(bool paused)
{
    if (m_mpv) {
        int flag = paused ? 1 : 0;
        mpv_set_property(m_mpv, "pause", MPV_FORMAT_FLAG, &flag);
    }
}

void MpvVideoItem::skip(double seconds)
{
    command({QStringLiteral("seek"), QString::number(seconds), QStringLiteral("relative")});
}

void MpvVideoItem::setVolume(double volume)
{
    if (m_mpv) {
        double v = volume;
        mpv_set_property(m_mpv, "volume", MPV_FORMAT_DOUBLE, &v);
    }
}

void MpvVideoItem::setMuted(bool muted)
{
    if (m_mpv) {
        int flag = muted ? 1 : 0;
        mpv_set_property(m_mpv, "mute", MPV_FORMAT_FLAG, &flag);
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
    if (m_mpv) {
        double v = speed;
        mpv_set_property(m_mpv, "speed", MPV_FORMAT_DOUBLE, &v);
    }
}

void MpvVideoItem::setChapter(int index)
{
    if (m_mpv) {
        int64_t v = index;
        mpv_set_property(m_mpv, "chapter", MPV_FORMAT_INT64, &v);
    }
}

void MpvVideoItem::setSubDelay(double seconds)
{
    if (m_mpv) {
        double v = seconds;
        mpv_set_property(m_mpv, "sub-delay", MPV_FORMAT_DOUBLE, &v);
    }
}

void MpvVideoItem::setAudioDelay(double seconds)
{
    if (m_mpv) {
        double v = seconds;
        mpv_set_property(m_mpv, "audio-delay", MPV_FORMAT_DOUBLE, &v);
    }
}

void MpvVideoItem::sendKey(const QString &mpvKeyName)
{
    if (mpvKeyName.isEmpty())
        return;
    command({QStringLiteral("keypress"), mpvKeyName});
}

void MpvVideoItem::command(const QStringList &args)
{
    if (!m_mpv)
        return;

    QVector<QByteArray> bytes;
    bytes.reserve(args.size());
    for (const QString &arg : args)
        bytes.append(arg.toUtf8());

    QVector<const char *> argv;
    argv.reserve(bytes.size() + 1);
    for (const QByteArray &b : bytes)
        argv.append(b.constData());
    argv.append(nullptr);

    mpv_command(m_mpv, argv.data());
}

void MpvVideoItem::setOption(const QString &name, const QString &value)
{
    if (m_mpv)
        mpv_set_property_string(m_mpv, name.toUtf8().constData(), value.toUtf8().constData());
}

QString MpvVideoItem::queryProperty(const QString &name) const
{
    if (!m_mpv)
        return {};
    char *value = mpv_get_property_string(m_mpv, name.toUtf8().constData());
    if (!value)
        return {};
    const QString result = QString::fromUtf8(value);
    mpv_free(value);
    return result;
}

// ----------------------------------------------------------------------------
// mpv event loop (GUI thread)
// ----------------------------------------------------------------------------

void MpvVideoItem::onMpvWakeup(void *ctx)
{
    QMetaObject::invokeMethod(static_cast<MpvVideoItem *>(ctx), "pumpEvents", Qt::QueuedConnection);
}

void MpvVideoItem::pumpEvents()
{
    if (!m_mpv)
        return;
    while (true) {
        mpv_event *event = mpv_wait_event(m_mpv, 0);
        if (event->event_id == MPV_EVENT_NONE)
            break;
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
        case MPV_EVENT_LOG_MESSAGE: {
            auto *msg = static_cast<mpv_event_log_message *>(event->data);
            if (msg)
                Q_EMIT mpvLog(QString::fromUtf8(msg->level),
                              QString::fromUtf8(msg->prefix),
                              QString::fromUtf8(msg->text).trimmed());
            break;
        }
        default:
            break;
        }
    }
}

void MpvVideoItem::handlePropertyChange(mpv_event_property *prop)
{
    if (!prop)
        return;
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
        if (!isAudio && !isSub)
            continue;
        const int id = t.value(QStringLiteral("id")).toInt();
        const QString title = t.value(QStringLiteral("title")).toString();
        const QString lang = t.value(QStringLiteral("lang")).toString();
        QString label;
        if (!title.isEmpty() && !lang.isEmpty())
            label = QStringLiteral("%1 (%2)").arg(title, lang);
        else if (!title.isEmpty())
            label = title;
        else if (!lang.isEmpty())
            label = lang;
        else
            label = QStringLiteral("Track %1").arg(id);
        QVariantMap track;
        track[QStringLiteral("id")] = id;
        track[QStringLiteral("label")] = label;
        track[QStringLiteral("selected")] = t.value(QStringLiteral("selected")).toBool();
        track[QStringLiteral("ffIndex")] = t.value(QStringLiteral("ff-index"), -1).toInt();
        (isAudio ? m_audioTracks : m_subtitleTracks).append(track);
    }
    Q_EMIT tracksChanged();
}
