import QtQuick
import QtQuick.Controls.Basic
import JellyfinDesktop

// App shell: login (full screen) until authenticated, then the chrome — top
// AppBar + side NavDrawer + a StackView for the content pages — with the player
// as a full-window overlay. All navigation routes through the functions here.
ApplicationWindow {
    id: win
    width: 1280
    height: 800
    visible: true
    title: qsTr("Jellyfin Desktop")
    color: Theme.background

    readonly property bool autoPlayEnabled: (typeof autoPlay !== "undefined") && autoPlay
    property var libraries: []

    JellyfinClient {
        id: jellyfin
        serverUrl: (typeof initialServer !== "undefined") ? initialServer : ""
        onErrorOccurred: (msg) => console.log("[jf] error:", msg)
        onAuthenticationFailed: (msg) => console.log("[jf] auth failed:", msg)
    }

    AppConfig { id: appConfig }

    // ---- routing ----------------------------------------------------------
    function goHome() { if (stack.depth > 1) stack.pop(null) }
    function openLibrary(lib) { stack.push(libraryComp, { parentId: lib.id, pageTitle: lib.name }) }
    function openFavorites() { stack.push(libraryComp, { favorites: true, pageTitle: qsTr("Favorites") }) }
    function openSearch() { stack.push(searchComp) }
    function openSettings() { stack.push(settingsComp) }
    function openDetail(item) {
        if (item.type === "CollectionFolder" || item.type === "UserView")
            openLibrary(item)
        else
            stack.push(detailComp, { itemId: item.id, pageTitle: item.name })
    }
    function playItem(item) { playerView.playItem(item) }
    function playQueue(items, index) { playerView.playQueue(items, index) }

    // ---- login (no chrome) ------------------------------------------------
    Loader {
        anchors.fill: parent
        active: !jellyfin.authenticated
        sourceComponent: loginComp
    }
    Component { id: loginComp; LoginView { client: jellyfin } }

    // ---- authenticated shell ---------------------------------------------
    Item {
        id: shell
        anchors.fill: parent
        visible: jellyfin.authenticated && !playerView.playing

        AppBar {
            id: appBar
            anchors { top: parent.top; left: parent.left; right: parent.right }
            client: jellyfin
            title: (stack.currentItem && stack.currentItem.pageTitle) ? stack.currentItem.pageTitle : qsTr("Home")
            canGoBack: stack.depth > 1
            onMenuClicked: drawer.open()
            onBackClicked: stack.pop()
            onHomeClicked: win.goHome()
            onSearchClicked: win.openSearch()
            onSettingsClicked: win.openSettings()
            onLogoutClicked: jellyfin.logout()
        }

        StackView {
            id: stack
            anchors { top: appBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            initialItem: homeComp
        }
    }

    NavDrawer {
        id: drawer
        client: jellyfin
        libraries: win.libraries
        onNavHome: win.goHome()
        onNavFavorites: win.openFavorites()
        onNavLibrary: (lib) => win.openLibrary(lib)
        onNavSettings: win.openSettings()
        onNavAdmin: win.openSettings() // admin lands in the Settings → Administration section
        onDoLogout: jellyfin.logout()
    }

    // ---- page components --------------------------------------------------
    Component {
        id: homeComp
        HomeScreen {
            client: jellyfin
            config: appConfig
            onItemActivated: (it) => win.playItem(it)
            onItemOpenDetail: (it) => win.openDetail(it)
            onOpenLibrary: (lib) => win.openLibrary(lib)
        }
    }
    Component {
        id: libraryComp
        LibraryScreen {
            client: jellyfin
            onItemActivated: (it) => win.playItem(it)
            onItemOpenDetail: (it) => win.openDetail(it)
            onOpenFiltered: (props) => stack.push(libraryComp, props)
        }
    }
    Component {
        id: detailComp
        DetailScreen {
            client: jellyfin
            onPlay: (it) => win.playItem(it)
            onPlayQueue: (items, index) => win.playQueue(items, index)
            onOpenDetail: (it) => win.openDetail(it)
        }
    }
    Component {
        id: searchComp
        SearchScreen {
            client: jellyfin
            onItemActivated: (it) => win.playItem(it)
            onItemOpenDetail: (it) => win.openDetail(it)
        }
    }
    Component {
        id: settingsComp
        SettingsScreen {
            client: jellyfin
            config: appConfig
            onLogout: jellyfin.logout()
        }
    }

    // ---- player overlay ---------------------------------------------------
    PlayerView {
        id: playerView
        anchors.fill: parent
        visible: playing
        client: jellyfin
        config: appConfig
    }

    // ---- shell data + dev auto-login/auto-play ---------------------------
    Connections {
        target: jellyfin
        function onAuthenticatedChanged() {
            if (!jellyfin.authenticated) {
                win.libraries = []
                win.goHome()
                return
            }
            jellyfin.fetchUserViews("shell:views")
            if (win.autoPlayEnabled)
                jellyfin.fetchResume("auto:resume")
        }
        function onItemsReady(tag, items) {
            if (tag === "shell:views")
                win.libraries = items
            else if (tag === "auto:resume" && win.autoPlayEnabled && items.length > 0)
                win.playItem(items[0])
        }
    }

    Component.onCompleted: {
        if (jellyfin.restoreSession()) // saved login: skip re-auth
            return
        if (typeof initialUser !== "undefined" && initialUser.length > 0)
            jellyfin.authenticate(initialUser, initialPass)
    }
}
