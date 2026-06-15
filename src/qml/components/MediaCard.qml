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

    signal activated(var item)        // play
    signal openDetail(var item)       // open detail page

    readonly property int artHeight: shape === "thumb" ? Theme.cardThumbHeight : Theme.cardPosterHeight
    implicitWidth: shape === "thumb" ? Theme.cardThumbWidth : Theme.cardPosterWidth
    implicitHeight: artHeight + labels.implicitHeight + Theme.spacingSmall

    readonly property bool isEpisode: item && item.type === "Episode"
    readonly property real progress: {
        if (!item) return 0
        const t = item.playbackTicks || 0
        const total = item.runTimeTicks || 0
        return total > 0 ? Math.min(1, t / total) : 0
    }

    function imageSource() {
        if (!item || !client) return ""
        if (shape === "thumb") {
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
                Behavior on scale { NumberAnimation { duration: 130 } }
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

            // hover overlay + play button
            Rectangle {
                anchors.fill: parent
                color: Theme.overlay
                visible: hover.hovered
                Text {
                    anchors.centerIn: parent
                    text: "▶"
                    color: Theme.textPrimary
                    font.pixelSize: 34
                }
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
                color: "#80000000"
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * card.progress
                    color: Theme.accent
                }
            }

            HoverHandler { id: hover }
            TapHandler { onTapped: card.openDetail(card.item) }
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
}
