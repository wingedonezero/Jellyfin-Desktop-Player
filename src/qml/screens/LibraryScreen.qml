import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// A library view (jellyfin-web): type-aware tabs over the content, a sort/filter
// toolbar on the grid, and a filter popup. Movies → Movies/Suggestions/
// Collections/Genres; TV → Series/Suggestions/Upcoming/Genres/Networks; other →
// Items/Genres. Also reused for Favorites and genre/studio-filtered grids (tabs
// hidden, single grid). All data via the client, routed by request tag.
Item {
    id: screen
    property var client
    property var config
    property string parentId: ""
    property string collectionType: ""
    property string genreId: ""   // genre-filtered grid (no tabs)
    property string studioId: ""  // studio/network-filtered grid (no tabs)
    property bool favorites: false
    property string pageTitle: ""

    signal itemActivated(var item)
    signal itemOpenDetail(var item)
    signal openFiltered(var props)
    signal itemAddToPlaylist(var item)
    signal itemAddToCollection(var item)
    signal cardAction(string verb, var item)

    // data per tab
    property var items: []
    property var genres: []
    property var studios: []
    property var collections: []
    property var upcoming: []
    property var sugRecs: []   // movie recommendation categories [{title,items}]
    property var sugLatest: []
    property var sugNext: []
    property var favItems: []
    property var episodeItems: []

    property int tab: 0
    property string viewMode: "poster"  // poster | thumb | banner | list (per-library)
    property string sortBy: "SortName"
    property string sortOrder: "Ascending"
    property string playedFilter: "all" // all | unplayed | played | resumable
    property bool favFilter: false
    property string nameStartsWith: ""  // alphabet picker (NameStartsWith)
    readonly property var alphabet: ["✕","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
    property int startIndex: 0
    property int totalCount: 0
    property int pageSize: 100   // display/libraryPageSize (0 = no pagination)

    readonly property bool filteredView: favorites || genreId !== "" || studioId !== ""
    readonly property var tabs: {
        if (filteredView) return []
        if (collectionType === "movies")
            return [{ label: qsTr("Movies"), kind: "items" }, { label: qsTr("Suggestions"), kind: "suggestions" },
                    { label: qsTr("Favorites"), kind: "favorites" }, { label: qsTr("Collections"), kind: "collections" },
                    { label: qsTr("Genres"), kind: "genres" }]
        if (collectionType === "tvshows")
            return [{ label: qsTr("Series"), kind: "items" }, { label: qsTr("Suggestions"), kind: "suggestions" },
                    { label: qsTr("Upcoming"), kind: "upcoming" }, { label: qsTr("Genres"), kind: "genres" },
                    { label: qsTr("Networks"), kind: "networks" }, { label: qsTr("Episodes"), kind: "episodes" }]
        return [{ label: qsTr("Items"), kind: "items" }, { label: qsTr("Genres"), kind: "genres" }]
    }
    readonly property string curKind: filteredView ? "items" : (tabs[tab] ? tabs[tab].kind : "items")
    readonly property var kindIndex: ({ items: 0, suggestions: 1, collections: 2, upcoming: 3, genres: 4, networks: 5, favorites: 6, episodes: 7 })

    readonly property string itemsTag: "lib:items:" + parentId + ":" + genreId + ":" + studioId + ":" + (favorites ? "f" : "")
    readonly property var suggestions: {
        var out = []
        if (collectionType === "tvshows") {
            if (sugNext.length) out.push({ title: qsTr("Next Up"), items: sugNext })
        } else {
            for (var i = 0; i < sugRecs.length; ++i) out.push(sugRecs[i])
        }
        if (sugLatest.length) out.push({ title: qsTr("Latest"), items: sugLatest })
        return out
    }

    Component.onCompleted: {
        if (config) {
            viewMode = config.value("library/view/" + parentId, "poster")
            pageSize = Number(config.value("display/libraryPageSize", 100))
            if (isNaN(pageSize) || pageSize < 0) pageSize = 100
        }
        reloadItems()
        loadKind(curKind)  // load the initial tab's content if it isn't the items grid
    }
    function setViewMode(m) { viewMode = m; if (config) config.setValue("library/view/" + parentId, m) }
    // Compute the kind FRESH from the current tab — the curKind binding is still
    // the previous tab's value inside this (tab) change handler (it hasn't
    // re-evaluated yet), which would load the wrong tab's content.
    onTabChanged: loadKind(filteredView ? "items" : (tabs[tab] ? tabs[tab].kind : "items"))

    function filterPart() {
        var f = []
        if (playedFilter === "unplayed") f.push("IsUnplayed")
        else if (playedFilter === "played") f.push("IsPlayed")
        else if (playedFilter === "resumable") f.push("IsResumable")
        if (favFilter) f.push("IsFavorite")
        return f.length ? ("&Filters=" + f.join(",") + "&Recursive=true") : ""
    }
    function reloadItems() {
        if (!client) return
        if (favorites) { client.fetchFavorites(itemsTag); return }
        if (genreId !== "") { client.fetchItemsPaged(parentId, itemsTag, sortBy, sortOrder, "&GenreIds=" + genreId + "&Recursive=true" + filterPart() + namePart(), startIndex, pageSize); return }
        if (studioId !== "") { client.fetchItemsPaged(parentId, itemsTag, sortBy, sortOrder, "&StudioIds=" + studioId + "&Recursive=true" + filterPart() + namePart(), startIndex, pageSize); return }
        if (parentId !== "") client.fetchItemsPaged(parentId, itemsTag, sortBy, sortOrder, filterPart() + namePart(), startIndex, pageSize)
    }
    function loadKind(kind) {
        if (!client) return
        if (kind === "genres" && genres.length === 0) client.fetchGenres(parentId, "lib:genres:" + parentId)
        else if (kind === "networks" && studios.length === 0) client.fetchStudios(parentId, "lib:studios:" + parentId)
        else if (kind === "collections" && collections.length === 0) client.fetchCollections("lib:collections:" + parentId)
        else if (kind === "upcoming" && upcoming.length === 0) client.fetchUpcoming("lib:upcoming:" + parentId)
        else if (kind === "suggestions" && suggestions.length === 0) {
            if (collectionType === "tvshows") client.fetchNextUp("lib:sugNext:" + parentId)
            else client.fetchRecommendations(parentId, "lib:sugRecs:" + parentId)
            client.fetchLatest(parentId, "lib:sugLatest:" + parentId)
        }
        else if (kind === "favorites" && favItems.length === 0)
            client.fetchItems(parentId, "lib:fav:" + parentId, sortBy, sortOrder, "&Filters=IsFavorite&Recursive=true&IncludeItemTypes=Movie&Limit=300")
        else if (kind === "episodes" && episodeItems.length === 0)
            client.fetchItems(parentId, "lib:eps:" + parentId, sortBy, sortOrder, "&IncludeItemTypes=Episode&Recursive=true&Limit=300")
    }
    function setSort(s) { sortBy = s; if (s.indexOf("SortName") !== 0) nameStartsWith = ""; startIndex = 0; reloadItems() }
    function setAlpha(l) { nameStartsWith = (l === "✕" ? "" : l); startIndex = 0; reloadItems() }
    function alphaSel(l) { return l === "✕" ? (nameStartsWith === "") : (nameStartsWith === l) }
    function namePart() { return nameStartsWith !== "" ? ("&NameStartsWith=" + encodeURIComponent(nameStartsWith)) : "" }
    function pagePrev() { startIndex = Math.max(0, startIndex - pageSize); reloadItems() }
    function pageNext() { startIndex = startIndex + pageSize; reloadItems() }
    function pageLabel() {
        if (pageSize > 0 && totalCount > 0) {
            var end = Math.min(startIndex + pageSize, totalCount)
            return (startIndex + 1) + "-" + end + " " + qsTr("of") + " " + totalCount
        }
        return qsTr("%n item(s)", "", items.length)
    }

    Connections {
        target: screen.client
        function onItemsReady(tag, its) {
            if (tag === screen.itemsTag) screen.items = its
            else if (tag === "lib:genres:" + screen.parentId) screen.genres = its
            else if (tag === "lib:studios:" + screen.parentId) screen.studios = its
            else if (tag === "lib:collections:" + screen.parentId) screen.collections = its
            else if (tag === "lib:upcoming:" + screen.parentId) screen.upcoming = its
            else if (tag === "lib:sugLatest:" + screen.parentId) screen.sugLatest = its
            else if (tag === "lib:sugNext:" + screen.parentId) screen.sugNext = its
            else if (tag === "lib:fav:" + screen.parentId) screen.favItems = its
            else if (tag === "lib:eps:" + screen.parentId) screen.episodeItems = its
        }
        function onItemsPageReady(tag, its, total, start) {
            if (tag === screen.itemsTag) { screen.items = its; screen.totalCount = total }
        }
        function onCategoriesReady(tag, cats) { if (tag === "lib:sugRecs:" + screen.parentId) screen.sugRecs = cats }
    }

    // ---- reusable bits ----
    component Tab: Item {
        id: t
        property string label: ""
        property bool active: false
        signal clicked()
        implicitWidth: tl.implicitWidth
        implicitHeight: 36
        Text { id: tl; anchors.centerIn: parent; text: t.label; color: t.active ? Theme.textPrimary : Theme.textSecondary; font.pixelSize: Theme.fontNormal; font.bold: t.active }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 2; color: Theme.accent; visible: t.active
        }
        TapHandler { onTapped: t.clicked() }
    }
    component ItemGrid: GridView {
        property var gitems: []
        property string gshape: "poster"
        signal activate(var it)
        signal openDetail(var it)
        signal addPlaylist(var it)
        signal addCollection(var it)
        signal cardAct(string verb, var it)
        leftMargin: Theme.pagePad; rightMargin: Theme.pagePad; topMargin: Theme.spacingSmall; bottomMargin: Theme.spacingLarge
        cellWidth: (gshape === "thumb" ? Theme.cardThumbWidth : Theme.cardPosterWidth) + Theme.spacing
        cellHeight: (gshape === "thumb" ? Theme.cardThumbHeight : Theme.cardPosterHeight) + 50
        clip: true
        model: gitems
        ScrollBar.vertical: ScrollBar {}
        delegate: Item {
            id: icell
            required property var modelData
            readonly property var grid: GridView.view
            width: grid.cellWidth
            height: grid.cellHeight
            MediaCard {
                width: icell.grid.gshape === "thumb" ? Theme.cardThumbWidth : Theme.cardPosterWidth
                item: icell.modelData; client: screen.client; shape: icell.grid.gshape
                onActivated: (it) => icell.grid.activate(it)
                onOpenDetail: (it) => icell.grid.openDetail(it)
                onAddToPlaylist: (it) => icell.grid.addPlaylist(it)
                onAddToCollection: (it) => icell.grid.addCollection(it)
                onCardAction: (verb, it) => icell.grid.cardAct(verb, it)
            }
        }
    }
    component WideList: ListView {
        property var litems: []
        property string lmode: "list"   // list | banner
        signal activate(var it)
        signal openDetail(var it)
        signal addPlaylist(var it)
        signal addCollection(var it)
        signal cardAct(string verb, var it)
        clip: true
        topMargin: Theme.spacingSmall; bottomMargin: Theme.spacingLarge
        spacing: Theme.spacingSmall
        model: litems
        ScrollBar.vertical: ScrollBar {}
        delegate: MediaWideRow {
            required property var modelData
            readonly property var view: ListView.view
            x: Theme.pagePad
            width: view.width - Theme.pagePad * 2
            item: modelData; client: screen.client; shape: view.lmode
            onActivated: (it) => view.activate(it)
            onOpenDetail: (it) => view.openDetail(it)
            onAddToPlaylist: (it) => view.addPlaylist(it)
            onAddToCollection: (it) => view.addCollection(it)
            onCardAction: (verb, it) => view.cardAct(verb, it)
        }
    }
    component ChipGrid: GridView {
        property var chips: []
        signal chosen(var chip)
        leftMargin: Theme.pagePad; rightMargin: Theme.pagePad; topMargin: Theme.spacingSmall; bottomMargin: Theme.spacingLarge
        cellWidth: Theme.cardThumbWidth + Theme.spacing
        cellHeight: 64
        clip: true
        model: chips
        ScrollBar.vertical: ScrollBar {}
        delegate: Item {
            id: ccell
            required property var modelData
            readonly property var grid: GridView.view
            width: grid.cellWidth
            height: grid.cellHeight
            Rectangle {
                width: Theme.cardThumbWidth; height: 52; radius: Theme.radius
                color: chipHover.hovered ? Theme.surfaceHover : Theme.surface
                border.color: chipHover.hovered ? Theme.accent : Theme.transparent
                border.width: 1
                Text { anchors.centerIn: parent; width: parent.width - Theme.spacing * 2; text: ccell.modelData.name; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter }
                HoverHandler { id: chipHover }
                TapHandler { onTapped: ccell.grid.chosen(ccell.modelData) }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingSmall

        // tabs
        RowLayout {
            visible: !screen.filteredView
            Layout.leftMargin: Theme.pagePad
            Layout.topMargin: Theme.spacingSmall
            spacing: Theme.spacingLarge
            Repeater {
                model: screen.tabs
                Tab {
                    required property int index
                    required property var modelData
                    label: modelData.label
                    active: screen.tab === index
                    onClicked: screen.tab = index
                }
            }
        }

        // toolbar (grid only)
        RowLayout {
            visible: screen.curKind === "items"
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pagePad
            Layout.rightMargin: Theme.pagePad
            Layout.topMargin: screen.filteredView ? Theme.spacing : 0
            JIconButton {
                text: "‹"; visible: screen.pageSize > 0 && screen.startIndex > 0
                onClicked: screen.pagePrev()
            }
            Text {
                text: screen.pageLabel()
                color: Theme.textSecondary; font.pixelSize: Theme.fontNormal
                verticalAlignment: Text.AlignVCenter
            }
            JIconButton {
                text: "›"; visible: screen.pageSize > 0 && (screen.startIndex + screen.pageSize) < screen.totalCount
                onClicked: screen.pageNext()
            }
            Item { Layout.fillWidth: true }
            JIconButton {
                text: "▦"
                onClicked: viewMenu.popup()
                DarkMenu {
                    id: viewMenu
                    DarkMenuItem { text: qsTr("Poster"); onTriggered: screen.setViewMode("poster") }
                    DarkMenuItem { text: qsTr("Thumbnail"); onTriggered: screen.setViewMode("thumb") }
                    DarkMenuItem { text: qsTr("Banner"); onTriggered: screen.setViewMode("banner") }
                    DarkMenuItem { text: qsTr("List"); onTriggered: screen.setViewMode("list") }
                }
            }
            JIconButton {
                text: "⇅"
                onClicked: sortMenu.popup()
                DarkMenu {
                    id: sortMenu
                    DarkMenuItem { text: qsTr("Name"); onTriggered: screen.setSort("SortName") }
                    DarkMenuItem { text: qsTr("Community rating"); onTriggered: screen.setSort("CommunityRating,SortName") }
                    DarkMenuItem { text: qsTr("Critic rating"); onTriggered: screen.setSort("CriticRating,SortName") }
                    DarkMenuItem { text: qsTr("Date added"); onTriggered: screen.setSort("DateCreated,SortName") }
                    DarkMenuItem { text: qsTr("Date played"); onTriggered: screen.setSort("DatePlayed,SortName") }
                    DarkMenuItem { text: qsTr("Parental rating"); onTriggered: screen.setSort("OfficialRating,SortName") }
                    DarkMenuItem { text: qsTr("Play count"); onTriggered: screen.setSort("PlayCount,SortName") }
                    DarkMenuItem { text: qsTr("Release date"); onTriggered: screen.setSort("ProductionYear,PremiereDate,SortName") }
                    DarkMenuItem { text: qsTr("Runtime"); onTriggered: screen.setSort("Runtime,SortName") }
                }
            }
            JIconButton {
                text: screen.sortOrder === "Ascending" ? "↑" : "↓"
                onClicked: { screen.sortOrder = (screen.sortOrder === "Ascending" ? "Descending" : "Ascending"); screen.startIndex = 0; screen.reloadItems() }
            }
            JIconButton {
                id: filterBtn
                text: "▤"
                fg: (screen.playedFilter !== "all" || screen.favFilter) ? Theme.accent : Theme.textPrimary
                onClicked: filterPopup.open()
                Popup {
                    id: filterPopup
                    width: 240
                    x: filterBtn.width - width
                    y: filterBtn.height + 4
                    padding: 8
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
                    contentItem: ColumnLayout {
                        spacing: 2
                        Text { text: qsTr("Status"); color: Theme.textDisabled; font.pixelSize: Theme.fontTiny; font.bold: true; Layout.leftMargin: 6 }
                        Repeater {
                            model: [{ k: "all", l: qsTr("All") }, { k: "unplayed", l: qsTr("Unplayed") }, { k: "played", l: qsTr("Played") }, { k: "resumable", l: qsTr("Resumable") }]
                            ItemDelegate {
                                required property var modelData
                                Layout.fillWidth: true; implicitHeight: 36; hoverEnabled: true
                                onClicked: { screen.playedFilter = modelData.k; screen.startIndex = 0; screen.reloadItems() }
                                contentItem: RowLayout {
                                    Text { text: modelData.l; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 6 }
                                    Text { text: screen.playedFilter === modelData.k ? "✓" : ""; color: Theme.accent; Layout.rightMargin: 6 }
                                }
                                background: Rectangle { radius: Theme.radius; color: parent.hovered ? Theme.surfaceHover : "transparent" }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider; Layout.topMargin: 4; Layout.bottomMargin: 4 }
                        ItemDelegate {
                            Layout.fillWidth: true; implicitHeight: 36; hoverEnabled: true
                            onClicked: { screen.favFilter = !screen.favFilter; screen.startIndex = 0; screen.reloadItems() }
                            contentItem: RowLayout {
                                Text { text: qsTr("Favorites only"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 6 }
                                Text { text: screen.favFilter ? "✓" : ""; color: Theme.accent; Layout.rightMargin: 6 }
                            }
                            background: Rectangle { radius: Theme.radius; color: parent.hovered ? Theme.surfaceHover : "transparent" }
                        }
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: screen.kindIndex[screen.curKind]

            // 0 items — poster/thumb grid or list/banner rows by view mode
            Item {
                id: itemsPane
                readonly property bool wide: screen.viewMode === "list" || screen.viewMode === "banner"
                readonly property bool alphaOn: screen.curKind === "items" && screen.sortBy.indexOf("SortName") === 0
                ItemGrid {
                    anchors.fill: parent
                    anchors.rightMargin: itemsPane.alphaOn ? 22 : 0
                    visible: !itemsPane.wide
                    gitems: itemsPane.wide ? [] : screen.items
                    gshape: screen.viewMode === "thumb" ? "thumb" : "poster"
                    onActivate: (it) => screen.itemActivated(it)
                    onOpenDetail: (it) => screen.itemOpenDetail(it)
                    onAddPlaylist: (it) => screen.itemAddToPlaylist(it)
                    onAddCollection: (it) => screen.itemAddToCollection(it)
                    onCardAct: (verb, it) => screen.cardAction(verb, it)
                }
                WideList {
                    anchors.fill: parent
                    anchors.rightMargin: itemsPane.alphaOn ? 22 : 0
                    visible: itemsPane.wide
                    litems: itemsPane.wide ? screen.items : []
                    lmode: screen.viewMode === "banner" ? "banner" : "list"
                    onActivate: (it) => screen.itemActivated(it)
                    onOpenDetail: (it) => screen.itemOpenDetail(it)
                    onAddPlaylist: (it) => screen.itemAddToPlaylist(it)
                    onAddCollection: (it) => screen.itemAddToCollection(it)
                    onCardAct: (verb, it) => screen.cardAction(verb, it)
                }
                // alphabet picker (NameStartsWith) — only when sorting by name
                Column {
                    visible: itemsPane.alphaOn
                    anchors { right: parent.right; rightMargin: 3; verticalCenter: parent.verticalCenter }
                    Repeater {
                        model: screen.alphabet
                        Item {
                            id: al
                            required property var modelData
                            width: 16; height: 17
                            Text {
                                anchors.centerIn: parent
                                text: al.modelData
                                font.pixelSize: Theme.fontTiny
                                font.bold: screen.alphaSel(al.modelData)
                                color: screen.alphaSel(al.modelData) ? Theme.accent : Theme.textSecondary
                            }
                            TapHandler { onTapped: screen.setAlpha(al.modelData) }
                        }
                    }
                }
            }
            // 1 suggestions (rows)
            Flickable {
                contentWidth: width
                contentHeight: sugCol.implicitHeight + Theme.spacingLarge
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: sugCol
                    width: parent.width
                    y: Theme.spacing
                    spacing: Theme.spacingLarge
                    Repeater {
                        model: screen.suggestions
                        MediaRow {
                            required property var modelData
                            title: modelData.title
                            model: modelData.items
                            client: screen.client
                            shape: collectionType === "tvshows" ? "thumb" : "poster"
                            onItemActivated: (it) => screen.itemActivated(it)
                            onItemOpenDetail: (it) => screen.itemOpenDetail(it)
                            onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                            onItemAddToCollection: (it) => screen.itemAddToCollection(it)
                            onCardAction: (verb, it) => screen.cardAction(verb, it)
                        }
                    }
                }
            }
            // 2 collections
            ItemGrid {
                gitems: screen.collections
                gshape: "poster"
                onActivate: (it) => screen.itemOpenDetail(it)
                onOpenDetail: (it) => screen.itemOpenDetail(it)
                onAddPlaylist: (it) => screen.itemAddToPlaylist(it)
                onAddCollection: (it) => screen.itemAddToCollection(it)
                onCardAct: (verb, it) => screen.cardAction(verb, it)
            }
            // 3 upcoming
            ItemGrid {
                gitems: screen.upcoming
                gshape: "thumb"
                onActivate: (it) => screen.itemActivated(it)
                onOpenDetail: (it) => screen.itemOpenDetail(it)
                onAddPlaylist: (it) => screen.itemAddToPlaylist(it)
                onAddCollection: (it) => screen.itemAddToCollection(it)
                onCardAct: (verb, it) => screen.cardAction(verb, it)
            }
            // 4 genres
            ChipGrid {
                chips: screen.genres
                onChosen: (g) => screen.openFiltered({ parentId: screen.parentId, collectionType: screen.collectionType, genreId: g.id, pageTitle: g.name })
            }
            // 5 networks (studios)
            ChipGrid {
                chips: screen.studios
                onChosen: (s) => screen.openFiltered({ parentId: screen.parentId, collectionType: screen.collectionType, studioId: s.id, pageTitle: s.name })
            }
            // 6 favorites (movies)
            ItemGrid {
                gitems: screen.favItems
                gshape: "poster"
                onActivate: (it) => screen.itemActivated(it)
                onOpenDetail: (it) => screen.itemOpenDetail(it)
                onAddPlaylist: (it) => screen.itemAddToPlaylist(it)
                onAddCollection: (it) => screen.itemAddToCollection(it)
                onCardAct: (verb, it) => screen.cardAction(verb, it)
            }
            // 7 episodes (tv)
            ItemGrid {
                gitems: screen.episodeItems
                gshape: "thumb"
                onActivate: (it) => screen.itemActivated(it)
                onOpenDetail: (it) => screen.itemOpenDetail(it)
                onAddPlaylist: (it) => screen.itemAddToPlaylist(it)
                onAddCollection: (it) => screen.itemAddToCollection(it)
                onCardAct: (verb, it) => screen.cardAction(verb, it)
            }
        }
    }
}
