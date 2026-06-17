import QtQuick
import QtQuick.Layouts
import JellyfinDesktop

// A single media tile (jellyfin-web card): artwork with hover-zoom + play
// overlay, resume-progress bar, watched / unplayed badges, and title/subtitle.
// Theme-pure and shape-agnostic ("poster" 2:3 or "thumb" 16:9). Reused by
// MediaRow and the library grid.
Item {
    id: card
    required property var item        // QVariantMap from JellyfinClient
    property var client
    property string shape: "poster"   // "poster" | "thumb"
    property bool episodeImages: true // Next Up/Resume: episode still vs show image

    signal activated(var item)        // play
    signal openDetail(var item)       // open detail page
    signal addToPlaylist(var item)    // → app-level picker (Main)
    signal addToCollection(var item)  // → app-level picker (Main)

    readonly property int artHeight: shape === "thumb" ? Theme.cardThumbHeight : Theme.cardPosterHeight
    implicitWidth: shape === "thumb" ? Theme.cardThumbWidth : Theme.cardPosterWidth
    implicitHeight: artHeight + labels.implicitHeight + Theme.spacingSmall

    readonly property bool isEpisode: item && item.type === "Episode"
    // only these play directly; everything else (Series/Season/BoxSet/Genre/…) opens detail
    readonly property bool playable: item && (item.type === "Movie" || item.type === "Episode"
                                              || item.type === "Video" || item.type === "MusicVideo"
                                              || item.type === "Trailer" || item.type === "Audio")
    // real library items can be added to a collection/playlist (not views/genres/people)
    readonly property bool canAddTo: item && (item.type === "Movie" || item.type === "Series"
                                              || item.type === "Episode" || item.type === "Video"
                                              || item.type === "MusicVideo" || item.type === "Audio"
                                              || item.type === "MusicAlbum" || item.type === "BoxSet")
    readonly property real progress: {
        if (!item) return 0
        const t = item.playbackTicks || 0
        const total = item.runTimeTicks || 0
        return total > 0 ? Math.min(1, t / total) : 0
    }

    function imageSource() {
        if (!item || !client) return ""
        if (shape === "thumb") {
            // Settings → Display "Use episode images in Next Up & Resume": when off,
            // show the parent show's poster instead of the per-episode still.
            if (isEpisode && !episodeImages && item.seriesId)
                return client.imageUrl(item.seriesId, "Primary", artHeight * 2, "")
            if (item.imageTagThumb) return client.imageUrl(item.id, "Thumb", artHeight * 2, item.imageTagThumb)
            if (item.hasBackdrop)   return client.imageUrl(item.id, "Backdrop", artHeight * 2, "")
        }
        if (item.imageTag) return client.imageUrl(item.id, "Primary", artHeight * 2, item.imageTag)
        return ""
    }
    function primaryTitle() {
        if (!item) return ""
        return isEpisode ? (item.seriesName || item.name) : item.name
    }
    function secondaryText() {
        if (!item) return ""
        if (isEpisode) {
            const s = item.parentIndexNumber
            const e = item.indexNumber
            let se = ""
            if (s !== undefined && s !== "") se += "S" + s
            if (e !== undefined && e !== "") se += (se ? " " : "") + "E" + e
            return se || (item.name || "")
        }
        return (item.productionYear && item.productionYear > 0) ? ("" + item.productionYear) : ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingSmall

        // --- artwork ---
        Rectangle {
            id: art
            Layout.fillWidth: true
            Layout.preferredHeight: card.artHeight
            radius: Theme.radius
            color: Theme.surface
            clip: true
            border.color: hover.hovered ? Theme.accent : Theme.transparent
            border.width: hover.hovered ? 2 : 0

            Image {
                id: img
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                source: card.imageSource()
                visible: status === Image.Ready
                scale: hover.hovered ? 1.06 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.animFast } }
            }
            // fallback when no/loading artwork
            Text {
                anchors.centerIn: parent
                width: parent.width - Theme.spacing * 2
                visible: img.status !== Image.Ready
                text: card.primaryTitle()
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSmall
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            // hover dim (visual only — taps fall through to the card's openDetail)
            Rectangle {
                anchors.fill: parent
                color: Theme.overlay
                visible: hover.hovered
            }
            // play button — only for directly-playable items; opens detail otherwise
            Rectangle {
                anchors.centerIn: parent
                visible: hover.hovered && card.playable
                width: 46; height: 46; radius: 23
                color: Theme.overlayStrong
                border.color: Theme.textPrimary
                border.width: 1
                Text { anchors.centerIn: parent; text: "▶"; color: Theme.textPrimary; font.pixelSize: 20 }
                TapHandler { onTapped: card.activated(card.item) }
            }

            // watched check / unplayed count
            Rectangle {
                visible: card.item && (card.item.played === true || (card.item.unplayedItemCount || 0) > 0)
                anchors { top: parent.top; right: parent.right; margins: 6 }
                width: Math.max(20, badge.implicitWidth + 8)
                height: 20
                radius: 10
                color: Theme.watched
                Text {
                    id: badge
                    anchors.centerIn: parent
                    text: (card.item && card.item.played === true) ? "✓"
                          : ("" + (card.item ? (card.item.unplayedItemCount || "") : ""))
                    color: Theme.accentText
                    font.pixelSize: Theme.fontSmall
                    font.bold: true
                }
            }

            // resume progress
            Rectangle {
                visible: card.progress > 0
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 4
                color: Theme.overlayMedium
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * card.progress
                    color: Theme.accent
                }
            }

            HoverHandler { id: hover }
        }

        // --- labels ---
        ColumnLayout {
            id: labels
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: card.primaryTitle()
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSmall
                elide: Text.ElideRight
                maximumLineCount: 1
                Layout.fillWidth: true
            }
            Text {
                text: card.secondaryText()
                visible: text.length > 0
                color: Theme.textSecondary
                font.pixelSize: Theme.fontTiny
                elide: Text.ElideRight
                maximumLineCount: 1
                Layout.fillWidth: true
            }
        }
    }

    // click anywhere on the card (except the play button) → open detail
    TapHandler { onTapped: card.openDetail(card.item) }

    // right-click → context menu (jellyfin-web item menu)
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: ctxMenu.popup() }
    DarkMenu {
        id: ctxMenu
        DarkMenuItem { text: qsTr("Play"); visible: card.playable; onTriggered: card.activated(card.item) }
        DarkMenuItem {
            text: qsTr("Play from beginning")
            visible: card.playable && card.item && (card.item.playbackTicks > 0)
            onTriggered: { var it = Object.assign({}, card.item); it.playbackTicks = 0; card.activated(it) }
        }
        DarkMenuItem {
            text: (card.item && card.item.isFavorite) ? qsTr("Remove from favorites") : qsTr("Add to favorites")
            onTriggered: if (card.client) card.client.setFavorite(card.item.id, !(card.item.isFavorite === true))
        }
        DarkMenuItem {
            text: (card.item && card.item.played) ? qsTr("Mark as unplayed") : qsTr("Mark as played")
            onTriggered: if (card.client) card.client.setWatched(card.item.id, !(card.item.played === true))
        }
        DarkMenuItem { text: qsTr("Add to collection"); visible: card.canAddTo; enabled: Features.collections; onTriggered: card.addToCollection(card.item) }
        DarkMenuItem { text: qsTr("Add to playlist"); visible: card.canAddTo; enabled: Features.playlists; onTriggered: card.addToPlaylist(card.item) }
        DarkMenuItem { text: qsTr("Download"); enabled: Features.downloads }
        DarkMenuItem { text: qsTr("Copy stream URL"); visible: card.playable; onTriggered: if (card.client) card.client.copyStreamUrl(card.item.id) }
        DarkMenuItem { text: qsTr("Delete media"); enabled: Features.deleteMedia }
        DarkMenuItem { text: qsTr("Edit metadata"); enabled: Features.metadataEdit }
        DarkMenuItem { text: qsTr("Edit images"); enabled: Features.metadataEdit }
        DarkMenuItem { text: qsTr("Edit subtitles"); enabled: Features.metadataEdit }
        DarkMenuItem { text: qsTr("Identify"); enabled: Features.metadataEdit }
        DarkMenuItem { text: qsTr("Refresh metadata"); enabled: Features.metadataEdit }
    }
}
