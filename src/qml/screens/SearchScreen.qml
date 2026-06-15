import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// Search (jellyfin-web): a query field over a results grid. Debounced; results
// across Movies/Series/Episodes via the client.
Item {
    id: screen
    property var client
    property string pageTitle: qsTr("Search")

    signal itemActivated(var item)
    signal itemOpenDetail(var item)

    property var results: []

    Component.onCompleted: field.forceActiveFocus()
    function doSearch(q) {
        const query = q.trim()
        if (client && query.length > 0) client.search(query, "search:results")
        else screen.results = []
    }

    Connections {
        target: screen.client
        function onItemsReady(tag, its) { if (tag === "search:results") screen.results = its }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacing

        // search field
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pagePad
            Layout.rightMargin: Theme.pagePad
            Layout.topMargin: Theme.spacing
            implicitHeight: Theme.controlHeight
            radius: Theme.radius
            color: Theme.surface
            border.color: field.activeFocus ? Theme.accent : Theme.divider
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing
                anchors.rightMargin: Theme.spacingSmall
                spacing: Theme.spacingSmall
                Text { text: "\u{1F50D}"; color: Theme.textSecondary; font.pixelSize: Theme.fontNormal }
                TextField {
                    id: field
                    Layout.fillWidth: true
                    placeholderText: qsTr("Search movies, shows, episodes…")
                    color: Theme.textPrimary
                    placeholderTextColor: Theme.textDisabled
                    font.pixelSize: Theme.fontNormal
                    background: Item {}
                    onTextChanged: debounce.restart()
                    onAccepted: screen.doSearch(text)
                }
                JIconButton {
                    text: "✕"
                    visible: field.text.length > 0
                    implicitWidth: 32; implicitHeight: 32
                    onClicked: { field.clear(); screen.results = [] }
                }
            }
        }

        Timer { id: debounce; interval: 350; onTriggered: screen.doSearch(field.text) }

        Text {
            visible: field.text.length > 0 && screen.results.length === 0
            text: qsTr("No results")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontNormal
            Layout.leftMargin: Theme.pagePad
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            leftMargin: Theme.pagePad
            rightMargin: Theme.pagePad
            bottomMargin: Theme.spacingLarge
            cellWidth: Theme.cardPosterWidth + Theme.spacing
            cellHeight: Theme.cardPosterHeight + 50
            clip: true
            model: screen.results
            ScrollBar.vertical: ScrollBar {}

            delegate: Item {
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight
                MediaCard {
                    width: Theme.cardPosterWidth
                    item: modelData
                    client: screen.client
                    shape: "poster"
                    onActivated: (it) => screen.itemActivated(it)
                    onOpenDetail: (it) => screen.itemOpenDetail(it)
                }
            }
        }
    }
}
