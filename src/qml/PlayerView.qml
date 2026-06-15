import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window
import JellyfinDesktop

// The playback layer: the mpv surface, the OSD controls, auto-hide, resume,
// and periodic progress reporting. Driven by a JellyfinClient passed in.
Item {
    id: root
    required property var client
    property alias playing: player.playing
    property bool osdVisible: true
    property var currentItem: ({})
    property bool favorite: false

    function playItem(item) {
        player.currentId = item.id
        root.currentItem = item
        root.favorite = (item.isFavorite === true)
        player.pendingResume = item.playbackTicks ? (item.playbackTicks / 10000000) : 0
        player.playing = true
        showOsd()
        player.play(client.streamUrl(item.id))
        client.reportPlaybackStart(item.id)
        console.log("[jf] play", item.id, "resume@", player.pendingResume)
    }

    function stop() {
        if (!player.playing)
            return
        if (player.currentId.length > 0)
            client.reportPlaybackStopped(player.currentId, Math.round(player.position * 10000000))
        player.playing = false
        player.currentId = ""
        player.command(["stop"])
    }

    function showOsd() {
        osdVisible = true
        osdTimer.restart()
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
        }
        onEndFile: (reason) => {
            console.log("[mpv] end-file, reason:", reason)
            root.stop()
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
        opacity: root.osdVisible ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        onBack: root.stop()
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
