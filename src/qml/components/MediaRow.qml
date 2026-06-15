import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// A titled, horizontally-scrolling row of MediaCards (a jellyfin-web home
// section). Hides itself when empty so screens can declare every section
// unconditionally.
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

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: (row.shape === "thumb" ? Theme.cardThumbHeight : Theme.cardPosterHeight) + 50
        orientation: ListView.Horizontal
        spacing: Theme.spacing
        clip: true
        leftMargin: Theme.pagePad
        rightMargin: Theme.pagePad
        boundsBehavior: Flickable.StopAtBounds
        model: row.model
        cacheBuffer: 600

        delegate: MediaCard {
            required property var modelData
            item: modelData
            client: row.client
            shape: row.shape
            onActivated: (it) => row.itemActivated(it)
            onOpenDetail: (it) => row.itemOpenDetail(it)
        }

        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
    }
}
