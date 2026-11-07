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
    // True once mpv has the first frame up. Until then the app backdrop stays
    // opaque so the transparent window doesn't briefly reveal the desktop
    // through the not-yet-painted video subsurface.
    property bool videoReady: false
    property var currentItem: ({})
    property var playerItem: ({})  // full item (trickplay/chapters), fetched on play
    property bool favorite: false

    // media segments (intro/outro/...) + the per-type skip action map
    property var segments: []
    property var segActions: ({})
    property var currentSkipSegment: null  // the AskToSkip segment to prompt for, or null

    // up-next overlay card (episodes, near the end, when there's a next item)
    property bool upNextVisible: false
    property bool upNextDismissed: false

    // play queue
    property var queue: []
    property int queueIndex: -1
    property int repeatMode: 0 // 0 none, 1 one, 2 all
    // Repeat One the mpv way: the file loops at EOF instead of relying on an
    // end-file → seek(0) round-trip (the file is already unloaded by then).
    onRepeatModeChanged: player.setOption("loop-file", repeatMode === 1 ? "inf" : "no")

    // playback-health toast (shown at window level by Main.qml — it must
    // outlive the player when a failed stream closes it)
    signal toast(string message)
    Timer { id: logDedup; interval: 10000 }
    property int maxBitrate: 0 // 0 = Auto (direct play); >0 caps quality (transcode)
    property bool autoPlayNext: true
    property int skipBack: 10
    property int skipForward: 30
    property bool showRemaining: false // duration label shows -remaining instead of total
    property real _resumeSeconds: 0
    // A transcode's HLS stream starts AT the resume offset, so mpv's time-pos
    // is relative to it. Everything reported to the server must add this back
    // (web's playbackmanager does the same with startPositionTicks), or a
    // resumed transcode would clobber the saved position with tiny values.
    property real _transcodeOffset: 0
    function absPosition() { return root._transcodeOffset + player.position }
    // Position to REPORT to the server. Before the first frame is up, mpv's
    // time-pos is 0 (and reset to 0 on unload) — reporting that would wipe the
    // item's saved resume point (stop at "0" = drop from Continue Watching).
    // Until the video is actually playing, the best-known position is where we
    // asked to resume from.
    function reportSeconds() { return root.videoReady ? root.absPosition() : root._resumeSeconds }
    property var streamInfo: ({}) // last streamReady payload → OSD Playback Info panel
    // detail-page selections carried into playback (-999 = unset, -1 = subtitles off)
    property int _pendingAudioIndex: -999
    property int _pendingSubIndex: -999
    property string _pendingSourceId: ""
    property bool _tracksApplied: false
    // Remember-selections (web's autoSetNextTracks): the Jellyfin stream indices
    // currently selected in mpv (kept live from track-list), plus a snapshot of
    // the previous queue item's streams + selection taken at item change. The
    // next item scores its streams against the snapshot and keeps the match.
    property int _lastAudioJf: -1
    property int _lastSubJf: -1     // -1 = subtitles off
    property var _prevStreams: []
    property int _prevAudioJf: -1
    property int _prevSubJf: -999   // -999 = no previous item (don't carry "off")

    // Keyboard: the player grabs focus while visible and forwards key presses
    // to mpv, so mpv's own bindings + OSD feedback drive playback (d deinterlace,
    // i stats, SPACE pause, arrows seek, t tone-mapping via input.conf, …).
    // f/F11/Esc are app-level (fullscreen / exit).
    focus: true
    onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)

    // Fullscreen is owned here: remember what the window was (maximized vs
    // normal) so leaving fullscreen restores it instead of always "Windowed",
    // and leave it automatically when playback stops (web exits fullscreen on
    // stop too) — otherwise a video ending in fullscreen strands the browse UI.
    property int _preFullscreenVisibility: Window.Windowed
    function isFullscreen() { const w = Window.window; return !!w && w.visibility === Window.FullScreen }
    function setFullscreen(on) {
        const w = Window.window
        if (!w) return
        if (on && w.visibility !== Window.FullScreen) {
            root._preFullscreenVisibility = (w.visibility === Window.Maximized) ? Window.Maximized : Window.Windowed
            w.visibility = Window.FullScreen
        } else if (!on && w.visibility === Window.FullScreen) {
            w.visibility = root._preFullscreenVisibility
        }
    }
    function toggleFullscreen() { setFullscreen(!isFullscreen()) }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            if (root.isFullscreen()) root.setFullscreen(false)
            else root.stop()
            event.accepted = true; return
        }
        if ((event.key === Qt.Key_F || event.key === Qt.Key_F11)
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
            root.toggleFullscreen()
            root.showOsd(); event.accepted = true; return
        }
        // Keys whose *default mpv binding* would kill the embedded core or jump
        // an mpv playlist we don't use — remap to their app equivalents instead
        // of forwarding. (q/Q = quit → back out; </> = playlist prev/next →
        // our queue; Enter = playlist-next → swallow, too easy to hit.)
        if (event.key === Qt.Key_Q) { root.stop(); event.accepted = true; return }
        if (event.text === "<") { root.playPrev(); event.accepted = true; return }
        if (event.text === ">") { root.playNext(); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { event.accepted = true; return }
        const name = root._mpvKeyName(event)
        if (name.length > 0) { player.sendKey(name); event.accepted = true }
    }

    // Translate a Qt key event to an mpv key name (for player.sendKey()).
    function _mpvKeyName(event) {
        var mods = ""
        if (event.modifiers & Qt.ControlModifier) mods += "Ctrl+"
        if (event.modifiers & Qt.AltModifier) mods += "Alt+"
        if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12)
            return mods + "F" + (event.key - Qt.Key_F1 + 1)
        var sp = ({})
        sp[Qt.Key_Space] = "SPACE"; sp[Qt.Key_Left] = "LEFT"; sp[Qt.Key_Right] = "RIGHT"
        sp[Qt.Key_Up] = "UP"; sp[Qt.Key_Down] = "DOWN"; sp[Qt.Key_PageUp] = "PGUP"
        sp[Qt.Key_PageDown] = "PGDWN"; sp[Qt.Key_Home] = "HOME"; sp[Qt.Key_End] = "END"
        sp[Qt.Key_Return] = "ENTER"; sp[Qt.Key_Enter] = "ENTER"; sp[Qt.Key_Backspace] = "BS"
        if (sp[event.key] !== undefined) {
            if (event.modifiers & Qt.ShiftModifier) mods += "Shift+"
            return mods + sp[event.key]
        }
        if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 0x20) {
            // mpv spells a shifted letter as the uppercase char (Ctrl+D = Ctrl+Shift+d)
            if (mods.length > 0 && event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                const ch = String.fromCharCode(event.key)
                return mods + ((event.modifiers & Qt.ShiftModifier) ? ch : ch.toLowerCase())
            }
            return mods + event.text
        }
        return ""
    }

    // Playback prefs are re-read for every item (and live when Settings changes
    // them), not once at startup — this view lives for the whole session.
    // The quality cap is only picked up per item: changing it mid-play would
    // make the OSD quality menu disagree with the stream that's actually open.
    function reloadPrefs(includeQuality) {
        if (!config) return
        if (includeQuality) {
            // web parity: the in-network vs internet max-quality cap is picked by
            // the server's /System/Endpoint answer for this connection
            maxBitrate = Number(config.value((client && !client.inNetwork)
                                             ? "playback/maxBitrateInternet"
                                             : "playback/maxBitrate", 0)) || 0
        }
        var apn = config.value("playback/autoPlayNext", true)
        autoPlayNext = (apn === true || apn === "true" || apn === 1 || apn === "1")
        skipBack = Number(config.value("playback/skipBack", 10)) || 10
        skipForward = Number(config.value("playback/skipForward", 30)) || 30
        var rt = config.value("playback/remainingTime", false)
        showRemaining = (rt === true || rt === "true" || rt === 1 || rt === "1")
    }
    Component.onCompleted: reloadPrefs(true)
    Connections {
        target: root.config
        function onValueChanged(key) { if (key.indexOf("playback/") === 0) root.reloadPrefs(false) }
    }

    function playItem(item) {
        playQueue([item], 0)
        // Web parity: playing a single episode queues the rest of the series from
        // here (startItemId), so auto-play-next / up-next / prev-next work from
        // Next Up, Continue Watching, search and cards — not just a season's Play.
        if (item && item.type === "Episode" && item.seriesId)
            client.fetchEpisodes(item.seriesId, "", "player:autoqueue", item.id)
    }

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

    // card menu "Add to queue" / "Play next" — append/insert into the live queue;
    // if nothing is playing yet, just start the item.
    function enqueue(item) {
        if (!player.playing) { playItem(item); return }
        root.queue = root.queue.concat([item])
    }
    function playNextInsert(item) {
        if (!player.playing) { playItem(item); return }
        var q = root.queue.slice()
        q.splice(root.queueIndex + 1, 0, item)
        root.queue = q
    }

    function _startCurrent() {
        if (queueIndex < 0 || queueIndex >= queue.length)
            return
        const item = queue[queueIndex]
        // snapshot the outgoing item's streams + live track selection before
        // they're overwritten (the "prevSource" of web's autoSetNextTracks)
        if (player.currentId.length > 0) {
            root._prevStreams = root.streamInfo.mediaStreams || []
            root._prevAudioJf = root._lastAudioJf
            root._prevSubJf = root._lastSubJf
        } else {
            root._prevStreams = []
            root._prevAudioJf = -1
            root._prevSubJf = -999
        }
        if (player.currentId.length > 0 && player.currentId !== item.id)
            client.reportPlaybackStopped(player.currentId, Math.round(root.reportSeconds() * 10000000))
        root.reloadPrefs(true) // the item picks up the current default quality + prefs
        player.currentId = item.id
        root.currentItem = item
        root.playerItem = item   // queue item may lack trickplay; enriched by the fetch below
        root.favorite = (item.isFavorite === true)
        root._resumeSeconds = item.playbackTicks ? (item.playbackTicks / 10000000) : 0
        player.playing = true
        root.videoReady = false
        // per-item state (mpv keeps these across files; web resets them per playback)
        player.setSubDelay(0)
        player.setAudioDelay(0)
        showOsd()
        // detail-page version / default-track selections (carried on the item)
        root._pendingSourceId = item.mediaSourceId || ""
        root._pendingAudioIndex = (item.audioStreamIndex === undefined || item.audioStreamIndex === null) ? -999 : item.audioStreamIndex
        root._pendingSubIndex = (item.subtitleStreamIndex === undefined || item.subtitleStreamIndex === null) ? -999 : item.subtitleStreamIndex
        root._tracksApplied = false
        // resolve direct-play vs transcode first; onStreamReady actually loads it
        client.requestStream(item.id, root.maxBitrate, Math.round(root._resumeSeconds * 10000000), "stream:play",
                             root._pendingAudioIndex >= 0 ? root._pendingAudioIndex : -1,
                             root._pendingSubIndex >= 0 ? root._pendingSubIndex : -1,
                             root._pendingSourceId)
        // fetch the full item so the OSD has trickplay sheets (the resume/episode
        // list items don't carry them); merged in onItemsReady below
        client.fetchItem(item.id, "player:item")
        // up-next card resets per item
        root.upNextVisible = false
        root.upNextDismissed = false
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
        root._resumeSeconds = root.absPosition()
        root._tracksApplied = false
        client.requestStream(player.currentId, root.maxBitrate, Math.round(root._resumeSeconds * 10000000), "stream:play",
                             root._pendingAudioIndex >= 0 ? root._pendingAudioIndex : -1,
                             root._pendingSubIndex >= 0 ? root._pendingSubIndex : -1,
                             root._pendingSourceId)
    }
    // Apply detail-page audio/subtitle selection to the loaded file (direct play):
    // match the chosen Jellyfin stream index to the mpv track via its ffmpeg index.
    // On a transcode the indices won't match (server already baked them) → no-op.
    function _applyPendingTracks() {
        if (root._tracksApplied) return
        if (root._pendingAudioIndex >= 0) {
            var a = player.audioTracks
            for (var i = 0; i < a.length; ++i)
                if (a[i].ffIndex === root._pendingAudioIndex) { player.setAudioTrack(a[i].id); break }
        }
        if (root._pendingSubIndex >= 0) {
            var s = player.subtitleTracks
            for (var j = 0; j < s.length; ++j)
                if (s[j].ffIndex === root._pendingSubIndex) { player.setSubtitleTrack(s[j].id); break }
        } else if (root._pendingSubIndex === -1) {
            player.setSubtitleTrack(-1) // explicit "off"
        }
        root._tracksApplied = true
    }
    // Port of web playbackmanager's rankStreamType: score each stream of `type`
    // in the new source against the previously selected one — +1 same codec,
    // +1 same relative position, +2 same display title, +2 same language — and
    // return the best candidate's Jellyfin index if it scores >= 3, else null.
    function _rankTrackMatch(prevStreams, prevIndex, newStreams, type) {
        if (prevIndex < 0 || !prevStreams || prevStreams.length === 0 || !newStreams) return null
        var prev = null
        for (var i = 0; i < prevStreams.length; ++i)
            if (prevStreams[i].index === prevIndex) { prev = prevStreams[i]; break }
        if (!prev) return null
        var prevRel = 0
        for (i = 0; i < prevStreams.length; ++i) {
            if (prevStreams[i].type !== type) continue
            if (prevStreams[i].index === prevIndex) break
            prevRel++
        }
        var best = null, bestScore = 0, rel = 0
        for (i = 0; i < newStreams.length; ++i) {
            var s = newStreams[i]
            if (s.type !== type) continue
            var score = 0
            if (prev.codec && prev.codec === s.codec) score += 1
            if (prevRel === rel) score += 1
            if (prev.title && prev.title === s.title) score += 2
            if (prev.language && prev.language !== "und" && prev.language === s.language) score += 2
            if (score > bestScore && score >= 3) { bestScore = score; best = s.index }
            rel++
        }
        return best
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
            // Late reply for an item we've since left (backed out, or picked
            // another title before PlaybackInfo returned) — ignore it, or it
            // would start that stream behind the browse UI.
            if (!player.playing || info.itemId !== player.currentId) {
                console.log("[jf] stale stream reply ignored for", info.itemId)
                return
            }
            // When the user didn't pick a track on the detail page (-999), the
            // default is: the previous episode's live selection carried over
            // (web's Remember audio/subtitle selections, when enabled and a
            // stream match scores high enough), else the server's preference-
            // computed default (audio language + subtitle mode/language).
            // -1 => none/off. A manual pick (>=0) still wins. Transcodes skip
            // the carry-over: tracks are baked server-side from its defaults.
            var uc = (root.client && root.client.userConfig) ? root.client.userConfig : ({})
            if (root._pendingAudioIndex === -999) {
                var carriedA = (!info.isTranscode && uc.RememberAudioSelections !== false)
                    ? root._rankTrackMatch(root._prevStreams, root._prevAudioJf, info.mediaStreams, "Audio") : null
                root._pendingAudioIndex = (carriedA !== null) ? carriedA
                    : ((info.defaultAudioIndex !== undefined) ? info.defaultAudioIndex : -1)
                if (carriedA !== null) console.log("[jf] remember-selections: audio ->", carriedA)
            }
            if (root._pendingSubIndex === -999) {
                var carriedS = null
                if (!info.isTranscode && uc.RememberSubtitleSelections !== false && root._prevSubJf !== -999)
                    carriedS = (root._prevSubJf === -1) ? -1 // "off" is remembered too, like web
                        : root._rankTrackMatch(root._prevStreams, root._prevSubJf, info.mediaStreams, "Subtitle")
                root._pendingSubIndex = (carriedS !== null) ? carriedS
                    : ((info.defaultSubIndex !== undefined) ? info.defaultSubIndex : -1)
                if (carriedS !== null) console.log("[jf] remember-selections: subtitle ->", carriedS)
            }
            // the new item starts out on whatever we're about to select
            root._lastAudioJf = root._pendingAudioIndex >= 0 ? root._pendingAudioIndex : -1
            root._lastSubJf = root._pendingSubIndex >= 0 ? root._pendingSubIndex : -1
            root._tracksApplied = false
            root.streamInfo = info
            // Direct play: mpv opens the full file, start= seeks to the resume
            // point. Transcode: the server's HLS already begins at the resume
            // offset (StartTimeTicks was in the request) — starting again would
            // double-seek, so open at 0 and remember the offset for reporting.
            root._transcodeOffset = info.isTranscode ? root._resumeSeconds : 0
            player.play(info.url, info.isTranscode ? 0 : root._resumeSeconds)
            client.reportPlaybackStart(player.currentId)
            console.log("[jf] stream", info.isTranscode ? "transcode" : "direct",
                        "tracks a/s:", root._pendingAudioIndex, "/", root._pendingSubIndex)
        }
        function onItemsReady(tag, items) {
            if (tag === "player:item" && items.length > 0 && items[0].id === player.currentId)
                root.playerItem = items[0]
            else if (tag === "player:autoqueue" && items.length > 1 && root.queue.length === 1) {
                // adopt the series queue only if we're still on the single item we launched
                var idx = -1
                for (var i = 0; i < items.length; ++i)
                    if (items[i].id === player.currentId) { idx = i; break }
                if (idx >= 0) { root.queue = items; root.queueIndex = idx }
            }
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
        var time = root.absPosition() * 10000000 // ticks (segments are absolute)
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
                player.seek(seg.endTicks / 10000000 - root._transcodeOffset)
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
        if (seg.endTicks > 0) player.seek(seg.endTicks / 10000000 - root._transcodeOffset)
        else playNext()
    }
    function skipLabel(type) {
        var names = { "Intro": qsTr("Intro"), "Outro": qsTr("Outro"), "Recap": qsTr("Recap"),
                      "Preview": qsTr("Preview"), "Commercial": qsTr("Commercial") }
        return qsTr("Skip %1").arg(names[type] || type)
    }

    // ---- up-next overlay card ---------------------------------------------
    function _nextItem() { return (queueIndex + 1 < queue.length) ? queue[queueIndex + 1] : null }
    function _nextOverlayEnabled() {
        if (!config) return true
        var v = config.value("playback/nextVideoOverlay", true)
        return (v === true || v === "true" || v === 1 || v === "1")
    }
    // Mirror web's showComingUpNextIfNeeded thresholds: only for episodes with a
    // next item, runtime >= 10 min, >= 20s left, within the last 30/35/40s.
    function _checkUpNext() {
        if (root.upNextDismissed || root.upNextVisible) return
        if (!_nextOverlayEnabled()) return
        var it = root.currentItem
        if (!it || it.type !== "Episode" || !_nextItem()) return
        var runtime = player.duration
        var pos = player.position
        if (runtime < 600) return
        var showAtSecondsLeft = runtime >= 3000 ? 40 : (runtime >= 2400 ? 35 : 30)
        var remaining = runtime - pos
        if (pos >= (runtime - showAtSecondsLeft) && remaining >= 20)
            root.upNextVisible = true
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
            client.reportPlaybackStopped(player.currentId, Math.round(root.reportSeconds() * 10000000))
        root.setFullscreen(false)
        player.playing = false
        root.videoReady = false
        root._transcodeOffset = 0
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

        onFileLoaded: {
            console.log("[mpv] file loaded — streaming OK")
            root.applySubtitleStyle()
        }
        // First presented frame (fires after the loadfile start= seek lands) —
        // only now drop the opaque backdrop, or the transparent window flashes
        // the desktop while mpv is still seeking to the resume point.
        onPlaybackRestart: {
            if (root.videoReady) return
            root.videoReady = true
            // hwdec-current is reliably populated by now (it was blank at file-loaded)
            console.log("[mpv] vo:", player.queryProperty("current-vo"),
                        "| gpu-api:", player.queryProperty("gpu-api"),
                        "| hwdec:", player.queryProperty("hwdec-current"))
        }
        onEndFile: (reason, error) => {
            console.log("[mpv] end-file, reason:", reason, error.length ? ("— " + error) : "")
            if (reason === "eof")
                (root.autoPlayNext || root.repeatMode !== 0) ? root.playNext() : root.stop()
            else if (reason === "error") {
                root.toast(qsTr("Playback failed: %1").arg(error.length ? error : qsTr("unknown error")))
                root.stop()
            } else if (reason !== "stop") // "quit"/"redirect": core gone or stream bounced
                root.stop()
        }
        // Playback-health surfacing: mpv errors (failed stream, bad mpv.conf
        // option, decoder trouble) pop a toast instead of dying silently.
        // Identical messages are suppressed for 10s so per-frame decode spam
        // can't flood the UI.
        property string _lastLogMsg: ""
        onMpvLog: (level, prefix, text) => {
            if (level !== "error" && level !== "fatal") return
            console.log("[mpv]", level, prefix + ":", text)
            // ffmpeg codec chatter ("h264: no frame!" after a mid-stream open,
            // per-frame decode grumbles) is transient and self-healing — log it
            // but don't toast. A decode failure that actually kills playback
            // still surfaces via the end-file error toast.
            if (prefix.startsWith("ffmpeg")) return
            if (text === _lastLogMsg && logDedup.running) return
            _lastLogMsg = text
            logDedup.restart()
            root.toast(prefix === "core" ? text : (prefix + ": " + text))
        }
        onTracksChanged: {
            console.log("[mpv] tracks — audio:", audioTracks.length, "subtitle:", subtitleTracks.length)
            // apply any detail-page default audio/subtitle once the tracks are known
            if (audioTracks.length > 0 && !root._tracksApplied
                    && (root._pendingAudioIndex >= 0 || root._pendingSubIndex >= -1))
                root._applyPendingTracks()
            // remember-selections: keep the live Jellyfin indices of whatever is
            // selected (OSD picks included). ffIndex == server index on direct
            // play only; skip transcodes and the empty end-of-file track list.
            if (root._tracksApplied && audioTracks.length > 0 && !root.streamInfo.isTranscode) {
                for (var i = 0; i < audioTracks.length; ++i)
                    if (audioTracks[i].selected) { root._lastAudioJf = audioTracks[i].ffIndex; break }
                var sel = -1
                for (var j = 0; j < subtitleTracks.length; ++j)
                    if (subtitleTracks[j].selected) { sel = subtitleTracks[j].ffIndex; break }
                root._lastSubJf = sel
            }
        }
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
        // hide the pointer with the OSD (it only auto-hides during playback);
        // any movement brings both back via showOsd()
        cursorShape: root.osdVisible ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: root.showOsd()
        onClicked: {
            root.forceActiveFocus() // re-grab keyboard for mpv key forwarding
            root.showOsd()
            player.setPaused(!player.paused)
        }
    }

    // Buffering (network stall) indicator — mpv paused itself to refill the
    // cache. Matches the spinner every client shows; hidden during normal play.
    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingSmall
        visible: player.playing && root.videoReady && player.buffering
        BusyIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            running: parent.visible
            width: 64; height: 64
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: player.bufferingPercent > 0 && player.bufferingPercent < 100
            text: player.bufferingPercent + " %"
            color: Theme.textPrimary
            font.pixelSize: Theme.fontNormal
            style: Text.Outline; styleColor: "#000000"
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
        streamInfo: root.streamInfo
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
        onToggleFullscreen: root.toggleFullscreen()
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

    // Up-next overlay card: next-episode thumbnail + countdown + Start Now / Hide.
    // Independent of the OSD auto-hide, like web's upnextdialog.
    Rectangle {
        id: upNextCard
        visible: root.upNextVisible && root._nextItem() !== null
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 40; bottomMargin: 96 }
        z: 60
        width: 440
        height: 116
        radius: Theme.radius
        color: Theme.surface
        border.color: Theme.divider
        border.width: 1
        opacity: 0.97

        readonly property var nx: root._nextItem() || ({})
        readonly property int secondsLeft: Math.max(0, Math.ceil(player.duration - player.position))

        Row {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            Image {
                width: 160; height: 90
                fillMode: Image.PreserveAspectCrop
                clip: true
                asynchronous: true
                cache: true
                source: (root.client && upNextCard.nx.id)
                        ? root.client.imageUrl(upNextCard.nx.id, "Primary", 180, upNextCard.nx.imageTag || "")
                        : ""
            }
            Column {
                width: parent.width - 160 - 12
                spacing: 5
                Text {
                    width: parent.width
                    text: qsTr("Next Episode Playing in %1").arg(qsTr("%1 Seconds").arg(upNextCard.secondsLeft))
                    color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.composeTitle(upNextCard.nx)
                    color: Theme.textPrimary; font.pixelSize: Theme.fontNormal
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                }
                Row {
                    spacing: 8
                    Button {
                        id: startNowBtn
                        hoverEnabled: true
                        padding: 7
                        onClicked: root.playNext()
                        background: Rectangle { radius: Theme.radius; color: startNowBtn.hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent }
                        contentItem: Text { text: qsTr("Start Now"); color: Theme.accentText; font.pixelSize: Theme.fontSmall; font.bold: true }
                    }
                    Button {
                        id: hideUpNextBtn
                        hoverEnabled: true
                        padding: 7
                        onClicked: { root.upNextDismissed = true; root.upNextVisible = false }
                        background: Rectangle { radius: Theme.radius; color: hideUpNextBtn.hovered ? Theme.surfaceHover : "transparent"; border.color: Theme.divider; border.width: 1 }
                        contentItem: Text { text: qsTr("Hide"); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall }
                    }
                }
            }
        }
    }

    // Poll position during playback: arm/auto-apply segment skips + up-next card.
    Timer {
        interval: 400
        repeat: true
        running: player.playing
        onTriggered: { root._checkSegments(); root._checkUpNext() }
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
            // nothing to report until mpv has the stream open (see reportSeconds)
            if (player.currentId.length > 0 && root.videoReady)
                root.client.reportPlaybackProgress(player.currentId,
                                                   Math.round(root.absPosition() * 10000000),
                                                   player.paused)
        }
    }
}
