import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// A library grid (jellyfin-web library view): a toolbar (item count + sort;
// filter stubbed) over a poster grid. Items via the client, routed by tag.
Item {
    id: screen
    property var client
    property string parentId: ""
    property string pageTitle: ""

    signal itemActivated(var item)
    signal itemOpenDetail(var item)

    property var items: []
    property string sortBy: "SortName"
    property string sortOrder: "Ascending"

    Component.onCompleted: reload()
    function reload() { if (client && parentId) client.fetchItems(parentId, "lib:" + parentId, sortBy, sortOrder) }
    function setSort(s) { sortBy = s; reload() }

    Connections {
        target: screen.client
        function onItemsReady(tag, its) { if (tag === "lib:" + screen.parentId) screen.items = its }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingSmall

        // toolbar
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pagePad
            Layout.rightMargin: Theme.pagePad
            Layout.topMargin: Theme.spacing
            Text {
                text: qsTr("%n item(s)", "", screen.items.length)
                color: Theme.textSecondary
                font.pixelSize: Theme.fontNormal
                Layout.fillWidth: true
                verticalAlignment: Text.AlignVCenter
            }
            JIconButton {
                text: "⇅"
                onClicked: sortMenu.popup()
                DarkMenu {
                    id: sortMenu
                    DarkMenuItem { text: qsTr("Name"); onTriggered: screen.setSort("SortName") }
                    DarkMenuItem { text: qsTr("Date added"); onTriggered: screen.setSort("DateCreated") }
                    DarkMenuItem { text: qsTr("Release date"); onTriggered: screen.setSort("PremiereDate") }
                    DarkMenuItem { text: qsTr("Community rating"); onTriggered: screen.setSort("CommunityRating") }
                    DarkMenuItem { text: qsTr("Runtime"); onTriggered: screen.setSort("Runtime") }
                }
            }
            JIconButton { text: "▤"; enabled: Features.libraryFilters } // filter (stub)
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            leftMargin: Theme.pagePad
            rightMargin: Theme.pagePad
            topMargin: Theme.spacingSmall
            bottomMargin: Theme.spacingLarge
            cellWidth: Theme.cardPosterWidth + Theme.spacing
            cellHeight: Theme.cardPosterHeight + 50
            clip: true
            model: screen.items
            ScrollBar.vertical: ScrollBar {}

            delegate: Item {
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight
                MediaCard {
                    width: Theme.cardPosterWidth
                    item: modelData
                    client: screen.client
                    shape: "poster"
                    onActivated: (it) => screen.itemActivated(it)
                    onOpenDetail: (it) => screen.itemOpenDetail(it)
                }
            }
        }
    }
}
