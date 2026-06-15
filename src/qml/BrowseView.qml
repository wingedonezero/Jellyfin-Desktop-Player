import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    required property var client
    signal playRequested(string itemId)

    // Breadcrumb of folders we've descended into: [{ id, title }, ...]
    property var path: []
    readonly property string title: path.length > 0 ? path[path.length - 1].title
                                                     : qsTr("Libraries")

    Component.onCompleted: client.fetchUserViews("browse")

    Connections {
        target: root.client
        function onItemsReady(tag, items) {
            if (tag === "browse")
                grid.model = items
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Button {
                text: qsTr("◀")
                visible: root.path.length > 0
                onClicked: root.goBack()
            }
            Label {
                text: root.title
                color: "white"
                font.pixelSize: 22
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Label { text: root.client.userName; color: "#aaaaaa" }
            Button { text: qsTr("Log out"); onClicked: root.client.logout() }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            cellWidth: 180
            cellHeight: 280
            clip: true

            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#22ffffff"
                        radius: 6
                        clip: true
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            source: cell.modelData.imageTag
                                    ? root.client.imageUrl(cell.modelData.id, "Primary", 400)
                                    : ""
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: cell.modelData.name
                        color: "white"
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.open(cell.modelData)
                }
            }
        }
    }

    function open(item) {
        if (item.isFolder) {
            root.path = root.path.concat([{ id: item.id, title: item.name }])
            client.fetchItems(item.id, "browse")
        } else {
            root.playRequested(item.id)
        }
    }

    function goBack() {
        root.path = root.path.slice(0, -1)
        if (root.path.length === 0)
            client.fetchUserViews("browse")
        else
            client.fetchItems(root.path[root.path.length - 1].id, "browse")
    }
}
