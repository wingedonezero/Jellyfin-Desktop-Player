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
        active: !playerView.playing
        sourceComponent: jellyfin.authenticated ? browseComponent : loginComponent
    }
    Component { id: loginComponent; LoginView { client: jellyfin } }
    Component {
        id: browseComponent
        BrowseView {
            client: jellyfin
            onPlayRequested: (item) => playerView.playItem(item)
        }
    }

    PlayerView {
        id: playerView
        anchors.fill: parent
        visible: playing
        client: jellyfin
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
                    playerView.playItem(items[0])
                else
                    jellyfin.fetchUserViews("auto-views")
            } else if (tag === "auto-views" && items.length > 0) {
                jellyfin.fetchItems(items[0].id, "auto-items")
            } else if (tag === "auto-items") {
                for (let i = 0; i < items.length; i++) {
                    if (!items[i].isFolder) {
                        playerView.playItem(items[i])
                        break
                    }
                }
            }
        }
    }
}
