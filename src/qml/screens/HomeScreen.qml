import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// The Home screen (jellyfin-web style). The rows shown and their order come from
// Settings → Home (home/section0..5): each slot is one of Continue Watching /
// Next Up / My Media / Latest-per-library / none, rendered top-to-bottom.
// Composes MediaRow/MediaCard; all data via the client, routed by request tag.
Item {
    id: screen
    property var client
    property var config: null
    property string pageTitle: qsTr("Home")

    signal itemActivated(var item)   // play
    signal itemOpenDetail(var item)  // open detail
    signal openLibrary(var lib)
    signal itemAddToPlaylist(var item)
    signal itemAddToCollection(var item)
    signal cardAction(string verb, var item)

    // Rows are ItemListModels updated IN PLACE on refresh (back-nav, playback
    // stop, watched toggles): the delegates and scroll offset survive, instead
    // of every row resetting to X=0 and re-creating its cards (visible blink).
    ItemListModel { id: resumeList }
    ItemListModel { id: nextUpList }
    property var librariesModel: []      // only reassigned when the set of libraries changes
    property var _latest: ({})           // libraryId → ItemListModel (plain JS map; mutated, never reassigned)
    Component { id: listModelComp; ItemListModel {} }
    function latestModel(libId) {
        if (!_latest[libId]) _latest[libId] = listModelComp.createObject(screen)
        return _latest[libId]
    }
    function sameIds(a, b) {
        if (a.length !== b.length) return false
        for (var i = 0; i < a.length; ++i) if (a[i].id !== b[i].id) return false
        return true
    }
    function clearAll() {
        resumeList.clear(); nextUpList.clear(); librariesModel = []
        for (var k in _latest) _latest[k].clear()
    }

    // Settings → Display: use episode stills vs the show poster in Next Up / Resume
    function cfgBool(key, def) {
        var v = config ? config.value(key, def) : def
        return v === true || v === "true" || v === 1 || v === "1"
    }
    property bool useEpisodeImages: cfgBool("display/episodeImagesNextUp", true)
    Connections {
        target: screen.config
        function onValueChanged(key) {
            if (key === "display/episodeImagesNextUp") screen.useEpisodeImages = screen.cfgBool(key, true)
        }
    }

    // ordered list of home section keys (from Settings → Home; read at load).
    // Tokens are jellyfin-web's HomeSectionType strings (smalllibrarytiles /
    // librarybuttons / resume / nextup / latestmedia / none); web's audio/book/
    // livetv section types are out of scope and render nothing.
    property var homeSections: []
    function loadSections() {
        const def = ["smalllibrarytiles", "resume", "nextup", "latestmedia", "none", "none", "none"]
        let s = []
        for (var i = 0; i < 7; i++) {
            let k = "" + (config ? config.value("home/section" + i, def[i]) : def[i])
            // migrate this app's pre-web-vocabulary tokens
            if (k === "mymedia") k = "smalllibrarytiles"
            else if (k === "latest") k = "latestmedia"
            if (k && k !== "none") s.push(k)
        }
        homeSections = s
    }
    // does a section have anything to show? (so empty slots don't reserve space)
    function sectionHasContent(key) {
        if (key === "resume") return resumeList.count > 0
        if (key === "nextup") return nextUpList.count > 0
        if (key === "smalllibrarytiles" || key === "librarybuttons" || key === "latestmedia")
            return librariesModel.length > 0
        return false
    }

    // The Home page is the StackView's initial item, so it exists before login
    // finishes — only fetch once the client is authenticated (and again if auth
    // changes, e.g. re-login).
    Component.onCompleted: {
        loadSections()
        maybeReload()
    }
    function maybeReload() { if (client && client.authenticated) reload() }
    // Playback just stopped: Continue Watching / Next Up / Latest are all stale.
    function refreshUserData() { maybeReload() }
    function reload() {
        if (!client) return
        client.fetchResume("home:resume")
        client.fetchNextUp("home:nextup")
        client.fetchUserViews("home:views")
    }

    Connections {
        target: screen.client
        function onAuthenticatedChanged() {
            // signed out: don't keep showing the previous user's rows
            if (screen.client && !screen.client.authenticated) screen.clearAll()
            screen.maybeReload()
        }
        function onItemsReady(tag, items) {
            if (tag === "home:resume") {
                resumeList.updateItems(items)
            } else if (tag === "home:nextup") {
                nextUpList.updateItems(items)
            } else if (tag === "home:views") {
                // reassigning recreates every Latest row — only when libraries changed
                if (!screen.sameIds(screen.librariesModel, items)) screen.librariesModel = items
                for (let i = 0; i < items.length; ++i)
                    screen.client.fetchLatest(items[i].id, "home:latest:" + items[i].id)
            } else if (tag.indexOf("home:latest:") === 0) {
                screen.latestModel(tag.substring("home:latest:".length)).updateItems(items)
            }
        }
    }

    // one component per home-section type; the Repeater places them by slot order
    Component {
        id: resumeRow
        MediaRow {
            title: qsTr("Continue Watching"); model: resumeList
            client: screen.client; shape: "thumb"; episodeImages: screen.useEpisodeImages
            onItemActivated: (it) => screen.itemActivated(it)
            onItemOpenDetail: (it) => screen.itemOpenDetail(it)
            onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
            onItemAddToCollection: (it) => screen.itemAddToCollection(it)
            onCardAction: (verb, it) => screen.cardAction(verb, it)
        }
    }
    Component {
        id: nextUpRow
        MediaRow {
            title: qsTr("Next Up"); model: nextUpList
            client: screen.client; shape: "thumb"; episodeImages: screen.useEpisodeImages
            onItemActivated: (it) => screen.itemActivated(it)
            onItemOpenDetail: (it) => screen.itemOpenDetail(it)
            onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
            onItemAddToCollection: (it) => screen.itemAddToCollection(it)
            onCardAction: (verb, it) => screen.cardAction(verb, it)
        }
    }
    Component {
        id: myMediaRow
        MediaRow {
            title: qsTr("My Media"); model: screen.librariesModel
            client: screen.client; shape: "thumb"
            onItemActivated: (it) => screen.openLibrary(it)
            onItemOpenDetail: (it) => screen.openLibrary(it)
        }
    }
    // web's "My Media (small)": a compact row of labelled buttons per library
    Component {
        id: libraryButtonsRow
        ColumnLayout {
            spacing: Theme.spacingSmall
            Text {
                text: qsTr("My Media")
                color: Theme.textPrimary
                font.pixelSize: Theme.fontMedium
                font.bold: true
                Layout.leftMargin: Theme.pagePad
            }
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pagePad
                Layout.rightMargin: Theme.pagePad
                spacing: Theme.spacingSmall
                Repeater {
                    model: screen.librariesModel
                    Rectangle {
                        required property var modelData
                        width: btnLabel.implicitWidth + 36
                        height: 40
                        radius: Theme.radius
                        color: btnHover.hovered ? Theme.surfaceHover : Theme.surface
                        border.color: Theme.divider
                        border.width: 1
                        Text {
                            id: btnLabel
                            anchors.centerIn: parent
                            text: parent.modelData.name
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontNormal
                        }
                        HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: screen.openLibrary(parent.modelData) }
                    }
                }
            }
        }
    }
    Component {
        id: latestRows
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingLarge
            Repeater {
                model: screen.librariesModel
                MediaRow {
                    required property var modelData
                    title: qsTr("Latest %1").arg(modelData.name)
                    model: screen.latestModel(modelData.id) // (MediaRow hides itself when empty)
                    client: screen.client; shape: "poster"
                    onItemActivated: (it) => screen.itemActivated(it)
                    onItemOpenDetail: (it) => screen.itemOpenDetail(it)
                    onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                    onItemAddToCollection: (it) => screen.itemAddToCollection(it)
                    onCardAction: (verb, it) => screen.cardAction(verb, it)
                }
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + Theme.spacingLarge * 2
        clip: true
        JSmoothWheel {}
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: col
            width: parent.width
            y: Theme.spacingLarge
            spacing: Theme.spacingLarge

            Repeater {
                model: screen.homeSections
                Loader {
                    required property var modelData
                    Layout.fillWidth: true
                    visible: screen.sectionHasContent(modelData)
                    Layout.preferredHeight: (visible && item) ? item.implicitHeight : 0
                    sourceComponent: modelData === "resume" ? resumeRow
                                   : modelData === "nextup" ? nextUpRow
                                   : modelData === "smalllibrarytiles" ? myMediaRow
                                   : modelData === "librarybuttons" ? libraryButtonsRow
                                   : modelData === "latestmedia" ? latestRows : null
                }
            }
        }
    }
}
