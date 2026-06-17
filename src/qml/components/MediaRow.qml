import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// A titled, horizontally-scrolling row of MediaCards (a jellyfin-web home
// section). The inner list is NOT flick-interactive so a vertical mouse wheel
// passes through to the page; horizontal navigation is via hover arrows. Hides
// itself when empty so screens can declare every section unconditionally.
ColumnLayout {
    id: row
    property string title: ""
    property var model: []
    property var client
    property string shape: "poster"
    property bool episodeImages: true   // forwarded to cards (Next Up/Resume pref)
    property bool titleLink: false      // clickable header (→ titleClicked) with a › chevron

    signal itemActivated(var item)   // play
    signal itemOpenDetail(var item)  // open detail
    signal itemAddToPlaylist(var item)
    signal itemAddToCollection(var item)
    signal cardAction(string verb, var item)  // queue/playNext
    signal titleClicked()            // "see all" header click (when titleLink)

    Layout.fillWidth: true
    visible: model && model.length > 0
    spacing: Theme.spacingSmall

    RowLayout {
        Layout.leftMargin: Theme.pagePad
        spacing: 4
        Text {
            text: row.title
            color: (row.titleLink && hdrHover.hovered) ? Theme.accent : Theme.textPrimary
            font.pixelSize: Theme.fontMedium
            font.bold: true
        }
        Text {
            visible: row.titleLink
            text: "›"
            color: (row.titleLink && hdrHover.hovered) ? Theme.accent : Theme.textSecondary
            font.pixelSize: Theme.fontMedium
        }
        HoverHandler { id: hdrHover; enabled: row.titleLink }
        TapHandler { enabled: row.titleLink; onTapped: row.titleClicked() }
    }

    Item {
        id: rowArea
        Layout.fillWidth: true
        readonly property real artHeight: row.shape === "thumb" ? Theme.cardThumbHeight : Theme.cardPosterHeight
        Layout.preferredHeight: artHeight + 50

        ListView {
            id: list
            anchors.fill: parent
            orientation: ListView.Horizontal
            interactive: false // vertical wheel goes to the page; scroll via the edge gutters
            spacing: Theme.spacing
            clip: true
            leftMargin: Theme.pagePad
            rightMargin: Theme.pagePad
            boundsBehavior: Flickable.StopAtBounds
            model: row.model
            cacheBuffer: 600
            Behavior on contentX { NumberAnimation { duration: Theme.animMedium; easing.type: Easing.OutCubic } }

            delegate: MediaCard {
                required property var modelData
                item: modelData
                client: row.client
                shape: row.shape
                episodeImages: row.episodeImages
                onActivated: (it) => row.itemActivated(it)
                onOpenDetail: (it) => row.itemOpenDetail(it)
                onAddToPlaylist: (it) => row.itemAddToPlaylist(it)
                onAddToCollection: (it) => row.itemAddToCollection(it)
                onCardAction: (verb, it) => row.cardAction(verb, it)
            }
        }

        HoverHandler { id: rowHover }

        // --- horizontal scroll gutters (jellyfin-web edge chevrons) ----------
        // Full-height, fully-clickable edge strips. They appear on hover ONLY
        // when the row actually overflows (atXBeginning/atXEnd is authoritative,
        // so they never show — nor steal a click — when everything already
        // fits), and sit above the cards: the strip's MouseArea consumes the
        // click, so it can't fall through and open the card beneath it.
        component ScrollGutter: Rectangle {
            property bool toRight: true
            width: 56
            height: rowArea.artHeight
            anchors.top: parent.top
            z: 5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: toRight ? Theme.transparent : Theme.overlayStrong }
                GradientStop { position: 1.0; color: toRight ? Theme.overlayStrong : Theme.transparent }
            }
            // circular chevron badge (matches the card play button)
            Rectangle {
                anchors.centerIn: parent
                width: 40; height: 40; radius: 20
                color: Theme.overlayStrong
                border.color: Theme.textPrimary
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: toRight ? "›" : "‹"   // › ‹
                    color: Theme.textPrimary
                    font.pixelSize: 24
                }
            }
            // the WHOLE strip is the target; consume the click so it never
            // reaches the card behind it
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const page = list.width * 0.8
                    const maxX = Math.max(0, list.contentWidth - list.width)
                    list.contentX = toRight ? Math.min(list.contentX + page, maxX)
                                            : Math.max(0, list.contentX - page)
                }
            }
        }

        ScrollGutter {
            toRight: false
            anchors.left: parent.left
            visible: rowHover.hovered && !list.atXBeginning
        }
        ScrollGutter {
            toRight: true
            anchors.right: parent.right
            visible: rowHover.hovered && !list.atXEnd
        }
    }
}
