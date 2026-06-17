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
    function openLibrary(lib) { stack.push(libraryComp, { parentId: lib.id, pageTitle: lib.name, collectionType: lib.collectionType || "" }) }
    function openFavorites() { stack.push(libraryComp, { favorites: true, pageTitle: qsTr("Favorites") }) }
    function openSearch() { stack.push(searchComp) }
    function openSettings() { stack.push(settingsComp) }
    function openAdmin() { if (jellyfin.isAdmin) stack.push(adminComp) }
    function openDetail(item) {
        if (item.type === "CollectionFolder" || item.type === "UserView")
            openLibrary(item)
        else
            stack.push(detailComp, { itemId: item.id, pageTitle: item.name })
    }
    function playItem(item) { playerView.playItem(item) }
    function playQueue(items, index) { playerView.playQueue(items, index) }

    // card context-menu actions (queue/playNext are live-queue ops; refresh/delete
    // are confirm-gated server mutations) bubbled up from any card via cardAction.
    function cardAction(verb, item) {
        if (!item) return
        if (verb === "queue") playerView.enqueue(item)
        else if (verb === "playNext") playerView.playNextInsert(item)
        else if (verb === "refresh")
            confirmAction(qsTr("Refresh metadata for \"%1\"?").arg(item.name || ""),
                          function() { jellyfin.refreshItem(item.id) })
        else if (verb === "delete")
            confirmAction(qsTr("Delete \"%1\" from the server? This cannot be undone.").arg(item.name || ""),
                          function() { jellyfin.deleteItem(item.id) })
    }
    property string _confirmMsg: ""
    property var _confirmAction: null
    function confirmAction(msg, action) { win._confirmMsg = msg; win._confirmAction = action; confirmDialog.open() }

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
            onAdminClicked: win.openAdmin()
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
        onNavAdmin: win.openAdmin()
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
            onPlayQueue: (items, index) => win.playQueue(items, index)
            onOpenDetail: (it) => win.openDetail(it)
            onItemAddToPlaylist: (it) => win.openAddTo(it, "playlist")
            onItemAddToCollection: (it) => win.openAddTo(it, "collection")
            onCardAction: (verb, it) => win.cardAction(verb, it)
            onDeleted: stack.pop()
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
    Component {
        id: adminComp
        AdminScreen { client: jellyfin }
    }

    // ---- player overlay ---------------------------------------------------
    PlayerView {
        id: playerView
        anchors.fill: parent
        visible: playing
        client: jellyfin
        config: appConfig
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

    // ---- shared confirm dialog (card refresh / delete) -------------------
    Popup {
        id: confirmDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 380
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
        contentItem: ColumnLayout {
            spacing: 14
            Text { Layout.fillWidth: true; text: win._confirmMsg; color: Theme.textPrimary
                   font.pixelSize: Theme.fontNormal; wrapMode: Text.Wrap }
            RowLayout {
                Layout.alignment: Qt.AlignRight; spacing: 8
                Button {
                    id: cdCancel; hoverEnabled: true; padding: 8; onClicked: confirmDialog.close()
                    background: Rectangle { radius: Theme.radius; color: cdCancel.hovered ? Theme.surfaceHover : "transparent"
                                            border.color: Theme.divider; border.width: 1 }
                    contentItem: Text { text: qsTr("Cancel"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal }
                }
                Button {
                    id: cdOk; hoverEnabled: true; padding: 8
                    onClicked: { if (win._confirmAction) win._confirmAction(); confirmDialog.close() }
                    background: Rectangle { radius: Theme.radius; color: cdOk.hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent }
                    contentItem: Text { text: qsTr("Confirm"); color: Theme.accentText; font.pixelSize: Theme.fontNormal; font.bold: true }
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
    }

    Component.onCompleted: {
        // apply client-local display prefs that affect the whole UI
        var fa = appConfig.value("display/fastAnimations", false)
        Theme.fastAnimations = (fa === true || fa === "true" || fa === 1 || fa === "1")

        if (jellyfin.restoreSession()) // saved login: skip re-auth
            return
        if (typeof initialUser !== "undefined" && initialUser.length > 0)
            jellyfin.authenticate(initialUser, initialPass)
    }
}
