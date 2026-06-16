import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window
import JellyfinDesktop

// The playback layer: the mpv surface, the OSD controls, auto-hide, resume,
// periodic progress reporting, and a play queue (next/previous/repeat +
// auto-play-next on end-of-file). Driven by a JellyfinClient passed in.
Item {
    id: root
    required property var client
    property var config: null // AppConfig — default quality + subtitle prefs
    property alias playing: player.playing
    property bool osdVisible: true
    property var currentItem: ({})
    property bool favorite: false

    // play queue
    property var queue: []
    property int queueIndex: -1
    property int repeatMode: 0 // 0 none, 1 one, 2 all
    property int maxBitrate: 0 // 0 = Auto (direct play); >0 caps quality (transcode)
    property bool autoPlayNext: true
    property int skipBack: 10
    property int skipForward: 30
    property real _resumeSeconds: 0

    Component.onCompleted: if (config) {
        maxBitrate = config.value("playback/maxBitrate", 0)
        autoPlayNext = config.value("playback/autoPlayNext", true)
        skipBack = config.value("playback/skipBack", 10)
        skipForward = config.value("playback/skipForward", 30)
    }

    function playItem(item) { playQueue([item], 0) }

    function playQueue(items, index) {
        root.queue = items
        root.queueIndex = index
        _startCurrent()
    }

    function _startCurrent() {
        if (queueIndex < 0 || queueIndex >= queue.length)
            return
        const item = queue[queueIndex]
        if (player.currentId.length > 0 && player.currentId !== item.id)
            client.reportPlaybackStopped(player.currentId, Math.round(player.position * 10000000))
        player.currentId = item.id
        root.currentItem = item
        root.favorite = (item.isFavorite === true)
        root._resumeSeconds = item.playbackTicks ? (item.playbackTicks / 10000000) : 0
        player.playing = true
        showOsd()
        // resolve direct-play vs transcode first; onStreamReady actually loads it
        client.requestStream(item.id, root.maxBitrate, Math.round(root._resumeSeconds * 10000000), "stream:play")
        console.log("[jf] play", item.id, "(" + (queueIndex + 1) + "/" + queue.length + ") resume@", root._resumeSeconds)
    }

    // Re-resolve the current item (e.g. after a quality change) and resume where
    // we are now.
    function reloadAtPosition() {
        if (player.currentId.length === 0) return
        root._resumeSeconds = player.position
        client.requestStream(player.currentId, root.maxBitrate, Math.round(root._resumeSeconds * 10000000), "stream:play")
    }
    function setQuality(bitrate) {
        if (root.maxBitrate === bitrate) return
        root.maxBitrate = bitrate
        reloadAtPosition()
    }

    Connections {
        target: root.client
        function onStreamReady(tag, info) {
            if (tag !== "stream:play") return
            player.pendingResume = root._resumeSeconds
            player.play(info.url)
            client.reportPlaybackStart(player.currentId)
            console.log("[jf] stream", info.isTranscode ? "transcode" : "direct")
        }
    }

    function playNext() {
        if (repeatMode === 1) { player.seek(0); player.setPaused(false); return }
        if (queueIndex + 1 < queue.length) { root.queueIndex = queueIndex + 1; _startCurrent() }
        else if (repeatMode === 2 && queue.length > 0) { root.queueIndex = 0; _startCurrent() }
        else { stop() }
    }

    function playPrev() {
        if (player.position > 3) { player.seek(0); return }
        if (queueIndex - 1 >= 0) { root.queueIndex = queueIndex - 1; _startCurrent() }
        else { player.seek(0) }
    }

    function stop() {
        if (!player.playing)
            return
        if (player.currentId.length > 0)
            client.reportPlaybackStopped(player.currentId, Math.round(player.position * 10000000))
        player.playing = false
        player.currentId = ""
        root.queue = []
        root.queueIndex = -1
        player.command(["stop"])
    }

    function showOsd() {
        osdVisible = true
        osdTimer.restart()
    }

    // Apply the saved subtitle appearance to mpv. Styling mode maps to mpv's
    // sub-ass-override: Native = keep the file's own styling, Auto = keep it but
    // honour our size, Custom = force our look (best for plain SRT). The colour/
    // font/edge options affect plain-text subs always, and ASS only in Custom.
    function applySubtitleStyle() {
        if (!config) return
        const mode = "" + config.value("subtitles/styleMode", "auto")
        player.setOption("sub-ass-override", mode === "native" ? "no" : (mode === "custom" ? "force" : "scale"))
        player.setOption("sub-scale", "" + config.value("subtitles/scale", 1.0))
        player.setOption("sub-pos", "" + config.value("subtitles/pos", 100))
        const boldV = config.value("subtitles/bold", false)
        player.setOption("sub-bold", (boldV === true || boldV === "true") ? "yes" : "no")
        const font = "" + config.value("subtitles/font", "")
        player.setOption("sub-font", font.length ? font : "sans-serif")
        player.setOption("sub-color", "" + config.value("subtitles/color", "#FFFFFF"))
        player.setOption("sub-outline-color", "#000000")
        const edge = "" + config.value("subtitles/edge", "outline")
        player.setOption("sub-outline-size", edge === "outline" ? "3" : (edge === "both" ? "2.5" : "0"))
        player.setOption("sub-shadow-offset", edge === "shadow" ? "2.5" : (edge === "both" ? "2" : "0"))
    }

    MpvVideoItem {
        id: player
        anchors.fill: parent

        property bool playing: false
        property string currentId: ""
        property real pendingResume: 0

        onFileLoaded: {
            console.log("[mpv] file loaded — streaming OK")
            if (pendingResume > 0) {
                player.seek(pendingResume)
                pendingResume = 0
            }
            root.applySubtitleStyle()
        }
        onEndFile: (reason) => {
            // mpv reasons: 0 eof, 2 stop (our loadfile/stop), 4 error.
            console.log("[mpv] end-file, reason:", reason)
            if (reason === "0")
                (root.autoPlayNext || root.repeatMode !== 0) ? root.playNext() : root.stop()
            else if (reason !== "2")
                root.stop()              // error etc.; (transcode fallback lands later)
        }
        onTracksChanged: console.log("[mpv] tracks — audio:", audioTracks.length, "subtitle:", subtitleTracks.length)
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: root.showOsd()
        onClicked: {
            root.showOsd()
            player.setPaused(!player.paused)
        }
    }

    PlayerControls {
        anchors.fill: parent
        player: player
        title: root.currentItem.name || ""
        favorite: root.favorite
        repeatMode: root.repeatMode
        maxBitrate: root.maxBitrate
        skipBack: root.skipBack
        skipForward: root.skipForward
        opacity: root.osdVisible ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        onBack: root.stop()
        onPrevious: root.playPrev()
        onNext: root.playNext()
        onCycleRepeat: root.repeatMode = (root.repeatMode + 1) % 3
        onSetQuality: (br) => root.setQuality(br)
        onToggleFavorite: {
            root.favorite = !root.favorite
            root.client.setFavorite(player.currentId, root.favorite)
        }
        onToggleFullscreen: {
            const w = Window.window
            if (w)
                w.visibility = (w.visibility === Window.FullScreen) ? Window.Windowed : Window.FullScreen
        }
    }

    Timer {
        id: osdTimer
        interval: 3000
        onTriggered: root.osdVisible = false
    }

    // Report real playback position so continue-watching / resume work.
    Timer {
        interval: 10000
        repeat: true
        running: player.playing
        onTriggered: {
            if (player.currentId.length > 0)
                root.client.reportPlaybackProgress(player.currentId,
                                                   Math.round(player.position * 10000000),
                                                   player.paused)
        }
    }
}
