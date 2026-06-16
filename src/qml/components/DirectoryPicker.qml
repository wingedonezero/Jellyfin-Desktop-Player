import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// Server-side directory browser, backed by GET /Environment/Drives +
// /Environment/DirectoryContents (both read-only). Navigate into folders, go up
// (parent computed client-side — fine for the POSIX server), or type a path;
// "Select this folder" returns the current path. Reusable: set `client`, call
// openAt(startPath), handle onPicked. Used by the admin path fields + Libraries.
Popup {
    id: picker
    property var client
    property bool includeFiles: false
    property string path: ""            // current directory; "" => roots/drives
    property var entries: []
    signal picked(string chosenPath)

    function openAt(startPath) { path = ("" + (startPath || "")); load(); open() }
    function load() {
        if (!client) return
        if (path === "")
            client.getJson("/Environment/Drives", "dirpick:list")
        else
            client.getJson("/Environment/DirectoryContents?path=" + encodeURIComponent(path)
                           + "&includeDirectories=true&includeFiles=" + (includeFiles ? "true" : "false"),
                           "dirpick:list")
    }
    function enter(p) { path = p; load() }
    function goUp() {
        if (path === "") return
        if (path === "/") { enter(""); return }   // root → drives list
        var p = path
        if (p.length > 1 && p.charAt(p.length - 1) === "/") p = p.substring(0, p.length - 1)
        var i = p.lastIndexOf("/")
        enter(i <= 0 ? "/" : p.substring(0, i))
    }

    Connections {
        target: picker.client
        function onJsonReady(tag, data) {
            if (tag !== "dirpick:list") return
            picker.entries = (data && data.length !== undefined) ? data : ((data && data.Items) ? data.Items : [])
        }
    }

    modal: true
    dim: true
    width: 600
    height: 540
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    padding: Theme.spacing
    background: Rectangle { color: Theme.elevated; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }

    contentItem: ColumnLayout {
        spacing: Theme.spacingSmall
        Text { text: qsTr("Select a folder"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true }

        RowLayout {
            Layout.fillWidth: true; spacing: Theme.spacingSmall
            Rectangle {
                implicitWidth: 40; implicitHeight: 34; radius: Theme.radius
                color: upMa.containsMouse ? Theme.surfaceHover : Theme.surface
                border.color: Theme.divider; border.width: 1
                Text { anchors.centerIn: parent; text: "↑"; color: Theme.textPrimary; font.pixelSize: Theme.fontMedium }
                MouseArea { id: upMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: picker.goUp() }
            }
            TextField {
                Layout.fillWidth: true
                text: picker.path
                placeholderText: qsTr("(drives)")
                color: Theme.textPrimary; placeholderTextColor: Theme.textDisabled; font.pixelSize: Theme.fontSmall
                onAccepted: picker.enter(text)
                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 }
            }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true
            color: Theme.surface; radius: Theme.radius; border.color: Theme.divider; border.width: 1
            ListView {
                id: list
                anchors.fill: parent; anchors.margins: 1
                clip: true
                model: picker.entries
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    required property var modelData
                    width: list.width; implicitHeight: 36; hoverEnabled: true
                    onClicked: picker.enter(modelData.Path)
                    contentItem: RowLayout {
                        Text { text: ("" + (modelData.Name || modelData.Path)); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideRight; leftPadding: 8; verticalAlignment: Text.AlignVCenter }
                        Text { text: "›"; color: Theme.textSecondary; font.pixelSize: Theme.fontNormal; rightPadding: 10 }
                    }
                    background: Rectangle { color: hovered ? Theme.surfaceHover : "transparent" }
                }
            }
        }
        Text { visible: picker.entries.length === 0; text: qsTr("No subfolders here."); color: Theme.textSecondary; font.pixelSize: Theme.fontTiny }

        RowLayout {
            Layout.fillWidth: true; Layout.topMargin: Theme.spacingSmall; spacing: Theme.spacingSmall
            Item { Layout.fillWidth: true }
            Rectangle {
                implicitWidth: cancelT.implicitWidth + 28; implicitHeight: 34; radius: Theme.radius
                color: cancelMa.containsMouse ? Theme.surfaceHover : Theme.surface; border.color: Theme.divider; border.width: 1
                Text { id: cancelT; anchors.centerIn: parent; text: qsTr("Cancel"); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall }
                MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: picker.close() }
            }
            Rectangle {
                readonly property bool canPick: picker.path !== ""
                implicitWidth: selT.implicitWidth + 28; implicitHeight: 34; radius: Theme.radius
                opacity: canPick ? 1 : 0.4
                color: selMa.containsMouse && canPick ? Theme.accentHover : Theme.accent
                Text { id: selT; anchors.centerIn: parent; text: qsTr("Select this folder"); color: Theme.accentText; font.pixelSize: Theme.fontSmall; font.bold: true }
                MouseArea { id: selMa; anchors.fill: parent; enabled: parent.canPick; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { picker.picked(picker.path); picker.close() } }
            }
        }
    }
}
