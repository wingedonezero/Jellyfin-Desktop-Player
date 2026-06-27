#pragma once

#include <QtQml/qqmlregistration.h>
#include <QQuickItem>
#include <QPointer>
#include <QRect>
#include <QStringList>
#include <QVariantList>

#include <mpv/client.h>

class QWidget;
class QQuickWindow;

// ----------------------------------------------------------------------------
// MpvVideoItem — a libmpv video surface for Qt Quick (Option A: mpv owns its
// own window).
//
// Unlike the old render-API approach (mpv drew into a QQuickFramebufferObject),
// mpv here renders with its real video output (vo=gpu-next, gpu-api=vulkan) into
// a dedicated native X11 window that we keep stacked directly BEHIND the (now
// transparent) Qt window, tracking this item's on-screen geometry. The QML UI —
// including the OSD — composites on top through the transparent region. This is
// what unlocks gpu-next/Vulkan, full mpv config, and mpv's native OSD/input.
//
// The control surface is unchanged: mpv is the authoritative source of state,
// observed and exposed as bindable properties; the same invokables drive it.
// audioTracks/subtitleTracks are lists of { id, label, selected, ffIndex } maps.
// ----------------------------------------------------------------------------

class MpvVideoItem : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY pausedChanged)
    Q_PROPERTY(double volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY mutedChanged)
    Q_PROPERTY(QVariantList audioTracks READ audioTracks NOTIFY tracksChanged)
    Q_PROPERTY(QVariantList subtitleTracks READ subtitleTracks NOTIFY tracksChanged)
    Q_PROPERTY(double speed READ speed NOTIFY speedChanged)
    Q_PROPERTY(QVariantList chapters READ chapters NOTIFY chaptersChanged)
    Q_PROPERTY(int chapter READ chapter NOTIFY chapterChanged)
    Q_PROPERTY(double subDelay READ subDelay NOTIFY subDelayChanged)
    Q_PROPERTY(double audioDelay READ audioDelay NOTIFY audioDelayChanged)
    Q_PROPERTY(QVariantList bufferedRanges READ bufferedRanges NOTIFY bufferedRangesChanged)

public:
    explicit MpvVideoItem(QQuickItem *parent = nullptr);
    ~MpvVideoItem() override;

    double position() const { return m_position; }
    double duration() const { return m_duration; }
    bool paused() const { return m_paused; }
    double volume() const { return m_volume; }
    bool muted() const { return m_muted; }
    QVariantList audioTracks() const { return m_audioTracks; }
    QVariantList subtitleTracks() const { return m_subtitleTracks; }
    double speed() const { return m_speed; }
    QVariantList chapters() const { return m_chapters; }
    int chapter() const { return m_chapter; }
    double subDelay() const { return m_subDelay; }
    double audioDelay() const { return m_audioDelay; }
    QVariantList bufferedRanges() const { return m_bufferedRanges; }

    // --- playback control ---
    Q_INVOKABLE void play(const QString &url);
    Q_INVOKABLE void seek(double seconds);    // absolute seek, in seconds
    Q_INVOKABLE void skip(double seconds);    // relative seek, in seconds
    Q_INVOKABLE void setPaused(bool paused);
    Q_INVOKABLE void setVolume(double volume);
    Q_INVOKABLE void setMuted(bool muted);
    Q_INVOKABLE void setAudioTrack(int id);
    Q_INVOKABLE void setSubtitleTrack(int id); // id < 0 => off
    Q_INVOKABLE void setSpeed(double speed);
    Q_INVOKABLE void setChapter(int index);
    Q_INVOKABLE void setSubDelay(double seconds);   // + => subtitles later
    Q_INVOKABLE void setAudioDelay(double seconds); // + => audio later

    // --- input forwarding (so mpv's own input.conf + OSD work) ---
    // Translate a Qt key/text to an mpv key name and feed it to mpv's input
    // layer, which runs the binding and shows mpv's native OSD feedback.
    Q_INVOKABLE void sendKey(const QString &mpvKeyName);

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
    void volumeChanged();
    void mutedChanged();
    void tracksChanged();
    void speedChanged();
    void chaptersChanged();
    void chapterChanged();
    void subDelayChanged();
    void audioDelayChanged();
    void bufferedRangesChanged();
    // mpv log line (level: "error"/"warn"/...). Drives the playback-health UI.
    void mpvLog(const QString &level, const QString &prefix, const QString &text);

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void itemChange(ItemChange change, const ItemChangeData &data) override;

private:
    static void onMpvWakeup(void *ctx); // called from an mpv-owned thread
    Q_INVOKABLE void pumpEvents();      // runs on the GUI thread
    void handlePropertyChange(mpv_event_property *prop);
    void updateTracks(const QVariantList &trackList);
    void updateChapters(const QVariantList &chapterList);
    void updateBufferedRanges(const QVariantMap &cacheState);

    // The native window mpv renders into, kept behind the transparent Qt window
    // and matched to this item's on-screen geometry.
    void ensureHostWindow();
    void syncHostGeometry();
    void updateHostVisibility();
    void attachToWindow(QQuickWindow *w);

    double m_position = 0.0;
    double m_duration = 0.0;
    bool m_paused = false;
    double m_volume = 100.0;
    bool m_muted = false;
    QVariantList m_audioTracks;
    QVariantList m_subtitleTracks;
    double m_speed = 1.0;
    QVariantList m_chapters;
    int m_chapter = -1;
    double m_subDelay = 0.0;
    double m_audioDelay = 0.0;
    QVariantList m_bufferedRanges; // [{start,end}] seconds, from demuxer-cache-state

    mpv_handle *m_mpv = nullptr;
    QWidget *m_host = nullptr;          // mpv's render window (wid target)
    QPointer<QQuickWindow> m_window;    // the Qt window this item lives in
    bool m_hostStacked = false;        // restack-below-once latch on (re)show
};
