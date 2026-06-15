#pragma once

#include <QtQml/qqmlregistration.h>
#include <QtQuick/QQuickFramebufferObject>
#include <QStringList>

#include <memory>

#include <mpv/client.h>
#include <mpv/render_gl.h>

// ----------------------------------------------------------------------------
// Ownership helpers.
//
// The mpv handle and the GL render context have independent lifetimes: the
// render context is created and destroyed on the Qt scene-graph render thread
// (inside the Renderer), while the handle lives with the item on the GUI
// thread. The handle MUST outlive the render context, or teardown crashes.
// shared_ptr ownership makes that ordering correct no matter which side drops
// last (MpvRenderResources holds a ref to MpvHandle).
// ----------------------------------------------------------------------------

struct MpvHandle {
    mpv_handle *handle = nullptr;
    explicit MpvHandle(mpv_handle *h) : handle(h) {}
    ~MpvHandle()
    {
        if (handle) {
            mpv_terminate_destroy(handle);
        }
    }
    MpvHandle(const MpvHandle &) = delete;
    MpvHandle &operator=(const MpvHandle &) = delete;
};

struct MpvRenderResources {
    mpv_render_context *renderCtx = nullptr;
    std::shared_ptr<MpvHandle> mpv; // keeps the handle alive past the context

    explicit MpvRenderResources(std::shared_ptr<MpvHandle> h)
        : mpv(std::move(h))
    {
    }

    // MUST be called on the render thread with the GL context current.
    void freeContext()
    {
        if (renderCtx) {
            mpv_render_context_set_update_callback(renderCtx, nullptr, nullptr);
            mpv_render_context_free(renderCtx);
            renderCtx = nullptr;
        }
    }
};

// ----------------------------------------------------------------------------
// MpvVideoItem — a libmpv video surface for Qt Quick.
//
// mpv renders through its OpenGL render API directly into this item's FBO. The
// only external dependency is libmpv itself. Playback state (position,
// duration, pause) is observed from mpv and exposed as bindable properties —
// mpv is the authoritative source of state; the UI reflects it.
// ----------------------------------------------------------------------------

class MpvVideoItem : public QQuickFramebufferObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY pausedChanged)

public:
    explicit MpvVideoItem(QQuickItem *parent = nullptr);
    ~MpvVideoItem() override;

    Renderer *createRenderer() const override;

    double position() const { return m_position; }
    double duration() const { return m_duration; }
    bool paused() const { return m_paused; }

    // --- playback control ---
    Q_INVOKABLE void play(const QString &url);
    Q_INVOKABLE void seek(double seconds);     // absolute seek, in seconds
    Q_INVOKABLE void setPaused(bool paused);

    // --- low-level passthrough (typed API grows on top of these) ---
    Q_INVOKABLE void command(const QStringList &args);
    Q_INVOKABLE void setOption(const QString &name, const QString &value);
    Q_INVOKABLE QString queryProperty(const QString &name) const;

Q_SIGNALS:
    void fileLoaded();
    void endFile(const QString &reason);
    void positionChanged();
    void durationChanged();
    void pausedChanged();

private:
    static void onMpvWakeup(void *ctx); // called from an mpv-owned thread
    Q_INVOKABLE void pumpEvents();      // runs on the GUI thread
    Q_INVOKABLE void scheduleUpdate();  // runs on the GUI thread
    void handlePropertyChange(mpv_event_property *prop);

    double m_position = 0.0;
    double m_duration = 0.0;
    bool m_paused = false;

    std::shared_ptr<MpvHandle> m_mpv;
    std::shared_ptr<MpvRenderResources> m_resources;

    friend class MpvRenderer;
};
