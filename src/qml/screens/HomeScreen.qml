import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// The Home screen (jellyfin-web style): Continue Watching, Next Up, My Media,
// and Latest-per-library rows. Composes MediaRow/MediaCard; all data via the
// client, routed by request tag.
Item {
    id: screen
    property var client
    property string pageTitle: qsTr("Home")

    signal itemActivated(var item)   // play
    signal itemOpenDetail(var item)  // open detail
    signal openLibrary(var lib)

    property var resumeModel: []
    property var nextUpModel: []
    property var librariesModel: []
    property var latestByLib: ({})

    // The Home page is the StackView's initial item, so it exists before login
    // finishes — only fetch once the client is authenticated (and again if auth
    // changes, e.g. re-login).
    Component.onCompleted: maybeReload()
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

            MediaRow {
                title: qsTr("Continue Watching")
                model: screen.resumeModel
                client: screen.client
                shape: "thumb"
                onItemActivated: (it) => screen.itemActivated(it)
                onItemOpenDetail: (it) => screen.itemOpenDetail(it)
            }
            MediaRow {
                title: qsTr("Next Up")
                model: screen.nextUpModel
                client: screen.client
                shape: "thumb"
                onItemActivated: (it) => screen.itemActivated(it)
                onItemOpenDetail: (it) => screen.itemOpenDetail(it)
            }
            MediaRow {
                title: qsTr("My Media")
                model: screen.librariesModel
                client: screen.client
                shape: "thumb"
                onItemActivated: (it) => screen.openLibrary(it)
                onItemOpenDetail: (it) => screen.openLibrary(it)
            }
            Repeater {
                model: screen.librariesModel
                MediaRow {
                    required property var modelData
                    title: qsTr("Latest %1").arg(modelData.name)
                    model: screen.latestByLib[modelData.id] || []
                    client: screen.client
                    shape: "poster"
                    onItemActivated: (it) => screen.itemActivated(it)
                    onItemOpenDetail: (it) => screen.itemOpenDetail(it)
                }
            }
        }
    }
}
