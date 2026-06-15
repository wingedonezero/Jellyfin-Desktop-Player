import QtQuick
import QtQuick.Controls.Basic
import JellyfinDesktop

ApplicationWindow {
    id: win
    width: 1280
    height: 720
    visible: true
    title: qsTr("Jellyfin Desktop")
    color: "#101014"

    JellyfinClient {
        id: jellyfin
        serverUrl: (typeof initialServer !== "undefined") ? initialServer : ""
        onAuthenticatedChanged: console.log("[jf] authenticated:", authenticated, userName)
        onItemsReady: (tag, items) => console.log("[jf] items[" + tag + "]:", items.length)
        onErrorOccurred: (msg) => console.log("[jf] error:", msg)
        onAuthenticationFailed: (msg) => console.log("[jf] auth failed:", msg)
    }

    // Login / browse — hidden while a video is playing.
    Loader {
        anchors.fill: parent
        active: !player.playing
        sourceComponent: jellyfin.authenticated ? browseComponent : loginComponent
    }
    Component { id: loginComponent; LoginView { client: jellyfin } }
    Component {
        id: browseComponent
        BrowseView {
            client: jellyfin
            onPlayRequested: (itemId) => win.playItem(itemId)
        }
    }

    // Video surface — fills the window while playing.
    MpvVideoItem {
        id: player
        anchors.fill: parent
        visible: playing

        property bool playing: false
        property string currentId: ""

        onFileLoaded: console.log("[mpv] file loaded — streaming OK")
        onEndFile: (reason) => {
            console.log("[mpv] end-file, reason:", reason)
            win.stopPlayback()
        }

        MouseArea {
            anchors.fill: parent
            enabled: player.playing
            onClicked: player.command(["cycle", "pause"])
        }
    }

    Button {
        visible: player.playing
        text: qsTr("◀  Back")
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 12
        onClicked: win.stopPlayback()
    }

    function playItem(itemId) {
        player.currentId = itemId
        player.playing = true
        player.play(jellyfin.streamUrl(itemId))
        jellyfin.reportPlaybackStart(itemId)
        console.log("[jf] play", itemId)
    }

    function stopPlayback() {
        if (!player.playing)
            return
        if (player.currentId.length > 0)
            jellyfin.reportPlaybackStopped(player.currentId, 0)
        player.playing = false
        player.currentId = ""
        player.command(["stop"])
    }

    // --- dev/test: auto-login + auto-play, gated by env context properties ---
    Component.onCompleted: {
        if (typeof initialUser !== "undefined" && initialUser.length > 0)
            jellyfin.authenticate(initialUser, initialPass)
    }
    Connections {
        target: jellyfin
        function onAuthenticatedChanged() {
            if (jellyfin.authenticated && typeof autoPlay !== "undefined" && autoPlay)
                jellyfin.fetchResume("auto-resume")
        }
        function onItemsReady(tag, items) {
            if (typeof autoPlay === "undefined" || !autoPlay)
                return
            if (tag === "auto-resume") {
                if (items.length > 0)
                    win.playItem(items[0].id)
                else
                    jellyfin.fetchUserViews("auto-views")
            } else if (tag === "auto-views" && items.length > 0) {
                jellyfin.fetchItems(items[0].id, "auto-items")
            } else if (tag === "auto-items") {
                for (let i = 0; i < items.length; i++) {
                    if (!items[i].isFolder) {
                        win.playItem(items[i].id)
                        break
                    }
                }
            }
        }
    }
}
