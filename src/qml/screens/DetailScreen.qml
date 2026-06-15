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
    property string itemId: ""
    property var detail: ({})
    property string pageTitle: (detail && detail.name) ? detail.name : qsTr("Details")

    signal play(var item)
    signal playQueue(var items, int index)
    signal openDetail(var item)

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
    property var filmography: []

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
            if (episodes.length > 0) {
                let ep = episodes[0]
                for (let i = 0; i < episodes.length; ++i)
                    if (!episodes[i].played) { ep = episodes[i]; break }
                playEpisode(ep)
            }
        } else {
            screen.play(detail)
        }
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

    Connections {
        target: screen.client
        function onItemsReady(tag, items) {
            if (tag === "d:item:" + screen.itemId) {
                screen.detail = items.length > 0 ? items[0] : ({})
                screen.favorite = screen.detail.isFavorite === true
                screen.played = screen.detail.played === true
                screen.cast = screen.detail.people || []
                if (screen.isPerson) {
                    screen.client.fetchByPerson(screen.detail.id, "d:filmography:" + screen.itemId)
                } else {
                    screen.client.fetchSimilar(screen.itemId, "d:similar:" + screen.itemId)
                    if (screen.isSeries)
                        screen.client.fetchSeasons(screen.detail.id, "d:seasons:" + screen.itemId)
                }
            } else if (tag === "d:seasons:" + screen.itemId) {
                screen.seasons = items
                if (items.length > 0) screen.selectSeason(items[0])
            } else if (tag.indexOf("d:episodes:") === 0) {
                screen.episodes = items
            } else if (tag === "d:similar:" + screen.itemId) {
                screen.similar = items
            } else if (tag === "d:filmography:" + screen.itemId) {
                screen.filmography = items
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
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; cache: true
                source: pt.modelData.imageTag
                        ? screen.client.imageUrl(pt.modelData.id, "Primary", 160, pt.modelData.imageTag)
                        : ""
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: !pt.modelData.imageTag
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
                    source: (screen.detail && screen.detail.hasBackdrop)
                            ? screen.client.imageUrl(screen.detail.id, "Backdrop", 720, "")
                            : ""
                    visible: status === Image.Ready
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#33000000" }
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

                        Text {
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
                        }
                        Text {
                            text: (screen.detail && screen.detail.genres) ? screen.detail.genres.join(", ") : ""
                            visible: text.length > 0
                            color: Theme.textSecondary; font.pixelSize: Theme.fontSmall
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: Theme.spacingSmall
                            Layout.topMargin: Theme.spacingSmall
                            ActionButton {
                                primary: true
                                visible: !screen.isPerson
                                text: (screen.detail && screen.detail.playbackTicks > 0) ? qsTr("▶  Resume") : qsTr("▶  Play")
                                enabled: !screen.isSeries || screen.episodes.length > 0
                                onClicked: screen.playPrimary()
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
                                text: "⋯"
                                onClicked: moreMenu.popup()
                                DarkMenu {
                                    id: moreMenu
                                    DarkMenuItem { text: qsTr("Add to playlist"); enabled: Features.playlists }
                                    DarkMenuItem { text: qsTr("Add to collection"); enabled: Features.collections }
                                    DarkMenuItem { text: qsTr("Download"); enabled: Features.downloads }
                                    DarkMenuItem { text: qsTr("Edit metadata"); enabled: Features.metadataEdit }
                                    DarkMenuItem { text: qsTr("Refresh metadata"); enabled: Features.metadataEdit }
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
                    text: (screen.detail && screen.detail.overview) ? screen.detail.overview : ""
                    visible: text.length > 0
                    color: Theme.textPrimary; font.pixelSize: Theme.fontNormal
                    wrapMode: Text.Wrap; Layout.fillWidth: true; lineHeight: 1.25
                }
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
                        Behavior on contentX { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        delegate: PersonTile {}
                    }
                    HoverHandler { id: castHover }
                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingTiny }
                        width: 32; height: 72; radius: Theme.radius; color: "#cc000000"
                        visible: castHover.hovered && castList.contentX > castArea.minX + 1
                        Text { anchors.centerIn: parent; text: "‹"; color: Theme.textPrimary; font.pixelSize: 26 }
                        TapHandler { onTapped: castList.contentX = Math.max(castArea.minX, castList.contentX - castList.width * 0.8) }
                    }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Theme.spacingTiny }
                        width: 32; height: 72; radius: Theme.radius; color: "#cc000000"
                        visible: castHover.hovered && castList.contentX < castArea.maxX - 1
                        Text { anchors.centerIn: parent; text: "›"; color: Theme.textPrimary; font.pixelSize: 26 }
                        TapHandler { onTapped: castList.contentX = Math.min(castArea.maxX, castList.contentX + castList.width * 0.8) }
                    }
                }
            }

            // --- filmography (person pages) ---
            MediaRow {
                title: qsTr("Filmography")
                model: screen.filmography
                client: screen.client
                shape: "poster"
                onItemActivated: (it) => screen.play(it)
                onItemOpenDetail: (it) => screen.openDetail(it)
            }

            // --- more like this ---
            MediaRow {
                title: qsTr("More Like This")
                model: screen.similar
                client: screen.client
                shape: "poster"
                onItemActivated: (it) => screen.play(it)
                onItemOpenDetail: (it) => screen.openDetail(it)
            }

            Item { Layout.preferredHeight: Theme.spacingLarge }
        }
    }
}
