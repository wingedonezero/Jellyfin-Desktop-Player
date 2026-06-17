import QtQuick
import QtQuick.Layouts
import JellyfinDesktop

// A full-width library row for the wide view modes:
//   "list"   — small poster + title / metadata / overview beside it
//   "banner" — a wide thumb/backdrop image with a title overlay
// Mirrors MediaCard's behavior (body opens detail, the ▶ plays, right-click =
// the shared ItemContextMenu) for jellyfin-web's list/banner library layouts.
Item {
    id: row
    required property var item
    property var client
    property string shape: "list"   // list | banner

    implicitHeight: shape === "banner" ? Math.round(width / 5.4) : 84

    signal activated(var item)
    signal openDetail(var item)
    signal addToPlaylist(var item)
    signal addToCollection(var item)
    signal cardAction(string verb, var item)

    readonly property bool isEpisode: item && item.type === "Episode"
    readonly property bool playable: item && (item.type === "Movie" || item.type === "Episode"
                                              || item.type === "Video" || item.type === "MusicVideo"
                                              || item.type === "Trailer" || item.type === "Audio")
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

    function posterSrc() { return (item && client && item.imageTag) ? client.imageUrl(item.id, "Primary", 160, item.imageTag) : "" }
    function wideSrc() {
        if (!item || !client) return ""
        if (item.imageTagThumb) return client.imageUrl(item.id, "Thumb", 360, item.imageTagThumb)
        if (item.hasBackdrop)   return client.imageUrl(item.id, "Backdrop", 360, "")
        if (item.imageTag)      return client.imageUrl(item.id, "Primary", 360, item.imageTag)
        return ""
    }
    function titleText() {
        if (!item) return ""
        if (isEpisode) {
            var se = ""
            if (item.parentIndexNumber !== undefined && item.parentIndexNumber !== "") se += "S" + item.parentIndexNumber
            if (item.indexNumber !== undefined && item.indexNumber !== "") se += (se ? "E" : "E") + item.indexNumber
            return (item.seriesName ? item.seriesName + " · " : "") + (se ? se + " " : "") + (item.name || "")
        }
        return item.name || ""
    }
    function subText() {
        if (!item) return ""
        var parts = []
        if (item.productionYear && item.productionYear > 0) parts.push("" + item.productionYear)
        if (item.communityRating && item.communityRating > 0) parts.push("★ " + (Math.round(item.communityRating * 10) / 10))
        var ticks = item.runTimeTicks || 0
        if (ticks > 0) {
            var mins = Math.round(ticks / 600000000)
            parts.push(mins >= 60 ? (Math.floor(mins / 60) + "h " + (mins % 60) + "m") : (mins + "m"))
        }
        return parts.join("  ·  ")
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: hover.hovered ? Theme.surfaceHover : "transparent"
    }
    HoverHandler { id: hover }

    // ---- list layout ----
    RowLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: Theme.spacing
        visible: row.shape === "list"
        Rectangle {
            Layout.preferredWidth: 48; Layout.preferredHeight: 72
            radius: Theme.radius; color: Theme.surface; clip: true
            Image {
                anchors.fill: parent; fillMode: Image.PreserveAspectCrop
                asynchronous: true; cache: true
                source: row.shape === "list" ? row.posterSrc() : ""
                visible: status === Image.Ready
            }
            Rectangle { anchors.fill: parent; color: Theme.overlay; visible: hover.hovered && row.playable }
            Text { anchors.centerIn: parent; text: "▶"; color: Theme.textPrimary; font.pixelSize: 16; visible: hover.hovered && row.playable }
            Rectangle {
                visible: row.item && row.item.played === true
                anchors { top: parent.top; right: parent.right; margins: 3 }
                width: 16; height: 16; radius: 8; color: Theme.watched
                Text { anchors.centerIn: parent; text: "✓"; color: Theme.accentText; font.pixelSize: 10; font.bold: true }
            }
            TapHandler { enabled: row.playable; onTapped: row.activated(row.item) }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            Text {
                text: row.titleText(); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true
                elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true
            }
            Text {
                text: row.subText(); visible: text.length > 0
                color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; Layout.fillWidth: true; elide: Text.ElideRight
            }
            Text {
                text: (row.item && row.item.overview) ? row.item.overview : ""; visible: text.length > 0
                color: Theme.textSecondary; font.pixelSize: Theme.fontSmall
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; Layout.fillWidth: true
            }
        }
    }

    // ---- banner layout ----
    Item {
        anchors.fill: parent
        anchors.margins: 4
        visible: row.shape === "banner"
        Rectangle {
            anchors.fill: parent; radius: Theme.radius; color: Theme.surface; clip: true
            Image {
                id: bimg
                anchors.fill: parent; fillMode: Image.PreserveAspectCrop
                asynchronous: true; cache: true
                source: row.shape === "banner" ? row.wideSrc() : ""
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent; visible: bimg.status !== Image.Ready
                text: row.titleText(); color: Theme.textSecondary; font.pixelSize: Theme.fontMedium
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 40
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.transparent }
                    GradientStop { position: 1.0; color: Theme.overlayStrong }
                }
            }
            Text {
                anchors { left: parent.left; bottom: parent.bottom; leftMargin: 10; bottomMargin: 8; right: parent.right; rightMargin: 10 }
                text: row.titleText(); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true
                elide: Text.ElideRight; maximumLineCount: 1
            }
            Rectangle {
                anchors.centerIn: parent; visible: hover.hovered && row.playable
                width: 46; height: 46; radius: 23; color: Theme.overlayStrong
                border.color: Theme.textPrimary; border.width: 1
                Text { anchors.centerIn: parent; text: "▶"; color: Theme.textPrimary; font.pixelSize: 20 }
                TapHandler { onTapped: row.activated(row.item) }
            }
        }
    }

    // resume progress (both modes)
    Rectangle {
        visible: row.progress > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 6; rightMargin: 6 }
        height: 3; color: Theme.overlayMedium; radius: 1.5
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * row.progress; color: Theme.accent; radius: 1.5
        }
    }

    // body → detail; right-click → shared menu
    TapHandler { onTapped: row.openDetail(row.item) }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: ctxMenu.popup() }
    ItemContextMenu {
        id: ctxMenu
        item: row.item; client: row.client
        playable: row.playable; canAddTo: row.canAddTo
        onPlay: (it) => row.activated(it)
        onQueue: (it) => row.cardAction("queue", it)
        onPlayNext: (it) => row.cardAction("playNext", it)
        onAddToCollection: (it) => row.addToCollection(it)
        onAddToPlaylist: (it) => row.addToPlaylist(it)
    }
}
