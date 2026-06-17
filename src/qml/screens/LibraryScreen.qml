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
    property string tagName: ""   // tag-filtered grid (no tabs)
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
    property var genrePreview: ({})   // genreId → preview items (genres-tab rows)
    property var studioPreview: ({})  // studioId → preview items (networks-tab rows)

    property int tab: 0
    property string viewMode: "poster"  // poster | thumb | banner | list (per-library)
    property string sortBy: "SortName"
    property string sortOrder: "Ascending"
    property string nameStartsWith: ""  // alphabet picker (NameStartsWith)
    // filter-dialog state — mirrors jellyfin-web filterdialog.js query fields
    property var fltFilters: []          // IsPlayed / IsUnplayed / IsResumable / IsFavorite
    property var fltSeriesStatus: []     // Continuing / Ended / Unreleased
    property var fltVideoTypes: []       // Bluray / Dvd
    property var fltGenres: []
    property var fltOfficialRatings: []
    property var fltTags: []
    property var fltYears: []
    property bool fltHasSubtitles: false
    property bool fltHasTrailer: false
    property bool fltHasSpecialFeature: false
    property bool fltHasThemeSong: false
    property bool fltHasThemeVideo: false
    property bool fltIs4K: false
    property bool fltIs3D: false
    property string fltHD: ""            // "" | "hd" | "sd"
    property var filterData: ({})        // {Genres,OfficialRatings,Tags,Years} from /Items/Filters
    property bool expFilters: true
    property bool expStatus: false
    property bool expFeatures: false
    property bool expVideo: false
    property bool expGenres: false
    property bool expRatings: false
    property bool expTags: false
    property bool expYears: false
    readonly property var alphabet: ["✕","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
    property int startIndex: 0
    property int totalCount: 0
    property int pageSize: 100   // display/libraryPageSize (0 = no pagination)

    readonly property bool filteredView: favorites || genreId !== "" || studioId !== "" || tagName !== ""
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

    readonly property string itemsTag: "lib:items:" + parentId + ":" + genreId + ":" + studioId + ":" + tagName + ":" + (favorites ? "f" : "")
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
        if (parentId !== "" && client) client.fetchItemFilters(parentId, includeType(), "lib:filters:" + parentId)
    }
    function setViewMode(m) { viewMode = m; if (config) config.setValue("library/view/" + parentId, m) }
    // Compute the kind FRESH from the current tab — the curKind binding is still
    // the previous tab's value inside this (tab) change handler (it hasn't
    // re-evaluated yet), which would load the wrong tab's content.
    onTabChanged: loadKind(filteredView ? "items" : (tabs[tab] ? tabs[tab].kind : "items"))

    function includeType() { return collectionType === "movies" ? "Movie" : collectionType === "tvshows" ? "Series" : "" }
    function toggleVal(arr, v) { var a = arr.slice(); var i = a.indexOf(v); if (i >= 0) a.splice(i, 1); else a.push(v); return a }
    function inArr(arr, v) { return arr.indexOf(v) >= 0 }
    function applyFilters() { startIndex = 0; reloadItems() }
    function fActive() {
        return fltFilters.length || fltSeriesStatus.length || fltVideoTypes.length || fltGenres.length
            || fltOfficialRatings.length || fltTags.length || fltYears.length
            || fltHasSubtitles || fltHasTrailer || fltHasSpecialFeature || fltHasThemeSong || fltHasThemeVideo
            || fltIs4K || fltIs3D || fltHD !== ""
    }
    function resetFilters() {
        fltFilters = []; fltSeriesStatus = []; fltVideoTypes = []; fltGenres = []
        fltOfficialRatings = []; fltTags = []; fltYears = []
        fltHasSubtitles = false; fltHasTrailer = false; fltHasSpecialFeature = false
        fltHasThemeSong = false; fltHasThemeVideo = false; fltIs4K = false; fltIs3D = false; fltHD = ""
        applyFilters()
    }
    function filterPart() {
        var p = []
        if (fltFilters.length) p.push("Filters=" + fltFilters.join(","))
        if (fltSeriesStatus.length) p.push("SeriesStatus=" + fltSeriesStatus.join(","))
        if (fltVideoTypes.length) p.push("VideoTypes=" + fltVideoTypes.join(","))
        if (fltGenres.length) p.push("Genres=" + fltGenres.map(g => encodeURIComponent(g)).join("|"))
        if (fltOfficialRatings.length) p.push("OfficialRatings=" + fltOfficialRatings.map(g => encodeURIComponent(g)).join("|"))
        if (fltTags.length) p.push("Tags=" + fltTags.map(g => encodeURIComponent(g)).join("|"))
        if (fltYears.length) p.push("Years=" + fltYears.join(","))
        if (fltHasSubtitles) p.push("HasSubtitles=true")
        if (fltHasTrailer) p.push("HasTrailer=true")
        if (fltHasSpecialFeature) p.push("HasSpecialFeature=true")
        if (fltHasThemeSong) p.push("HasThemeSong=true")
        if (fltHasThemeVideo) p.push("HasThemeVideo=true")
        if (fltIs4K) p.push("Is4K=true")
        if (fltIs3D) p.push("Is3D=true")
        if (fltHD === "hd") p.push("IsHD=true")
        else if (fltHD === "sd") p.push("IsHD=false")
        if (p.length === 0) return ""
        var q = "&Recursive=true"
        if (includeType() !== "") q += "&IncludeItemTypes=" + includeType()
        return q + "&" + p.join("&")
    }
    function reloadItems() {
        if (!client) return
        if (favorites) { client.fetchFavorites(itemsTag); return }
        if (genreId !== "") { client.fetchItemsPaged(parentId, itemsTag, sortBy, sortOrder, "&GenreIds=" + genreId + "&Recursive=true" + filterPart() + namePart(), startIndex, pageSize); return }
        if (studioId !== "") { client.fetchItemsPaged(parentId, itemsTag, sortBy, sortOrder, "&StudioIds=" + studioId + "&Recursive=true" + filterPart() + namePart(), startIndex, pageSize); return }
        if (tagName !== "") { client.fetchItemsPaged(parentId, itemsTag, sortBy, sortOrder, "&Tags=" + encodeURIComponent(tagName) + "&Recursive=true" + filterPart() + namePart(), startIndex, pageSize); return }
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
    // jellyfin-web genres tab: one preview row per genre (Random sample, capped)
    function loadGenrePreviews(list) {
        if (!client) return
        var inc = includeType() !== "" ? ("&IncludeItemTypes=" + includeType()) : ""
        for (var i = 0; i < list.length; i++)
            client.fetchItems(parentId, "lib:gpre:" + list[i].id, "Random", "Ascending",
                              "&GenreIds=" + list[i].id + "&Recursive=true" + inc + "&Limit=12")
    }
    function loadStudioPreviews(list) {
        if (!client) return
        var inc = includeType() !== "" ? ("&IncludeItemTypes=" + includeType()) : ""
        for (var i = 0; i < list.length; i++)
            client.fetchItems(parentId, "lib:spre:" + list[i].id, "Random", "Ascending",
                              "&StudioIds=" + list[i].id + "&Recursive=true" + inc + "&Limit=12")
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
            else if (tag === "lib:genres:" + screen.parentId) { screen.genres = its; screen.loadGenrePreviews(its) }
            else if (tag.indexOf("lib:gpre:") === 0) {
                var gid = tag.substring(9)
                var m = Object.assign({}, screen.genrePreview); m[gid] = its; screen.genrePreview = m
            }
            else if (tag === "lib:studios:" + screen.parentId) { screen.studios = its; screen.loadStudioPreviews(its) }
            else if (tag.indexOf("lib:spre:") === 0) {
                var sid = tag.substring(9)
                var sm = Object.assign({}, screen.studioPreview); sm[sid] = its; screen.studioPreview = sm
            }
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
        function onJsonReady(tag, data) { if (tag === "lib:filters:" + screen.parentId && data) screen.filterData = data }
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
    // ---- filter-dialog building blocks ----
    component FGroupHdr: ItemDelegate {
        id: gh
        property bool collapsed: true
        hoverEnabled: true; Layout.fillWidth: true; implicitHeight: 38
        background: Rectangle { color: gh.hovered ? Theme.surfaceHover : "transparent" }
        contentItem: RowLayout {
            Text { text: gh.collapsed ? "▸" : "▾"; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.leftMargin: 12 }
            Text { text: gh.text; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; Layout.fillWidth: true; Layout.leftMargin: 4 }
        }
    }
    component FChk: ItemDelegate {
        id: fchk
        property bool checkedState: false
        hoverEnabled: true; Layout.fillWidth: true; implicitHeight: 32
        background: Rectangle { radius: Theme.radius; color: fchk.hovered ? Theme.surfaceHover : "transparent" }
        contentItem: RowLayout {
            spacing: 8
            Rectangle {
                Layout.leftMargin: 24
                width: 16; height: 16; radius: 3
                border.color: fchk.checkedState ? Theme.accent : Theme.divider; border.width: 1
                color: fchk.checkedState ? Theme.accent : "transparent"
                Text { anchors.centerIn: parent; text: fchk.checkedState ? "✓" : ""; color: Theme.accentText; font.pixelSize: 11; font.bold: true }
            }
            Text { text: fchk.text; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.rightMargin: 12; elide: Text.ElideRight }
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
                text: "▤"
                fg: screen.fActive() ? Theme.accent : Theme.textPrimary
                onClicked: filterDialog.open()
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
            // 4 genres — a preview row per genre (jellyfin-web genres tab)
            Flickable {
                contentWidth: width
                contentHeight: genreCol.implicitHeight + Theme.spacingLarge
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: genreCol
                    width: parent.width
                    y: Theme.spacing
                    spacing: Theme.spacingLarge
                    Repeater {
                        model: screen.genres
                        MediaRow {
                            required property var modelData
                            title: modelData.name
                            titleLink: true
                            model: screen.genrePreview[modelData.id] || []
                            client: screen.client
                            shape: "poster"
                            onItemActivated: (it) => screen.itemActivated(it)
                            onItemOpenDetail: (it) => screen.itemOpenDetail(it)
                            onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                            onItemAddToCollection: (it) => screen.itemAddToCollection(it)
                            onCardAction: (verb, it) => screen.cardAction(verb, it)
                            onTitleClicked: screen.openFiltered({ parentId: screen.parentId, collectionType: screen.collectionType, genreId: modelData.id, pageTitle: modelData.name })
                        }
                    }
                }
            }
            // 5 networks (studios) — a preview row per network (jellyfin-web)
            Flickable {
                contentWidth: width
                contentHeight: studioCol.implicitHeight + Theme.spacingLarge
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: studioCol
                    width: parent.width
                    y: Theme.spacing
                    spacing: Theme.spacingLarge
                    Repeater {
                        model: screen.studios
                        MediaRow {
                            required property var modelData
                            title: modelData.name
                            titleLink: true
                            model: screen.studioPreview[modelData.id] || []
                            client: screen.client
                            shape: "poster"
                            onItemActivated: (it) => screen.itemActivated(it)
                            onItemOpenDetail: (it) => screen.itemOpenDetail(it)
                            onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                            onItemAddToCollection: (it) => screen.itemAddToCollection(it)
                            onCardAction: (verb, it) => screen.cardAction(verb, it)
                            onTitleClicked: screen.openFiltered({ parentId: screen.parentId, collectionType: screen.collectionType, studioId: modelData.id, pageTitle: modelData.name })
                        }
                    }
                }
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

    // ---- filter dialog (mirrors jellyfin-web filterdialog.js) ----
    Popup {
        id: filterDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 440
        height: Math.min(parent ? parent.height - 80 : 600, 760)
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
        readonly property bool av: screen.collectionType === "movies" || screen.collectionType === "tvshows"
        contentItem: ColumnLayout {
            spacing: 0
            RowLayout {
                Layout.fillWidth: true; Layout.margins: 12
                Text { text: qsTr("Filters"); color: Theme.textPrimary; font.bold: true; font.pixelSize: Theme.fontLarge; Layout.fillWidth: true }
                Button {
                    id: resetBtn; hoverEnabled: true; padding: 6; enabled: screen.fActive()
                    onClicked: screen.resetFilters()
                    background: Rectangle { radius: Theme.radius; color: resetBtn.hovered && resetBtn.enabled ? Theme.surfaceHover : "transparent"; border.color: Theme.divider; border.width: 1 }
                    contentItem: Text { text: qsTr("Reset"); color: resetBtn.enabled ? Theme.textPrimary : Theme.textDisabled; font.pixelSize: Theme.fontSmall }
                }
                JIconButton { text: "✕"; implicitWidth: 30; implicitHeight: 30; onClicked: filterDialog.close() }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }
            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width; contentHeight: groups.implicitHeight
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: groups
                    width: parent.width
                    spacing: 0

                    // Filters
                    FGroupHdr { text: qsTr("Filters"); collapsed: !screen.expFilters; onClicked: screen.expFilters = !screen.expFilters }
                    Repeater {
                        model: [{v:"IsPlayed",l:qsTr("Played")},{v:"IsUnplayed",l:qsTr("Unplayed")},{v:"IsResumable",l:qsTr("Resumable")},{v:"IsFavorite",l:qsTr("Favorites")}]
                        FChk {
                            required property var modelData
                            visible: screen.expFilters
                            text: modelData.l
                            checkedState: screen.inArr(screen.fltFilters, modelData.v)
                            onClicked: { screen.fltFilters = screen.toggleVal(screen.fltFilters, modelData.v); screen.applyFilters() }
                        }
                    }
                    // Series status (tvshows)
                    FGroupHdr { visible: screen.collectionType === "tvshows"; text: qsTr("Status"); collapsed: !screen.expStatus; onClicked: screen.expStatus = !screen.expStatus }
                    Repeater {
                        model: screen.collectionType === "tvshows" ? [{v:"Continuing",l:qsTr("Continuing")},{v:"Ended",l:qsTr("Ended")},{v:"Unreleased",l:qsTr("Unreleased")}] : []
                        FChk {
                            required property var modelData
                            visible: screen.expStatus
                            text: modelData.l
                            checkedState: screen.inArr(screen.fltSeriesStatus, modelData.v)
                            onClicked: { screen.fltSeriesStatus = screen.toggleVal(screen.fltSeriesStatus, modelData.v); screen.applyFilters() }
                        }
                    }
                    // Features (movies/tvshows)
                    FGroupHdr { visible: filterDialog.av; text: qsTr("Features"); collapsed: !screen.expFeatures; onClicked: screen.expFeatures = !screen.expFeatures }
                    FChk { visible: screen.expFeatures && filterDialog.av; text: qsTr("Subtitles"); checkedState: screen.fltHasSubtitles; onClicked: { screen.fltHasSubtitles = !screen.fltHasSubtitles; screen.applyFilters() } }
                    FChk { visible: screen.expFeatures && filterDialog.av; text: qsTr("Trailers"); checkedState: screen.fltHasTrailer; onClicked: { screen.fltHasTrailer = !screen.fltHasTrailer; screen.applyFilters() } }
                    FChk { visible: screen.expFeatures && filterDialog.av; text: qsTr("Special features"); checkedState: screen.fltHasSpecialFeature; onClicked: { screen.fltHasSpecialFeature = !screen.fltHasSpecialFeature; screen.applyFilters() } }
                    FChk { visible: screen.expFeatures && filterDialog.av; text: qsTr("Theme song"); checkedState: screen.fltHasThemeSong; onClicked: { screen.fltHasThemeSong = !screen.fltHasThemeSong; screen.applyFilters() } }
                    FChk { visible: screen.expFeatures && filterDialog.av; text: qsTr("Theme video"); checkedState: screen.fltHasThemeVideo; onClicked: { screen.fltHasThemeVideo = !screen.fltHasThemeVideo; screen.applyFilters() } }
                    // Video types (movies/tvshows)
                    FGroupHdr { visible: filterDialog.av; text: qsTr("Video types"); collapsed: !screen.expVideo; onClicked: screen.expVideo = !screen.expVideo }
                    FChk { visible: screen.expVideo && filterDialog.av; text: qsTr("Blu-ray"); checkedState: screen.inArr(screen.fltVideoTypes,"Bluray"); onClicked: { screen.fltVideoTypes = screen.toggleVal(screen.fltVideoTypes,"Bluray"); screen.applyFilters() } }
                    FChk { visible: screen.expVideo && filterDialog.av; text: qsTr("DVD"); checkedState: screen.inArr(screen.fltVideoTypes,"Dvd"); onClicked: { screen.fltVideoTypes = screen.toggleVal(screen.fltVideoTypes,"Dvd"); screen.applyFilters() } }
                    FChk { visible: screen.expVideo && filterDialog.av; text: qsTr("HD"); checkedState: screen.fltHD === "hd"; onClicked: { screen.fltHD = (screen.fltHD === "hd" ? "" : "hd"); screen.applyFilters() } }
                    FChk { visible: screen.expVideo && filterDialog.av; text: qsTr("4K"); checkedState: screen.fltIs4K; onClicked: { screen.fltIs4K = !screen.fltIs4K; screen.applyFilters() } }
                    FChk { visible: screen.expVideo && filterDialog.av; text: qsTr("SD"); checkedState: screen.fltHD === "sd"; onClicked: { screen.fltHD = (screen.fltHD === "sd" ? "" : "sd"); screen.applyFilters() } }
                    FChk { visible: screen.expVideo && filterDialog.av; text: qsTr("3D"); checkedState: screen.fltIs3D; onClicked: { screen.fltIs3D = !screen.fltIs3D; screen.applyFilters() } }
                    // Genres (dynamic)
                    FGroupHdr { visible: (screen.filterData.Genres || []).length > 0; text: qsTr("Genres"); collapsed: !screen.expGenres; onClicked: screen.expGenres = !screen.expGenres }
                    Repeater {
                        model: screen.filterData.Genres || []
                        FChk { required property var modelData; visible: screen.expGenres; text: modelData; checkedState: screen.inArr(screen.fltGenres, modelData); onClicked: { screen.fltGenres = screen.toggleVal(screen.fltGenres, modelData); screen.applyFilters() } }
                    }
                    // Parental ratings (dynamic)
                    FGroupHdr { visible: (screen.filterData.OfficialRatings || []).length > 0; text: qsTr("Parental ratings"); collapsed: !screen.expRatings; onClicked: screen.expRatings = !screen.expRatings }
                    Repeater {
                        model: screen.filterData.OfficialRatings || []
                        FChk { required property var modelData; visible: screen.expRatings; text: modelData; checkedState: screen.inArr(screen.fltOfficialRatings, modelData); onClicked: { screen.fltOfficialRatings = screen.toggleVal(screen.fltOfficialRatings, modelData); screen.applyFilters() } }
                    }
                    // Tags (dynamic)
                    FGroupHdr { visible: (screen.filterData.Tags || []).length > 0; text: qsTr("Tags"); collapsed: !screen.expTags; onClicked: screen.expTags = !screen.expTags }
                    Repeater {
                        model: screen.filterData.Tags || []
                        FChk { required property var modelData; visible: screen.expTags; text: modelData; checkedState: screen.inArr(screen.fltTags, modelData); onClicked: { screen.fltTags = screen.toggleVal(screen.fltTags, modelData); screen.applyFilters() } }
                    }
                    // Years (dynamic)
                    FGroupHdr { visible: (screen.filterData.Years || []).length > 0; text: qsTr("Years"); collapsed: !screen.expYears; onClicked: screen.expYears = !screen.expYears }
                    Repeater {
                        model: screen.filterData.Years || []
                        FChk { required property var modelData; visible: screen.expYears; text: "" + modelData; checkedState: screen.inArr(screen.fltYears, "" + modelData); onClicked: { screen.fltYears = screen.toggleVal(screen.fltYears, "" + modelData); screen.applyFilters() } }
                    }
                    Item { Layout.fillWidth: true; Layout.preferredHeight: 12 }
                }
            }
        }
    }
}
