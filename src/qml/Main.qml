import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
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
    // Transparent window: mpv renders in a native window stacked directly behind
    // this one and shows through the player's video region. The opaque backdrop
    // below covers everything except during playback, so the browse UI is solid.
    color: "transparent"

    readonly property bool autoPlayEnabled: (typeof autoPlay !== "undefined") && autoPlay
    // dev/test: JFD_AUTOSTOP=<secs> backs out of playback automatically
    readonly property int autoStopAfter: (typeof autoStopSecs !== "undefined") ? autoStopSecs : 0
    Timer {
        running: win.autoStopAfter > 0 && playerView.playing
        interval: win.autoStopAfter * 1000
        onTriggered: playerView.stop()
    }
    property var libraries: []

    JellyfinClient {
        id: jellyfin
        serverUrl: (typeof initialServer !== "undefined") ? initialServer : ""
        // Failures used to be log-only: a blank row or grid gave no hint why.
        // Show them as a toast (deduped — a dropped connection fails several
        // requests at once) so the user knows it's the server, not the app.
        onErrorOccurred: (msg) => {
            console.log("[jf] error:", msg)
            // signed out (login view has its own messages; a 401 cascade would
            // otherwise overwrite the "session expired" toast)
            if (!jellyfin.authenticated) return
            if (errorToastDedup.running) return
            errorToastDedup.restart()
            win.showToast(qsTr("Server request failed: %1").arg(msg))
        }
        onSessionExpired: (reason) => win.showToast(reason)
        onAuthenticationFailed: (msg) => console.log("[jf] auth failed:", msg)
    }
    Timer { id: errorToastDedup; interval: 8000 }

    AppConfig { id: appConfig }

    // Opaque app backdrop — covers the whole window so the browse/login UI is
    // solid. Hidden during playback so the transparent window reveals the mpv
    // video window behind it.
    Rectangle {
        anchors.fill: parent
        color: Theme.background
        visible: !playerView.playing || !playerView.videoReady
        z: -1000
    }

    // ---- routing ----------------------------------------------------------
    function goHome() { if (stack.depth > 1) stack.pop(null) }
    // Every page carries an objectName key; pushing the page that's already on
    // top is a no-op (🔍 while on Search, the current library from the drawer…)
    // instead of stacking a duplicate that needs two Backs and refetches.
    function pushPage(comp, props) {
        if (stack.currentItem && stack.currentItem.objectName === props.objectName) return
        stack.push(comp, props)
    }
    function openLibrary(lib) { pushPage(libraryComp, { objectName: "page:lib:" + lib.id, parentId: lib.id, pageTitle: lib.name, collectionType: lib.collectionType || "" }) }
    function openFavorites() { pushPage(libraryComp, { objectName: "page:favorites", favorites: true, pageTitle: qsTr("Favorites") }) }
    function openSearch() { pushPage(searchComp, { objectName: "page:search" }) }
    function openSettings() { pushPage(settingsComp, { objectName: "page:settings" }) }
    function openDetail(item) {
        if (item.type === "CollectionFolder" || item.type === "UserView")
            openLibrary(item)
        else if (item.type === "Studio") // e.g. from search: a studio is a filtered library list
            pushPage(libraryComp, { objectName: "page:studio:" + item.id, studioId: item.id, pageTitle: item.name })
        else
            pushPage(detailComp, { objectName: "page:detail:" + item.id, itemId: item.id, pageTitle: item.name })
    }
    function playItem(item) { playerView.playItem(item) }
    function playQueue(items, index, continueSeries) { playerView.playQueue(items, index, continueSeries === true) }

    property double _lastRefreshMs: 0
    function refreshAllPages() {
        win._lastRefreshMs = Date.now()
        for (var i = 0; i < stack.depth; ++i) {
            var page = stack.get(i)
            if (page && page.refreshUserData) page.refreshUserData()
        }
    }
    // Coming back to the app after being away (other window / screen off):
    // re-query the stacked pages so Continue Watching etc. is current, like
    // jellyfin-web refetching on visibilitychange. Throttled so quick focus
    // flips (menus, alt-tabbing around) don't hammer the server.
    onActiveChanged: {
        if (active && jellyfin.authenticated && !playerView.playing
                && Date.now() - win._lastRefreshMs > 60000)
            refreshAllPages()
    }

    // card context-menu actions (queue/playNext are live-queue ops) bubbled up
    // from any card via cardAction.
    function cardAction(verb, item) {
        if (!item) return
        if (verb === "queue") playerView.enqueue(item)
        else if (verb === "playNext") playerView.playNextInsert(item)
    }

    // shared "add to playlist/collection" picker, invoked from any card or detail
    property var addToItem: null
    property string addToKind: ""      // "playlist" | "collection"
    property var addToOptions: []
    function openAddTo(item, kind) {
        if (!item) return
        win.addToItem = item
        win.addToKind = kind
        win.addToOptions = []
        if (kind === "playlist") jellyfin.fetchPlaylists("shell:addto")
        else jellyfin.fetchCollections("shell:addto")
        addToPicker.open()
    }

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
            // Navigating back re-queries the revealed page (web parity: pages
            // refetch on viewshow) — a Detail visit may have changed played/
            // favorite state, and Home's rows go stale while covered.
            property int _prevDepth: 1
            onDepthChanged: {
                if (depth < _prevDepth && currentItem && currentItem.refreshUserData)
                    currentItem.refreshUserData()
                _prevDepth = depth
            }
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
            onItemAddToPlaylist: (it) => win.openAddTo(it, "playlist")
            onItemAddToCollection: (it) => win.openAddTo(it, "collection")
            onCardAction: (verb, it) => win.cardAction(verb, it)
        }
    }
    Component {
        id: libraryComp
        LibraryScreen {
            client: jellyfin
            config: appConfig
            onItemActivated: (it) => win.playItem(it)
            onItemOpenDetail: (it) => win.openDetail(it)
            onOpenFiltered: (props) => stack.push(libraryComp, props)
            onItemAddToPlaylist: (it) => win.openAddTo(it, "playlist")
            onItemAddToCollection: (it) => win.openAddTo(it, "collection")
            onCardAction: (verb, it) => win.cardAction(verb, it)
        }
    }
    Component {
        id: detailComp
        DetailScreen {
            client: jellyfin
            config: appConfig
            onPlay: (it) => win.playItem(it)
            onPlayQueue: (items, index, continueSeries) => win.playQueue(items, index, continueSeries)
            onOpenDetail: (it) => win.openDetail(it)
            onItemAddToPlaylist: (it) => win.openAddTo(it, "playlist")
            onItemAddToCollection: (it) => win.openAddTo(it, "collection")
            onCardAction: (verb, it) => win.cardAction(verb, it)
            onOpenFiltered: (props) => stack.push(libraryComp, props)
        }
    }
    Component {
        id: searchComp
        SearchScreen {
            client: jellyfin
            onItemActivated: (it) => win.playItem(it)
            onItemOpenDetail: (it) => win.openDetail(it)
            onItemAddToPlaylist: (it) => win.openAddTo(it, "playlist")
            onItemAddToCollection: (it) => win.openAddTo(it, "collection")
            onCardAction: (verb, it) => win.cardAction(verb, it)
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
        onToast: (message) => win.showToast(message)
    }

    // Window-level toast (playback errors, mpv.conf problems). Lives above the
    // player AND the shell so a message survives the player closing on failure.
    function showToast(message) {
        toastLabel.text = message
        toastPopup.visible = true
        toastTimer.restart()
    }
    Rectangle {
        id: toastPopup
        visible: false
        z: 10000
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 110 // above the OSD control bar
        width: Math.min(toastLabel.implicitWidth + 32, win.width - 80)
        height: toastLabel.implicitHeight + 20
        radius: Theme.radius
        color: "#E6202020"
        border.color: Theme.divider
        border.width: 1
        Text {
            id: toastLabel
            anchors.centerIn: parent
            width: parent.width - 32
            color: Theme.textPrimary
            font.pixelSize: Theme.fontNormal
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
        Timer { id: toastTimer; interval: 6000; onTriggered: toastPopup.visible = false }
        MouseArea { anchors.fill: parent; onClicked: toastPopup.visible = false }
    }

    // ---- shared add-to-playlist/collection picker -------------------------
    Popup {
        id: addToPicker
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 340
        padding: 8
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
        property bool creating: false
        onClosed: { creating = false; newName.clear() }
        contentItem: ColumnLayout {
            spacing: 2
            Text {
                Layout.fillWidth: true; Layout.leftMargin: 6; Layout.bottomMargin: 4
                text: (win.addToKind === "playlist" ? qsTr("Add to playlist") : qsTr("Add to collection"))
                      + (win.addToItem ? (" — " + win.addToItem.name) : "")
                color: Theme.textPrimary; font.bold: true; font.pixelSize: Theme.fontNormal; elide: Text.ElideRight
            }
            Repeater {
                model: win.addToOptions
                ItemDelegate {
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: 36; hoverEnabled: true
                    onClicked: {
                        if (win.addToKind === "playlist") jellyfin.addToPlaylist(modelData.id, win.addToItem.id)
                        else jellyfin.addToCollection(modelData.id, win.addToItem.id)
                        addToPicker.close()
                    }
                    contentItem: Text { text: modelData.name; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; leftPadding: 6; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                    background: Rectangle { radius: Theme.radius; color: parent.hovered ? Theme.surfaceHover : "transparent" }
                }
            }
            Text {
                visible: win.addToOptions.length === 0
                Layout.leftMargin: 6
                text: win.addToKind === "playlist" ? qsTr("No playlists yet.") : qsTr("No collections yet.")
                color: Theme.textSecondary; font.pixelSize: Theme.fontSmall
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider; Layout.topMargin: 4; Layout.bottomMargin: 4 }
            ItemDelegate {
                visible: !addToPicker.creating
                Layout.fillWidth: true; implicitHeight: 36; hoverEnabled: true
                onClicked: addToPicker.creating = true
                contentItem: Text { text: qsTr("＋ New…"); color: Theme.accent; font.pixelSize: Theme.fontNormal; leftPadding: 6; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: Theme.radius; color: parent.hovered ? Theme.surfaceHover : "transparent" }
            }
            RowLayout {
                visible: addToPicker.creating
                Layout.fillWidth: true
                TextField {
                    id: newName
                    Layout.fillWidth: true
                    placeholderText: qsTr("Name")
                    color: Theme.textPrimary
                    placeholderTextColor: Theme.textDisabled
                    background: Rectangle { implicitHeight: 32; radius: Theme.radius; color: Theme.background; border.color: Theme.accent; border.width: 1 }
                    onAccepted: createBtn.clicked()
                }
                JIconButton {
                    id: createBtn
                    text: "✓"; implicitWidth: 34; implicitHeight: 34
                    onClicked: {
                        if (newName.text.length && win.addToItem) {
                            if (win.addToKind === "playlist") jellyfin.createPlaylist(newName.text, win.addToItem.id)
                            else jellyfin.createCollection(newName.text, win.addToItem.id)
                            addToPicker.close()
                        }
                    }
                }
            }
        }
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
            else if (tag === "shell:addto")
                win.addToOptions = items
        }
        // The stop report / a played-favorite toggle has landed server-side, so
        // every stacked page refetches its userData — same as jellyfin-web
        // re-fetching item queries on playbackstop / mutation events.
        function onPlaybackStopReported() {
            console.log("[jf] stop reported — refreshing", stack.depth, "page(s)")
            win.refreshAllPages()
        }
        function onUserDataChanged() { win.refreshAllPages() }
    }

    // client-local display prefs that affect the whole UI — applied at start and
    // live when Settings changes them
    function applyDisplayPrefs() {
        var fa = appConfig.value("display/fastAnimations", false)
        Theme.fastAnimations = (fa === true || fa === "true" || fa === 1 || fa === "1")
    }
    Connections {
        target: appConfig
        function onValueChanged(key) { if (key === "display/fastAnimations") win.applyDisplayPrefs() }
    }

    Component.onCompleted: {
        applyDisplayPrefs()

        if (jellyfin.restoreSession()) // saved login: skip re-auth
            return
        if (typeof initialUser !== "undefined" && initialUser.length > 0)
            jellyfin.authenticate(initialUser, initialPass)
    }
}
