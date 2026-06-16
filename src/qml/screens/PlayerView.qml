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
    property var playerItem: ({})  // full item (trickplay/chapters), fetched on play
    property bool favorite: false

    // media segments (intro/outro/...) + the per-type skip action map
    property var segments: []
    property var segActions: ({})
    property var currentSkipSegment: null  // the AskToSkip segment to prompt for, or null

    // play queue
    property var queue: []
    property int queueIndex: -1
    property int repeatMode: 0 // 0 none, 1 one, 2 all
    property int maxBitrate: 0 // 0 = Auto (direct play); >0 caps quality (transcode)
    property bool autoPlayNext: true
    property int skipBack: 10
    property int skipForward: 30
    property bool showRemaining: false // duration label shows -remaining instead of total
    property real _resumeSeconds: 0

    Component.onCompleted: if (config) {
        maxBitrate = config.value("playback/maxBitrate", 0)
        autoPlayNext = config.value("playback/autoPlayNext", true)
        skipBack = config.value("playback/skipBack", 10)
        skipForward = config.value("playback/skipForward", 30)
        var rt = config.value("playback/remainingTime", false)
        showRemaining = (rt === true || rt === "true" || rt === 1 || rt === "1")
    }

    function playItem(item) { playQueue([item], 0) }

    // Compose the OSD title the way jellyfin-web does (itemHelper.getDisplayName
    // + setTitle): episodes as "Series - Sxx:Exx - Episode", movies with a year.
    function composeTitle(it) {
        if (!it || !it.name) return ""
        if (it.type === "Episode") {
            var num = ""
            // specials (season 0) get no Sxx:Exx prefix, matching web
            if (it.parentIndexNumber !== undefined && it.parentIndexNumber !== 0
                    && it.indexNumber !== undefined)
                num = "S" + it.parentIndexNumber + ":E" + it.indexNumber
            var base = num ? (it.name ? num + " - " + it.name : num) : it.name
            return it.seriesName ? (it.seriesName + " - " + base) : base
        }
        if (it.type === "Movie" && it.productionYear)
            return it.name + " (" + it.productionYear + ")"
        return it.name
    }

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
        root.playerItem = item   // queue item may lack trickplay; enriched by the fetch below
        root.favorite = (item.isFavorite === true)
        root._resumeSeconds = item.playbackTicks ? (item.playbackTicks / 10000000) : 0
        player.playing = true
        showOsd()
        // resolve direct-play vs transcode first; onStreamReady actually loads it
        client.requestStream(item.id, root.maxBitrate, Math.round(root._resumeSeconds * 10000000), "stream:play")
        // fetch the full item so the OSD has trickplay sheets (the resume/episode
        // list items don't carry them); merged in onItemsReady below
        client.fetchItem(item.id, "player:item")
        // media segments: load the per-type actions, reset, fetch enabled types
        root.segActions = root._loadSegActions()
        root.segments = []
        root.currentSkipSegment = null
        var segTypes = root._enabledSegTypes()
        if (segTypes.length > 0) client.fetchMediaSegments(item.id, segTypes.join(","))
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
        function onItemsReady(tag, items) {
            if (tag === "player:item" && items.length > 0 && items[0].id === player.currentId)
                root.playerItem = items[0]
        }
        function onMediaSegmentsReady(itemId, segs) {
            if (itemId === player.currentId) root.segments = segs
        }
    }

    // Pick the trickplay resolution the way jellyfin-web does: the highest width
    // that is still <= 20% of the screen width. Returns the info object
    // {Width,Height,TileWidth,TileHeight,Interval,...} or null when unavailable.
    function selectTrickplay(it) {
        if (!it || !it.trickplay) return null
        var byMs = it.trickplay[it.id]
        if (!byMs) { for (var k in it.trickplay) { byMs = it.trickplay[k]; break } }
        if (!byMs) return null
        var maxW = Screen.width * Screen.devicePixelRatio * 0.2
        var best = null
        for (var w in byMs) {
            var info = byMs[w]
            if (!best
                    || (info.Width < best.Width && best.Width > maxW)
                    || (info.Width > best.Width && info.Width <= maxW))
                best = info
        }
        return best
    }

    // ---- media-segment skip (intro/outro/recap/preview/commercial) --------
    // The per-type action (None/AskToSkip/Skip) is a client-local pref. Defaults
    // mirror jellyfin-web: Intro + Outro = AskToSkip, the rest None.
    function _loadSegActions() {
        if (!config) return ({})
        function a(key, def) { return "" + config.value(key, def) }
        return {
            "Intro":      a("playback/segIntro", "AskToSkip"),
            "Recap":      a("playback/segRecap", "None"),
            "Preview":    a("playback/segPreview", "None"),
            "Outro":      a("playback/segOutro", "AskToSkip"),
            "Commercial": a("playback/segCommercial", "None")
        }
    }
    function _enabledSegTypes() {
        var types = []
        for (var t in root.segActions)
            if (root.segActions[t] && root.segActions[t] !== "None") types.push(t)
        return types
    }
    // Called on a short timer during playback: find the segment we're inside and
    // apply its action (auto-skip, or arm the "Skip …" prompt). Mirrors web's
    // MediaSegmentManager.onPlayerTimeUpdate.
    function _checkSegments() {
        if (!player.playing || root.segments.length === 0) return
        var time = player.position * 10000000 // ticks
        var seg = null
        for (var i = 0; i < root.segments.length; ++i) {
            var s = root.segments[i]
            if (s.startTicks <= time && (s.endTicks <= 0 || time < s.endTicks)) { seg = s; break }
        }
        if (!seg) { if (root.currentSkipSegment) root.currentSkipSegment = null; return }
        var act = root.segActions[seg.type] || "None"
        if (act === "Skip") {
            if (root.currentSkipSegment) root.currentSkipSegment = null
            // skip once: seek to the end if it's a real (>1s) segment ahead of us
            if (seg.endTicks > seg.startTicks && (seg.endTicks - seg.startTicks) >= 10000000
                    && time < seg.endTicks - 5000000)
                player.seek(seg.endTicks / 10000000)
        } else if (act === "AskToSkip") {
            if (root.currentSkipSegment !== seg) root.currentSkipSegment = seg // identity-stable
        } else if (root.currentSkipSegment) {
            root.currentSkipSegment = null
        }
    }
    function skipCurrentSegment() {
        var seg = root.currentSkipSegment
        if (!seg) return
        root.currentSkipSegment = null
        if (seg.endTicks > 0) player.seek(seg.endTicks / 10000000)
        else playNext()
    }
    function skipLabel(type) {
        var names = { "Intro": qsTr("Intro"), "Outro": qsTr("Outro"), "Recap": qsTr("Recap"),
                      "Preview": qsTr("Preview"), "Commercial": qsTr("Commercial") }
        return qsTr("Skip %1").arg(names[type] || type)
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
        root.segments = []
        root.currentSkipSegment = null
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

    // Keep the screen + both monitors awake while a file is actively playing
    // (released on pause/stop, matching mpv). Embedded libmpv can't inhibit the
    // compositor itself under the render API, so the host holds the D-Bus
    // screensaver/power inhibitions instead.
    ScreenSaverInhibitor {
        inhibited: player.playing && !player.paused
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
        id: controls
        anchors.fill: parent
        player: player
        client: root.client
        title: root.composeTitle(root.currentItem)
        favorite: root.favorite
        repeatMode: root.repeatMode
        maxBitrate: root.maxBitrate
        skipBack: root.skipBack
        skipForward: root.skipForward
        showRemaining: root.showRemaining
        trickInfo: root.selectTrickplay(root.playerItem)
        trickItemId: root.playerItem.id || ""
        opacity: root.osdVisible ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        onBack: root.stop()
        onToggleRemaining: {
            root.showRemaining = !root.showRemaining
            if (root.config) root.config.setValue("playback/remainingTime", root.showRemaining)
        }
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

    // Transient "Skip Intro / Outro / …" button during an AskToSkip segment.
    // Shown independent of the OSD auto-hide, matching jellyfin-web's skip button.
    Button {
        id: skipBtn
        visible: root.currentSkipSegment !== null
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 48; bottomMargin: 96 }
        z: 60
        hoverEnabled: true
        padding: 12
        onClicked: root.skipCurrentSegment()
        background: Rectangle {
            radius: Theme.radius
            color: skipBtn.hovered ? Theme.surfaceHover : Theme.surface
            border.color: Theme.accent
            border.width: 1
            opacity: 0.97
        }
        contentItem: Text {
            text: (root.currentSkipSegment ? root.skipLabel(root.currentSkipSegment.type) : "") + "   ⏭"
            color: Theme.textPrimary
            font.pixelSize: Theme.fontMedium
            font.bold: true
        }
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Poll the position while there are segments, to arm/auto-apply skips.
    Timer {
        interval: 400
        repeat: true
        running: player.playing && root.segments.length > 0
        onTriggered: root._checkSegments()
    }

    Timer {
        id: osdTimer
        interval: 3000
        // keep the OSD up while the user is hovering the scrubber (trickplay preview)
        onTriggered: controls.scrubberHovered ? osdTimer.restart() : (root.osdVisible = false)
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
