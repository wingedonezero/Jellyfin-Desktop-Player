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

    signal itemActivated(var item)   // play
    signal itemOpenDetail(var item)  // open detail

    Layout.fillWidth: true
    visible: model && model.length > 0
    spacing: Theme.spacingSmall

    Text {
        text: row.title
        color: Theme.textPrimary
        font.pixelSize: Theme.fontMedium
        font.bold: true
        Layout.leftMargin: Theme.pagePad
    }

    Item {
        id: rowArea
        Layout.fillWidth: true
        Layout.preferredHeight: (row.shape === "thumb" ? Theme.cardThumbHeight : Theme.cardPosterHeight) + 50
        readonly property real minX: list.originX
        readonly property real maxX: list.originX + Math.max(0, list.contentWidth - list.width)

        ListView {
            id: list
            anchors.fill: parent
            orientation: ListView.Horizontal
            interactive: false // vertical wheel goes to the page; scroll via arrows
            spacing: Theme.spacing
            clip: true
            leftMargin: Theme.pagePad
            rightMargin: Theme.pagePad
            boundsBehavior: Flickable.StopAtBounds
            model: row.model
            cacheBuffer: 600
            Behavior on contentX { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            delegate: MediaCard {
                required property var modelData
                item: modelData
                client: row.client
                shape: row.shape
                onActivated: (it) => row.itemActivated(it)
                onOpenDetail: (it) => row.itemOpenDetail(it)
            }
        }

        HoverHandler { id: rowHover }

        Rectangle { // scroll left
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingTiny }
            width: 32; height: 72; radius: Theme.radius
            color: Theme.overlayStrong
            visible: rowHover.hovered && list.contentX > rowArea.minX + 1
            Text { anchors.centerIn: parent; text: "‹"; color: Theme.textPrimary; font.pixelSize: 26 }
            TapHandler { onTapped: list.contentX = Math.max(rowArea.minX, list.contentX - list.width * 0.8) }
        }
        Rectangle { // scroll right
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Theme.spacingTiny }
            width: 32; height: 72; radius: Theme.radius
            color: Theme.overlayStrong
            visible: rowHover.hovered && list.contentX < rowArea.maxX - 1
            Text { anchors.centerIn: parent; text: "›"; color: Theme.textPrimary; font.pixelSize: 26 }
            TapHandler { onTapped: list.contentX = Math.min(rowArea.maxX, list.contentX + list.width * 0.8) }
        }
    }
}
