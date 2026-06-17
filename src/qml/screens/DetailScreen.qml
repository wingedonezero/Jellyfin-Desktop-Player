import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// Item detail page (jellyfin-web): backdrop + poster + metadata, action row
// (Play/Resume, favorite, watched, more), overview, cast, and — for series —
// a season selector with an episode list, plus a "More Like This" row.
Item {
    id: screen
    property var client
    property var config: null
    property string itemId: ""
    property var detail: ({})
    property string pageTitle: (detail && detail.name) ? detail.name : qsTr("Details")

    // Settings → Display: show the details-page banner backdrop. QSettings can
    // hand back bools as "true"/"false" strings, so coerce. (Read on open; a
    // change applies the next time a detail page is opened.)
    function cfgBool(key, def) {
        var v = config ? config.value(key, def) : def
        return v === true || v === "true" || v === 1 || v === "1"
    }
    readonly property bool showBackdrop: cfgBool("display/backdrops", true)
                                         && cfgBool("display/detailsBanner", true)

    signal play(var item)
    signal playQueue(var items, int index)
    signal openDetail(var item)
    signal itemAddToPlaylist(var item)
    signal itemAddToCollection(var item)
    signal deleted()  // item was deleted → router pops this page

    // simple confirm dialog for destructive/server actions (refresh, delete)
    property string _confirmMsg: ""
    property var _confirmAction: null
    function confirm(msg, action) { _confirmMsg = msg; _confirmAction = action; confirmPopup.open() }

    property bool favorite: false
    property bool played: false
    property var cast: []
    property var seasons: []
    property var episodes: []
    property string selectedSeasonId: ""
    property string selectedSeasonName: ""
    property var similar: []

    readonly property bool isSeries: detail && detail.type === "Series"
    readonly property bool isPerson: detail && detail.type === "Person"
    readonly property bool isBoxSet: detail && detail.type === "BoxSet"
    readonly property bool isSeason: detail && detail.type === "Season"
    readonly property bool isEpisode: detail && detail.type === "Episode"
    readonly property bool isPlayableLeaf: detail && (detail.type === "Movie" || detail.type === "Episode"
                                                     || detail.type === "Video" || detail.type === "MusicVideo")
    property var filmography: []
    property var extras: []
    property var collectionItems: []   // BoxSet (collection) members
    property var seriesNextUp: []      // series detail: Next Up row
    property var moreFrom: []          // episode detail: other episodes this season

    // version / default-track selection (leaf items with media sources)
    property int selectedSourceIndex: 0
    property int selectedAudioIndex: -1
    property int selectedSubtitleIndex: -1
    readonly property var selectedSource: (detail && detail.mediaSources && detail.mediaSources.length > selectedSourceIndex)
                                          ? detail.mediaSources[selectedSourceIndex] : null
    function streamsOfType(t) {
        var src = selectedSource
        var streams = src ? src.streams : ((detail && detail.mediaStreams) ? detail.mediaStreams : [])
        return streams.filter(s => s.type === t)
    }
    function audioOptions() {
        var a = streamsOfType("Audio")
        return a.length > 1 ? a.map(s => ({ text: s.title || s.language || qsTr("Audio"), value: s.index })) : []
    }
    function subtitleOptions() {
        var s = streamsOfType("Subtitle")
        if (s.length === 0) return []
        return [{ text: qsTr("Off"), value: -1 }]
               .concat(s.map(x => ({ text: x.title || x.language || qsTr("Subtitle"), value: x.index })))
    }
    function selectSource(i) {
        selectedSourceIndex = i
        var src = selectedSource
        selectedAudioIndex = (src && src.defaultAudioIndex !== undefined) ? src.defaultAudioIndex : -1
        selectedSubtitleIndex = (src && src.defaultSubtitleIndex !== undefined) ? src.defaultSubtitleIndex : -1
    }
    // attach the chosen version + default audio/subtitle to a play request
    function _withSelections(item) {
        var it = Object.assign({}, item)
        if (selectedSource) it.mediaSourceId = selectedSource.id
        if (selectedAudioIndex >= 0) it.audioStreamIndex = selectedAudioIndex
        it.subtitleStreamIndex = selectedSubtitleIndex // -1 = off, >=0 = a stream
        return it
    }

    // collection members grouped by type, in a sensible display order
    readonly property var collectionGroups: {
        if (!isBoxSet) return []
        var buckets = ({})
        for (var i = 0; i < collectionItems.length; ++i) {
            var it = collectionItems[i]
            var key = (it.type === "Movie" || it.type === "Series" || it.type === "Episode"
                       || it.type === "Video" || it.type === "MusicAlbum") ? it.type : "Other"
            if (!buckets[key]) buckets[key] = []
            buckets[key].push(it)
        }
        var order = [["Movie", qsTr("Movies")], ["Series", qsTr("Shows")], ["Episode", qsTr("Episodes")],
                     ["MusicAlbum", qsTr("Albums")], ["Video", qsTr("Videos")], ["Other", qsTr("Items")]]
        var out = []
        for (var j = 0; j < order.length; ++j)
            if (buckets[order[j][0]]) out.push({ title: order[j][1], items: buckets[order[j][0]] })
        return out
    }
    readonly property var playableChildren: {
        var out = []
        for (var i = 0; i < collectionItems.length; ++i) {
            var t = collectionItems[i].type
            if (t === "Movie" || t === "Episode" || t === "Video" || t === "MusicVideo") out.push(collectionItems[i])
        }
        return out
    }

    Component.onCompleted: load()
    onItemIdChanged: load()
    function load() {
        if (!client || !itemId) return
        client.fetchItem(itemId, "d:item:" + itemId) // type-specific fetches follow once it returns
    }
    function selectSeason(s) {
        selectedSeasonId = s.id
        selectedSeasonName = s.name
        episodes = []
        client.fetchEpisodes(detail.id, s.id, "d:episodes:" + s.id)
    }
    function playEpisode(ep) {
        let idx = 0
        for (let i = 0; i < episodes.length; ++i)
            if (episodes[i].id === ep.id) { idx = i; break }
        screen.playQueue(episodes, idx) // queue the season so it auto-plays next
    }
    function playPrimary() {
        if (!detail) return
        if (isSeries) {
            // web: the series Play button starts at the global Next Up episode and
            // queues the whole series from there (crosses seasons)
            client.fetchNextUp("d:seriesplay:" + detail.id, detail.id)
        } else if (isSeason) {
            if (episodes.length > 0) {
                let ep = episodes[0]
                for (let i = 0; i < episodes.length; ++i)
                    if (!episodes[i].played) { ep = episodes[i]; break }
                playEpisode(ep)
            }
        } else if (isBoxSet) {
            if (playableChildren.length > 0) screen.playQueue(playableChildren, 0)
        } else {
            screen.play(_withSelections(detail))
        }
    }
    function shuffle() {
        if (!detail) return
        if (isSeries) client.fetchEpisodes(detail.id, "", "d:shuffle:" + detail.id) // whole series
        else if (isSeason) playShuffled(episodes)
        else if (isBoxSet) playShuffled(playableChildren)
    }
    function playShuffled(list) {
        if (!list || list.length === 0) return
        var a = list.slice()
        for (var i = a.length - 1; i > 0; --i) { // Fisher–Yates
            var j = Math.floor(Math.random() * (i + 1))
            var t = a[i]; a[i] = a[j]; a[j] = t
        }
        screen.playQueue(a, 0)
    }
    // play an item ignoring its saved resume position (web's "Play from beginning")
    function playFromStart(item) {
        var it = _withSelections(item)
        it.playbackTicks = 0
        screen.play(it)
    }
    function fmtRuntime(ticks) {
        const m = Math.round((ticks || 0) / 600000000)
        if (m <= 0) return ""
        const h = Math.floor(m / 60)
        return h > 0 ? (h + "h " + (m % 60) + "m") : (m + "m")
    }
    function metaLine() {
        const parts = []
        if (detail.productionYear && detail.productionYear > 0) parts.push("" + detail.productionYear)
        const rt = fmtRuntime(detail.runTimeTicks)
        if (rt) parts.push(rt)
        if (detail.officialRating) parts.push(detail.officialRating)
        return parts.join("   •   ")
    }
    function videoLine() {
        const v = (detail.mediaStreams || []).find(s => s.type === "Video")
        if (!v) return ""
        const res = (v.width && v.height) ? (v.width + "×" + v.height) : ""
        return [v.codec ? v.codec.toUpperCase() : "", res].filter(Boolean).join("  •  ")
    }
    function audioText() {
        return (detail.mediaStreams || []).filter(s => s.type === "Audio")
               .map(s => s.title || [s.codec, s.language].filter(Boolean).join(" ")).join(", ")
    }
    function subText() {
        return (detail.mediaStreams || []).filter(s => s.type === "Subtitle")
               .map(s => s.title || s.language || qsTr("Subtitle")).join(", ")
    }
    function fmtSize(bytes) {
        if (!bytes || bytes <= 0) return ""
        const gb = bytes / 1073741824
        return gb >= 1 ? (gb.toFixed(2) + " GB") : ((bytes / 1048576).toFixed(0) + " MB")
    }
    readonly property bool hasMediaInfo: !!(detail && detail.mediaStreams && detail.mediaStreams.length > 0)
    readonly property bool hasChapterImages: !!(detail && detail.chapters && detail.chapters.length > 0
                                                && detail.chapters[0].imageTag && detail.chapters[0].imageTag.length > 0)
    function fmtChapterTime(ticks) {
        var s = Math.floor((ticks || 0) / 10000000)
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60
        var p = (n) => (n < 10 ? "0" + n : "" + n)
        return (h > 0 ? h + ":" + p(m) : "" + m) + ":" + p(sec)
    }
    readonly property bool hasLogo: !!(detail && detail.logoTag && detail.logoTag.length > 0)
    property bool overviewExpanded: false
    function peopleByType(t) {
        var pp = (detail && detail.people) ? detail.people : []
        return pp.filter(p => p.type === t)
    }
    function fmtDate(iso) {
        if (!iso) return ""
        var d = new Date(iso)
        return isNaN(d.getTime()) ? "" : d.toLocaleDateString(Qt.locale(), Locale.LongFormat)
    }
    readonly property bool hasLinks: !!(detail && detail.externalUrls && detail.externalUrls.length > 0)

    Connections {
        target: screen.client
        function onItemsReady(tag, items) {
            if (tag === "d:item:" + screen.itemId) {
                screen.detail = items.length > 0 ? items[0] : ({})
                screen.favorite = screen.detail.isFavorite === true
                screen.played = screen.detail.played === true
                screen.cast = screen.detail.people || []
                screen.overviewExpanded = false
                screen.selectSource(0) // reset version + default tracks for the new item
                if (screen.isPerson) {
                    screen.client.fetchByPerson(screen.detail.id, "d:filmography:" + screen.itemId)
                } else {
                    screen.client.fetchSimilar(screen.itemId, "d:similar:" + screen.itemId)
                    screen.client.fetchSpecialFeatures(screen.itemId, "d:extras:" + screen.itemId)
                    if (screen.isSeries) {
                        screen.client.fetchSeasons(screen.detail.id, "d:seasons:" + screen.itemId)
                        screen.client.fetchNextUp("d:nextup:" + screen.detail.id, screen.detail.id)
                    } else if (screen.isBoxSet)
                        screen.client.fetchItems(screen.detail.id, "d:children:" + screen.itemId, "SortName", "Ascending")
                    else if (screen.isSeason)
                        screen.client.fetchEpisodes(screen.detail.seriesId, screen.detail.id, "d:episodes:" + screen.detail.id)
                    else if (screen.isEpisode && screen.detail.seriesId)
                        screen.client.fetchEpisodes(screen.detail.seriesId, screen.detail.seasonId, "d:morefrom:" + screen.detail.id)
                }
            } else if (tag === "d:seasons:" + screen.itemId) {
                screen.seasons = items
                if (items.length > 0) screen.selectSeason(items[0])
            } else if (screen.detail && tag === "d:seriesplay:" + screen.detail.id) {
                if (items.length > 0) screen.play(items[0])              // → auto-queues the series
                else if (screen.episodes.length > 0) screen.playEpisode(screen.episodes[0]) // all watched → rewatch
            } else if (screen.detail && tag === "d:shuffle:" + screen.detail.id) {
                screen.playShuffled(items)
            } else if (tag.indexOf("d:episodes:") === 0) {
                screen.episodes = items
            } else if (tag === "d:children:" + screen.itemId) {
                screen.collectionItems = items
            } else if (screen.detail && tag === "d:nextup:" + screen.detail.id) {
                screen.seriesNextUp = items
            } else if (screen.detail && tag === "d:morefrom:" + screen.detail.id) {
                screen.moreFrom = items.filter(e => e.id !== screen.detail.id) // exclude the current episode
            } else if (tag === "d:similar:" + screen.itemId) {
                screen.similar = items
            } else if (tag === "d:filmography:" + screen.itemId) {
                screen.filmography = items
            } else if (tag === "d:extras:" + screen.itemId) {
                screen.extras = items
            }
        }
    }

    // confirm dialog for destructive / server actions (refresh, delete)
    Popup {
        id: confirmPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 380
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
        contentItem: ColumnLayout {
            spacing: 14
            Text {
                Layout.fillWidth: true
                text: screen._confirmMsg
                color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                ActionButton { text: qsTr("Cancel"); onClicked: confirmPopup.close() }
                ActionButton {
                    primary: true; text: qsTr("Confirm")
                    onClicked: { if (screen._confirmAction) screen._confirmAction(); confirmPopup.close() }
                }
            }
        }
    }

    // reusable: a labeled dropdown for version / audio / subtitle selection
    component TrackSelect: RowLayout {
        id: ts
        property string label: ""
        property var options: []
        property var current: null
        signal picked(var value)
        Layout.fillWidth: true
        spacing: Theme.spacingSmall
        Text { text: ts.label; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: 70 }
        Button {
            id: tsBtn
            Layout.preferredWidth: 340
            hoverEnabled: true
            leftPadding: 12; rightPadding: 12; implicitHeight: Theme.controlHeight
            background: Rectangle { radius: Theme.radius; color: tsBtn.hovered ? Theme.surfaceHover : Theme.surface
                                    border.color: Theme.divider; border.width: 1 }
            contentItem: Text {
                text: { var o = ts.options.filter(x => x.value === ts.current); return (o.length ? o[0].text : "") + "   ▾" }
                color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
            }
            onClicked: tsMenu.popup()
            DarkMenu {
                id: tsMenu
                implicitWidth: 340
                Instantiator {
                    model: ts.options
                    delegate: DarkMenuItem {
                        required property var modelData
                        text: modelData.text
                        onTriggered: ts.picked(modelData.value)
                    }
                    onObjectAdded: (index, object) => tsMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => tsMenu.removeItem(object)
                }
            }
        }
    }

    // reusable: a small rounded action button with an accent (primary) variant
    component ActionButton: Button {
        property bool primary: false
        hoverEnabled: true
        implicitHeight: Theme.controlHeight
        leftPadding: 18
        rightPadding: 18
        font.pixelSize: Theme.fontNormal
        font.bold: primary
        background: Rectangle {
            radius: Theme.radius
            color: parent.primary
                   ? (parent.hovered ? Theme.accentHover : Theme.accent)
                   : (parent.hovered ? Theme.surfaceHover : Theme.surface)
            border.color: parent.primary ? Theme.transparent : Theme.divider
            border.width: parent.primary ? 0 : 1
        }
        contentItem: Text {
            text: parent.text
            font: parent.font
            color: parent.primary ? Theme.accentText : Theme.textPrimary
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component PersonTile: ColumnLayout {
        id: pt
        required property var modelData
        width: 96
        spacing: Theme.spacingTiny
        TapHandler { onTapped: screen.openDetail(pt.modelData) } // open the person page
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 80; height: 80; radius: 40
            color: Theme.surface
            clip: true
            Image {
                id: pimg
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; cache: true
                // People[] omits PrimaryImageTag even when the person item HAS an
                // image, so request by id unconditionally and fall back on 404.
                source: screen.client ? screen.client.imageUrl(pt.modelData.id, "Primary", 160, pt.modelData.imageTag || "") : ""
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: pimg.status !== Image.Ready
                text: "\u{1F464}"; font.pixelSize: 30; color: Theme.textDisabled
            }
        }
        Text {
            text: pt.modelData.name
            color: Theme.textPrimary; font.pixelSize: Theme.fontTiny
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            maximumLineCount: 1; Layout.fillWidth: true
        }
        Text {
            text: pt.modelData.role
            visible: text.length > 0
            color: Theme.textSecondary; font.pixelSize: Theme.fontTiny
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            maximumLineCount: 1; Layout.fillWidth: true
        }
    }

    component EpisodeRow: ItemDelegate {
        id: ep
        required property var modelData
        hoverEnabled: true
        Layout.fillWidth: true
        implicitHeight: 110
        background: Rectangle { radius: Theme.radius; color: ep.hovered ? Theme.surfaceHover : "transparent" }
        onClicked: screen.playEpisode(ep.modelData)
        contentItem: RowLayout {
            spacing: Theme.spacing
            Rectangle {
                Layout.preferredWidth: 160; Layout.preferredHeight: 90
                radius: Theme.radius; color: Theme.surface; clip: true
                Image {
                    anchors.fill: parent; fillMode: Image.PreserveAspectCrop
                    asynchronous: true; cache: true
                    source: ep.modelData.imageTag ? screen.client.imageUrl(ep.modelData.id, "Primary", 180, ep.modelData.imageTag) : ""
                    visible: status === Image.Ready
                }
                Text { anchors.centerIn: parent; text: "▶"; color: Theme.textPrimary; font.pixelSize: 24; visible: ep.hovered }
                Rectangle {
                    visible: ep.modelData.played === true
                    anchors { top: parent.top; right: parent.right; margins: 4 }
                    width: 18; height: 18; radius: 9; color: Theme.watched
                    Text { anchors.centerIn: parent; text: "✓"; color: Theme.accentText; font.pixelSize: 11; font.bold: true }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: (ep.modelData.indexNumber !== undefined ? (ep.modelData.indexNumber + ". ") : "") + ep.modelData.name
                    color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true
                    elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true
                }
                Text {
                    text: screen.fmtRuntime(ep.modelData.runTimeTicks)
                    visible: text.length > 0
                    color: Theme.textSecondary; font.pixelSize: Theme.fontTiny
                }
                Text {
                    text: ep.modelData.overview || ""
                    visible: text.length > 0
                    color: Theme.textSecondary; font.pixelSize: Theme.fontSmall
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: content
            width: parent.width
            spacing: Theme.spacingLarge

            // --- backdrop header ---
            Item {
                Layout.fillWidth: true
                implicitHeight: 360

                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true; cache: true
                    source: (screen.showBackdrop && screen.detail && screen.detail.hasBackdrop)
                            ? screen.client.imageUrl(screen.detail.id, "Backdrop", 720, "")
                            : ""
                    visible: status === Image.Ready
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.scrimSoft }
                        GradientStop { position: 1.0; color: Theme.background }
                    }
                }

                RowLayout {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                              leftMargin: Theme.pagePad; rightMargin: Theme.pagePad; bottomMargin: Theme.spacing }
                    spacing: Theme.spacingLarge

                    // poster
                    Rectangle {
                        Layout.preferredWidth: 180; Layout.preferredHeight: 270
                        radius: Theme.radius; color: Theme.surface; clip: true
                        Image {
                            anchors.fill: parent; fillMode: Image.PreserveAspectCrop
                            asynchronous: true; cache: true
                            source: (screen.detail && screen.detail.imageTag)
                                    ? screen.client.imageUrl(screen.detail.id, "Primary", 540, screen.detail.imageTag) : ""
                            visible: status === Image.Ready
                        }
                    }

                    // title + meta + actions
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        spacing: Theme.spacingSmall

                        // episode breadcrumb: clickable series name + SxxExx
                        RowLayout {
                            visible: screen.isEpisode && screen.detail && screen.detail.seriesName
                            spacing: 8
                            Text {
                                text: screen.detail ? (screen.detail.seriesName || "") : ""
                                color: seriesLinkHover.hovered ? Theme.accentHover : Theme.accent
                                font.pixelSize: Theme.fontNormal; font.bold: true
                                HoverHandler { id: seriesLinkHover }
                                TapHandler {
                                    onTapped: screen.openDetail({ id: screen.detail.seriesId,
                                                                  name: screen.detail.seriesName, type: "Series" })
                                }
                            }
                            Text {
                                visible: screen.detail && screen.detail.parentIndexNumber !== undefined
                                         && screen.detail.indexNumber !== undefined
                                text: "·  S" + (screen.detail ? screen.detail.parentIndexNumber : "")
                                      + ":E" + (screen.detail ? screen.detail.indexNumber : "")
                                color: Theme.textSecondary; font.pixelSize: Theme.fontNormal
                            }
                        }
                        // logo image (replaces the text title when present, like web)
                        Image {
                            visible: screen.hasLogo
                            source: screen.hasLogo
                                    ? screen.client.imageUrl(screen.detail.id, "Logo", 160, screen.detail.logoTag) : ""
                            fillMode: Image.PreserveAspectFit
                            horizontalAlignment: Image.AlignLeft
                            Layout.preferredHeight: 72
                            Layout.maximumWidth: 380
                            Layout.fillWidth: true
                            asynchronous: true; cache: true
                        }
                        Text {
                            visible: !screen.hasLogo
                            text: screen.detail ? (screen.detail.name || "") : ""
                            color: Theme.textPrimary; font.pixelSize: Theme.fontTitle; font.bold: true
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                        RowLayout {
                            spacing: Theme.spacing
                            Text { text: screen.metaLine(); color: Theme.textSecondary; font.pixelSize: Theme.fontNormal }
                            RowLayout {
                                spacing: 3
                                visible: screen.detail && screen.detail.communityRating > 0
                                Text { text: "★"; color: Theme.rating; font.pixelSize: Theme.fontNormal }
                                Text { text: screen.detail ? (Math.round(screen.detail.communityRating * 10) / 10) : ""
                                       color: Theme.textSecondary; font.pixelSize: Theme.fontNormal }
                            }
                            // critic rating (Rotten Tomatoes %), fresh/rotten coloured
                            Text {
                                visible: screen.detail && screen.detail.criticRating > 0
                                text: Math.round(screen.detail ? screen.detail.criticRating : 0) + "% " + qsTr("critics")
                                color: (screen.detail && screen.detail.criticRating >= 60) ? Theme.watched : Theme.error
                                font.pixelSize: Theme.fontNormal
                            }
                        }
                        Text {
                            text: (screen.detail && screen.detail.genres) ? screen.detail.genres.join(", ") : ""
                            visible: text.length > 0
                            color: Theme.textSecondary; font.pixelSize: Theme.fontSmall
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                        // director / writer rows
                        Repeater {
                            model: [{ label: qsTr("Director"), people: screen.peopleByType("Director") },
                                    { label: qsTr("Writer"),   people: screen.peopleByType("Writer") }]
                                   .filter(r => r.people.length > 0)
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.spacingSmall
                                Text { text: modelData.label; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: 70 }
                                Text { text: modelData.people.map(p => p.name).join(", "); color: Theme.textPrimary
                                       font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                        // person: born / died / birthplace
                        Repeater {
                            model: !screen.isPerson ? [] :
                                   [{ label: qsTr("Born"),       value: screen.fmtDate(screen.detail.premiereDate) },
                                    { label: qsTr("Died"),       value: screen.fmtDate(screen.detail.endDate) },
                                    { label: qsTr("Birthplace"), value: (screen.detail.productionLocations || []).join(", ") }]
                                   .filter(r => r.value && r.value.length > 0)
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.spacingSmall
                                Text { text: modelData.label; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: 90 }
                                Text { text: modelData.value; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                                       elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingSmall
                            Layout.topMargin: Theme.spacingSmall
                            ActionButton {
                                primary: true
                                visible: !screen.isPerson
                                text: (screen.detail && screen.detail.playbackTicks > 0) ? qsTr("▶  Resume") : qsTr("▶  Play")
                                enabled: (screen.isSeries || screen.isSeason) ? screen.episodes.length > 0
                                         : screen.isBoxSet ? screen.playableChildren.length > 0 : true
                                onClicked: screen.playPrimary()
                            }
                            JIconButton {
                                text: "↺"  // play from beginning (web's replay), only when resumable
                                visible: screen.isPlayableLeaf && screen.detail && screen.detail.playbackTicks > 0
                                onClicked: screen.playFromStart(screen.detail)
                            }
                            JIconButton {
                                text: "⇄"  // shuffle (series / season / collection) — 🔀 emoji is tofu on this font
                                visible: screen.isSeries || screen.isSeason || screen.isBoxSet
                                enabled: screen.isSeries ? screen.seasons.length > 0
                                         : screen.isSeason ? screen.episodes.length > 0
                                         : screen.playableChildren.length > 0
                                onClicked: screen.shuffle()
                            }
                            JIconButton {
                                text: screen.favorite ? "♥" : "♡"
                                fg: screen.favorite ? Theme.accent : Theme.textPrimary
                                onClicked: { screen.favorite = !screen.favorite; screen.client.setFavorite(screen.detail.id, screen.favorite) }
                            }
                            JIconButton {
                                text: "✓"
                                fg: screen.played ? Theme.watched : Theme.textPrimary
                                onClicked: { screen.played = !screen.played; screen.client.setWatched(screen.detail.id, screen.played) }
                            }
                            JIconButton {
                                id: moreBtn
                                text: "⋯"
                                onClicked: moreMenu.popup()
                                DarkMenu {
                                    id: moreMenu
                                    DarkMenuItem { text: qsTr("Add to playlist"); enabled: Features.playlists; onTriggered: screen.itemAddToPlaylist(screen.detail) }
                                    DarkMenuItem { text: qsTr("Add to collection"); enabled: Features.collections; onTriggered: screen.itemAddToCollection(screen.detail) }
                                    DarkMenuItem { text: qsTr("Copy stream URL"); visible: screen.isPlayableLeaf; onTriggered: screen.client.copyStreamUrl(screen.detail.id) }
                                    DarkMenuItem { text: qsTr("Download"); enabled: Features.downloads }
                                    DarkMenuItem { text: qsTr("Edit metadata"); enabled: Features.metadataEdit }
                                    DarkMenuItem {
                                        text: qsTr("Refresh metadata")
                                        onTriggered: screen.confirm(qsTr("Refresh metadata for \"%1\"?").arg(screen.detail.name || ""),
                                                                    function() { screen.client.refreshItem(screen.detail.id) })
                                    }
                                    DarkMenuItem {
                                        text: qsTr("Delete")
                                        visible: screen.detail && screen.detail.canDelete === true
                                        onTriggered: screen.confirm(qsTr("Delete \"%1\" from the server? This cannot be undone.").arg(screen.detail.name || ""),
                                                                    function() { screen.client.deleteItem(screen.detail.id); screen.deleted() })
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // --- tagline + overview ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pagePad
                Layout.rightMargin: Theme.pagePad
                spacing: Theme.spacingSmall
                Text {
                    text: (screen.detail && screen.detail.tagline) ? screen.detail.tagline : ""
                    visible: text.length > 0
                    color: Theme.textSecondary; font.pixelSize: Theme.fontMedium; font.italic: true
                    wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Text {
                    id: overviewText
                    text: (screen.detail && screen.detail.overview) ? screen.detail.overview : ""
                    visible: text.length > 0
                    color: Theme.textPrimary; font.pixelSize: Theme.fontNormal
                    wrapMode: Text.Wrap; Layout.fillWidth: true; lineHeight: 1.25
                    maximumLineCount: screen.overviewExpanded ? 10000 : 4
                    elide: Text.ElideRight
                }
                Text { // Show more / Show less (only when the overview overflows)
                    visible: overviewText.visible && (overviewText.truncated || screen.overviewExpanded)
                    text: screen.overviewExpanded ? qsTr("Show less") : qsTr("Show more")
                    color: showMoreHover.hovered ? Theme.accentHover : Theme.accent
                    font.pixelSize: Theme.fontSmall
                    HoverHandler { id: showMoreHover }
                    TapHandler { onTapped: screen.overviewExpanded = !screen.overviewExpanded }
                }
                // tags
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingSmall
                    spacing: Theme.spacingSmall
                    visible: screen.detail && screen.detail.tags && screen.detail.tags.length > 0
                    Repeater {
                        model: screen.detail ? (screen.detail.tags || []) : []
                        Rectangle {
                            required property var modelData
                            implicitWidth: tgt.implicitWidth + 16; implicitHeight: 26; radius: 13
                            color: Theme.surface; border.color: Theme.divider; border.width: 1
                            Text { id: tgt; anchors.centerIn: parent; text: modelData
                                   color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
                        }
                    }
                }
            }

            // --- collection (BoxSet) members, grouped by type ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingLarge
                visible: screen.isBoxSet && screen.collectionItems.length > 0
                Repeater {
                    model: screen.collectionGroups
                    MediaRow {
                        required property var modelData
                        title: modelData.title
                        model: modelData.items
                        client: screen.client
                        shape: "poster"
                        onItemActivated: (it) => screen.play(it)
                        onItemOpenDetail: (it) => screen.openDetail(it)
                        onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                        onItemAddToCollection: (it) => screen.itemAddToCollection(it)
                    }
                }
            }

            // --- standalone season: episode list (no season selector) ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pagePad
                Layout.rightMargin: Theme.pagePad
                spacing: Theme.spacingSmall
                visible: screen.isSeason && screen.episodes.length > 0
                Text {
                    text: qsTr("Episodes")
                    color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true
                }
                Repeater {
                    model: screen.episodes
                    EpisodeRow {}
                }
            }

            // --- version / audio / subtitle selectors (leaf items, like web) ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pagePad
                Layout.rightMargin: Theme.pagePad
                spacing: Theme.spacingSmall
                visible: screen.isPlayableLeaf && screen.selectedSource
                TrackSelect {
                    label: qsTr("Version")
                    visible: (screen.detail && screen.detail.mediaSources ? screen.detail.mediaSources.length : 0) > 1
                    options: (screen.detail && screen.detail.mediaSources ? screen.detail.mediaSources : [])
                             .map((s, i) => ({ text: s.name || (qsTr("Version") + " " + (i + 1)), value: i }))
                    current: screen.selectedSourceIndex
                    onPicked: (v) => screen.selectSource(v)
                }
                TrackSelect {
                    label: qsTr("Audio")
                    visible: screen.audioOptions().length > 0
                    options: screen.audioOptions()
                    current: screen.selectedAudioIndex
                    onPicked: (v) => screen.selectedAudioIndex = v
                }
                TrackSelect {
                    label: qsTr("Subtitles")
                    visible: screen.subtitleOptions().length > 0
                    options: screen.subtitleOptions()
                    current: screen.selectedSubtitleIndex
                    onPicked: (v) => screen.selectedSubtitleIndex = v
                }
            }

            // --- external links + media info ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pagePad
                Layout.rightMargin: Theme.pagePad
                spacing: Theme.spacingSmall
                visible: screen.hasMediaInfo || screen.hasLinks

                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall
                    visible: screen.hasLinks
                    Repeater {
                        model: screen.detail ? (screen.detail.externalUrls || []) : []
                        Rectangle {
                            required property var modelData
                            implicitWidth: lt.implicitWidth + 20; implicitHeight: 30; radius: Theme.radius
                            color: lh.hovered ? Theme.surfaceHover : Theme.surface
                            border.color: Theme.divider; border.width: 1
                            Text { id: lt; anchors.centerIn: parent; text: modelData.name; color: Theme.accent; font.pixelSize: Theme.fontSmall }
                            HoverHandler { id: lh }
                            TapHandler { onTapped: Qt.openUrlExternally(modelData.url) }
                        }
                    }
                }

                Text { visible: screen.hasMediaInfo; text: qsTr("Media Info"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                Repeater {
                    model: screen.hasMediaInfo ? [
                        { k: qsTr("Video"), v: screen.videoLine() },
                        { k: qsTr("Audio"), v: screen.audioText() },
                        { k: qsTr("Subtitles"), v: screen.subText() },
                        { k: qsTr("Container"), v: ((screen.detail.container || "") + "").toUpperCase() },
                        { k: qsTr("Size"), v: screen.fmtSize(screen.detail.sizeBytes) }
                    ].filter(r => r.v && r.v.length > 0) : []
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Text { text: modelData.k; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: 110 }
                        Text { text: modelData.v; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    }
                }
            }

            // --- chapters / scenes ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pagePad
                Layout.rightMargin: Theme.pagePad
                spacing: Theme.spacingSmall
                visible: screen.hasChapterImages
                Text { text: qsTr("Scenes"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.spacing
                    Repeater {
                        model: screen.detail ? (screen.detail.chapters || []) : []
                        ColumnLayout {
                            required property var modelData
                            spacing: 2
                            Rectangle {
                                width: 160; height: 90; radius: Theme.radius; color: Theme.surface; clip: true
                                Image {
                                    anchors.fill: parent; fillMode: Image.PreserveAspectCrop
                                    asynchronous: true; cache: true
                                    source: (screen.client && modelData.imageTag)
                                            ? screen.client.imageUrl(screen.detail.id, "Chapter", 180, modelData.imageTag, modelData.index) : ""
                                }
                                HoverHandler { id: chHover }
                                Rectangle {
                                    anchors.fill: parent; color: Theme.overlayStrong
                                    opacity: chHover.hovered ? 0.35 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                                }
                                TapHandler {
                                    onTapped: { var it = screen._withSelections(screen.detail); it.playbackTicks = modelData.startTicks; screen.play(it) }
                                }
                            }
                            Text { text: modelData.name; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                                   elide: Text.ElideRight; Layout.preferredWidth: 160 }
                            Text { text: screen.fmtChapterTime(modelData.startTicks); color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
                        }
                    }
                }
            }

            // --- series: Next Up ---
            MediaRow {
                title: qsTr("Next Up")
                model: screen.seriesNextUp
                client: screen.client
                shape: "thumb"
                onItemActivated: (it) => screen.play(it)
                onItemOpenDetail: (it) => screen.openDetail(it)
                onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                onItemAddToCollection: (it) => screen.itemAddToCollection(it)
            }

            // --- series: season selector + episodes ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pagePad
                Layout.rightMargin: Theme.pagePad
                spacing: Theme.spacingSmall
                visible: screen.isSeries && screen.seasons.length > 0

                Button {
                    id: seasonBtn
                    text: screen.selectedSeasonName + "  ▾"
                    hoverEnabled: true
                    leftPadding: 14; rightPadding: 14; implicitHeight: Theme.controlHeight
                    background: Rectangle { radius: Theme.radius; color: seasonBtn.hovered ? Theme.surfaceHover : Theme.surface; border.color: Theme.divider; border.width: 1 }
                    contentItem: Text { text: seasonBtn.text; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; verticalAlignment: Text.AlignVCenter }
                    onClicked: seasonMenu.popup()
                    DarkMenu {
                        id: seasonMenu
                        Instantiator {
                            model: screen.seasons
                            delegate: DarkMenuItem {
                                required property var modelData
                                text: modelData.name
                                onTriggered: screen.selectSeason(modelData)
                            }
                            onObjectAdded: (index, object) => seasonMenu.insertItem(index, object)
                            onObjectRemoved: (index, object) => seasonMenu.removeItem(object)
                        }
                    }
                }
                Repeater {
                    model: screen.episodes
                    EpisodeRow {}
                }
            }

            // --- cast ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall
                visible: screen.cast.length > 0
                Text { text: qsTr("Cast & Crew"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.leftMargin: Theme.pagePad }
                Item {
                    id: castArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    readonly property real minX: castList.originX
                    readonly property real maxX: castList.originX + Math.max(0, castList.contentWidth - castList.width)
                    ListView {
                        id: castList
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        interactive: false // vertical wheel scrolls the page; arrows scroll the cast
                        spacing: Theme.spacing
                        clip: true
                        leftMargin: Theme.pagePad; rightMargin: Theme.pagePad
                        boundsBehavior: Flickable.StopAtBounds
                        model: screen.cast
                        Behavior on contentX { NumberAnimation { duration: Theme.animMedium; easing.type: Easing.OutCubic } }
                        delegate: PersonTile {}
                    }
                    HoverHandler { id: castHover }
                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingTiny }
                        width: 32; height: 72; radius: Theme.radius; color: Theme.overlayStrong
                        visible: castHover.hovered && castList.contentX > castArea.minX + 1
                        Text { anchors.centerIn: parent; text: "‹"; color: Theme.textPrimary; font.pixelSize: 26 }
                        TapHandler { onTapped: castList.contentX = Math.max(castArea.minX, castList.contentX - castList.width * 0.8) }
                    }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Theme.spacingTiny }
                        width: 32; height: 72; radius: Theme.radius; color: Theme.overlayStrong
                        visible: castHover.hovered && castList.contentX < castArea.maxX - 1
                        Text { anchors.centerIn: parent; text: "›"; color: Theme.textPrimary; font.pixelSize: 26 }
                        TapHandler { onTapped: castList.contentX = Math.min(castArea.maxX, castList.contentX + castList.width * 0.8) }
                    }
                }
            }

            // --- extras / special features ---
            MediaRow {
                title: qsTr("Extras")
                model: screen.extras
                client: screen.client
                shape: "thumb"
                onItemActivated: (it) => screen.play(it)
                onItemOpenDetail: (it) => screen.play(it)
                onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                onItemAddToCollection: (it) => screen.itemAddToCollection(it)
            }

            // --- filmography (person pages) ---
            MediaRow {
                title: qsTr("Filmography")
                model: screen.filmography
                client: screen.client
                shape: "poster"
                onItemActivated: (it) => screen.play(it)
                onItemOpenDetail: (it) => screen.openDetail(it)
                onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                onItemAddToCollection: (it) => screen.itemAddToCollection(it)
            }

            // --- more from this season (episode pages) ---
            MediaRow {
                title: (screen.detail && screen.detail.parentIndexNumber !== undefined)
                       ? qsTr("More From Season %1").arg(screen.detail.parentIndexNumber)
                       : qsTr("More From This Series")
                model: screen.moreFrom
                client: screen.client
                shape: "thumb"
                onItemActivated: (it) => screen.play(it)
                onItemOpenDetail: (it) => screen.openDetail(it)
                onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                onItemAddToCollection: (it) => screen.itemAddToCollection(it)
            }

            // --- more like this ---
            MediaRow {
                title: qsTr("More Like This")
                model: screen.similar
                client: screen.client
                shape: "poster"
                onItemActivated: (it) => screen.play(it)
                onItemOpenDetail: (it) => screen.openDetail(it)
                onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                onItemAddToCollection: (it) => screen.itemAddToCollection(it)
            }

            Item { Layout.preferredHeight: Theme.spacingLarge }
        }
    }
}
