import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// A library view (jellyfin-web): tabs (Items / Genres) over a poster grid, with
// a sort control. Also reused for Favorites (favorites:true) and genre-filtered
// listings (genreId set) — both hide the tabs and just show a grid.
Item {
    id: screen
    property var client
    property string parentId: ""
    property string genreId: ""    // when set: only items in this genre
    property bool favorites: false // when true: the user's favorites
    property string pageTitle: ""

    signal itemActivated(var item)
    signal itemOpenDetail(var item)
    signal openFiltered(var props) // push another LibraryScreen (e.g. a genre)

    property var items: []
    property var genres: []
    property int tab: 0 // 0 = items, 1 = genres
    property string sortBy: "SortName"
    property string sortOrder: "Ascending"

    readonly property bool showTabs: !favorites && genreId === ""
    readonly property string reqTag: favorites ? "lib:favorites"
                                    : (genreId !== "" ? ("lib:" + parentId + ":g:" + genreId)
                                                      : ("lib:" + parentId))

    Component.onCompleted: reloadItems()
    function reloadItems() {
        if (!client) return
        if (favorites) client.fetchFavorites(reqTag)
        else if (genreId !== "") client.fetchItemsInGenre(parentId, genreId, reqTag, sortBy, sortOrder)
        else if (parentId) client.fetchItems(parentId, reqTag, sortBy, sortOrder)
    }
    function reloadGenres() { if (client && parentId) client.fetchGenres(parentId, "genres:" + parentId) }
    function setSort(s) { sortBy = s; reloadItems() }
    onTabChanged: if (tab === 1 && genres.length === 0) reloadGenres()

    Connections {
        target: screen.client
        function onItemsReady(tag, its) {
            if (tag === screen.reqTag) screen.items = its
            else if (tag === "genres:" + screen.parentId) screen.genres = its
        }
    }

    component Tab: Item {
        id: t
        property string label: ""
        property bool active: false
        signal clicked()
        implicitWidth: tlabel.implicitWidth
        implicitHeight: 36
        Text {
            id: tlabel
            anchors.centerIn: parent
            text: t.label
            color: t.active ? Theme.textPrimary : Theme.textSecondary
            font.pixelSize: Theme.fontNormal
            font.bold: t.active
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 2
            color: Theme.accent
            visible: t.active
        }
        TapHandler { onTapped: t.clicked() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingSmall

        // tabs (plain library only)
        RowLayout {
            visible: screen.showTabs
            Layout.leftMargin: Theme.pagePad
            Layout.topMargin: Theme.spacingSmall
            spacing: Theme.spacingLarge
            Tab { label: qsTr("Items");  active: screen.tab === 0; onClicked: screen.tab = 0 }
            Tab { label: qsTr("Genres"); active: screen.tab === 1; onClicked: screen.tab = 1 }
        }

        // toolbar: count + sort (items grid only)
        RowLayout {
            visible: !screen.showTabs || screen.tab === 0
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pagePad
            Layout.rightMargin: Theme.pagePad
            Layout.topMargin: screen.showTabs ? 0 : Theme.spacing
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

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: screen.showTabs ? screen.tab : 0

            // items grid
            GridView {
                id: grid
                leftMargin: Theme.pagePad; rightMargin: Theme.pagePad
                topMargin: Theme.spacingSmall; bottomMargin: Theme.spacingLarge
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

            // genres grid
            GridView {
                id: genreGrid
                leftMargin: Theme.pagePad; rightMargin: Theme.pagePad
                topMargin: Theme.spacingSmall; bottomMargin: Theme.spacingLarge
                cellWidth: Theme.cardThumbWidth + Theme.spacing
                cellHeight: 64
                clip: true
                model: screen.genres
                ScrollBar.vertical: ScrollBar {}
                delegate: Item {
                    required property var modelData
                    width: genreGrid.cellWidth
                    height: genreGrid.cellHeight
                    Rectangle {
                        width: Theme.cardThumbWidth
                        height: 52
                        radius: Theme.radius
                        color: hover.hovered ? Theme.surfaceHover : Theme.surface
                        border.color: hover.hovered ? Theme.accent : Theme.transparent
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: modelData.name
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontNormal
                            elide: Text.ElideRight
                            width: parent.width - Theme.spacing * 2
                            horizontalAlignment: Text.AlignHCenter
                        }
                        HoverHandler { id: hover }
                        TapHandler {
                            onTapped: screen.openFiltered({ parentId: screen.parentId, genreId: modelData.id, pageTitle: modelData.name })
                        }
                    }
                }
            }
        }
    }
}
