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

    property var resumeModel: []
    property var nextUpModel: []
    property var librariesModel: []
    property var latestByLib: ({})

    // Settings → Display: use episode stills vs the show poster in Next Up / Resume
    function cfgBool(key, def) {
        var v = config ? config.value(key, def) : def
        return v === true || v === "true" || v === 1 || v === "1"
    }
    readonly property bool useEpisodeImages: cfgBool("display/episodeImagesNextUp", true)

    // ordered list of home section keys (from Settings → Home; read at load)
    property var homeSections: []
    function loadSections() {
        const def = ["resume", "nextup", "mymedia", "latest", "none", "none"]
        let s = []
        for (var i = 0; i < 6; i++) {
            const k = config ? config.value("home/section" + i, def[i]) : def[i]
            if (k && k !== "none") s.push(k)
        }
        homeSections = s
    }
    // does a section have anything to show? (so empty slots don't reserve space)
    function sectionHasContent(key) {
        if (key === "resume") return resumeModel.length > 0
        if (key === "nextup") return nextUpModel.length > 0
        if (key === "mymedia" || key === "latest") return librariesModel.length > 0
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
    function reload() {
        if (!client) return
        client.fetchResume("home:resume")
        client.fetchNextUp("home:nextup")
        client.fetchUserViews("home:views")
    }

    Connections {
        target: screen.client
        function onAuthenticatedChanged() { screen.maybeReload() }
        function onItemsReady(tag, items) {
            if (tag === "home:resume") {
                screen.resumeModel = items
            } else if (tag === "home:nextup") {
                screen.nextUpModel = items
            } else if (tag === "home:views") {
                screen.librariesModel = items
                for (let i = 0; i < items.length; ++i)
                    screen.client.fetchLatest(items[i].id, "home:latest:" + items[i].id)
            } else if (tag.indexOf("home:latest:") === 0) {
                const id = tag.substring("home:latest:".length)
                let m = Object.assign({}, screen.latestByLib)
                m[id] = items
                screen.latestByLib = m
            }
        }
    }

    // one component per home-section type; the Repeater places them by slot order
    Component {
        id: resumeRow
        MediaRow {
            title: qsTr("Continue Watching"); model: screen.resumeModel
            client: screen.client; shape: "thumb"; episodeImages: screen.useEpisodeImages
            onItemActivated: (it) => screen.itemActivated(it)
            onItemOpenDetail: (it) => screen.itemOpenDetail(it)
            onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
            onItemAddToCollection: (it) => screen.itemAddToCollection(it)
        }
    }
    Component {
        id: nextUpRow
        MediaRow {
            title: qsTr("Next Up"); model: screen.nextUpModel
            client: screen.client; shape: "thumb"; episodeImages: screen.useEpisodeImages
            onItemActivated: (it) => screen.itemActivated(it)
            onItemOpenDetail: (it) => screen.itemOpenDetail(it)
            onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
            onItemAddToCollection: (it) => screen.itemAddToCollection(it)
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
                    visible: (screen.latestByLib[modelData.id] || []).length > 0
                    model: screen.latestByLib[modelData.id] || []
                    client: screen.client; shape: "poster"
                    onItemActivated: (it) => screen.itemActivated(it)
                    onItemOpenDetail: (it) => screen.itemOpenDetail(it)
                    onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                    onItemAddToCollection: (it) => screen.itemAddToCollection(it)
                }
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + Theme.spacingLarge * 2
        clip: true
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
                                   : modelData === "mymedia" ? myMediaRow
                                   : modelData === "latest" ? latestRows : null
                }
            }
        }
    }
}
