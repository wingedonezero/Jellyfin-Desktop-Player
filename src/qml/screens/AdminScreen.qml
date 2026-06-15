import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// The server administration dashboard (jellyfin-web's Dashboard), reachable only
// for admins. Grouped nav mirrors the web drawer. Read-only GET panels are
// wired (System info, Users, Devices, Activity, Plugins, API Keys, Logs,
// Scheduled Tasks); editing-heavy pages are present but stubbed (manage in the
// web dashboard for now). All data via client.getJson → jsonReady.
Item {
    id: screen
    property var client
    property string pageTitle: qsTr("Administration")

    property int sel: 0
    property var panelData: null
    readonly property var selEntry: navModel[sel] || ({})

    // group | label | kind (info/list/stub) | endpoint | primary/secondary field
    readonly property var navModel: [
        { group: qsTr("Server"),   label: qsTr("Dashboard"),     kind: "info", ep: "/System/Info" },
        { group: qsTr("Server"),   label: qsTr("General"),       kind: "stub" },
        { group: qsTr("Server"),   label: qsTr("Branding"),      kind: "stub" },
        { group: qsTr("Server"),   label: qsTr("Users"),         kind: "list", ep: "/Users", primary: "Name", secondary: "Id" },
        { group: qsTr("Server"),   label: qsTr("Libraries"),     kind: "stub" },
        { group: qsTr("Server"),   label: qsTr("Metadata"),      kind: "stub" },
        { group: qsTr("Server"),   label: qsTr("Playback / Transcoding"), kind: "stub" },
        { group: qsTr("Server"),   label: qsTr("Trickplay"),     kind: "stub" },
        { group: qsTr("Devices"),  label: qsTr("Devices"),       kind: "list", ep: "/Devices", primary: "Name", secondary: "LastUserName" },
        { group: qsTr("Devices"),  label: qsTr("Activity"),      kind: "list", ep: "/System/ActivityLog/Entries?Limit=60", primary: "Name", secondary: "Type" },
        { group: qsTr("Live TV"),  label: qsTr("Live TV"),       kind: "stub" },
        { group: qsTr("Live TV"),  label: qsTr("DVR"),           kind: "stub" },
        { group: qsTr("Plugins"),  label: qsTr("Plugins"),       kind: "list", ep: "/Plugins", primary: "Name", secondary: "Version" },
        { group: qsTr("Advanced"), label: qsTr("Networking"),    kind: "stub" },
        { group: qsTr("Advanced"), label: qsTr("API Keys"),      kind: "list", ep: "/Auth/Keys", primary: "AppName", secondary: "DateCreated" },
        { group: qsTr("Advanced"), label: qsTr("Backups"),       kind: "stub" },
        { group: qsTr("Advanced"), label: qsTr("Logs"),          kind: "list", ep: "/System/Logs", primary: "Name", secondary: "Size" },
        { group: qsTr("Advanced"), label: qsTr("Scheduled Tasks"), kind: "list", ep: "/ScheduledTasks", primary: "Name", secondary: "State" }
    ]

    onSelChanged: loadSel()
    Component.onCompleted: loadSel()
    function loadSel() {
        panelData = null
        if (client && selEntry.kind !== "stub")
            client.getJson(selEntry.ep, "admin:panel")
    }
    function infoRows(d) {
        if (!d || typeof d !== "object") return []
        return Object.keys(d).map(function (k) {
            const v = d[k]
            return { k: k, v: (v !== null && typeof v === "object") ? JSON.stringify(v) : ("" + v) }
        })
    }
    function listRows(d) {
        if (!d) return []
        return Array.isArray(d) ? d : (d.Items || [])
    }

    Connections {
        target: screen.client
        function onJsonReady(tag, data) { if (tag === "admin:panel") screen.panelData = data }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // grouped nav
        Rectangle {
            Layout.preferredWidth: 240
            Layout.fillHeight: true
            color: Theme.backgroundAlt
            Flickable {
                anchors.fill: parent
                contentHeight: navCol.implicitHeight + Theme.spacing
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: navCol
                    width: parent.width
                    y: Theme.spacingSmall
                    spacing: 1
                    Repeater {
                        model: screen.navModel
                        ColumnLayout {
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                visible: index === 0 || screen.navModel[index - 1].group !== modelData.group
                                text: modelData.group
                                color: Theme.textDisabled
                                font.pixelSize: Theme.fontTiny
                                font.bold: true
                                Layout.leftMargin: Theme.spacing
                                Layout.topMargin: Theme.spacingSmall
                                Layout.bottomMargin: 2
                            }
                            ItemDelegate {
                                Layout.fillWidth: true
                                implicitHeight: 38
                                hoverEnabled: true
                                onClicked: screen.sel = index
                                contentItem: Text {
                                    text: modelData.label
                                    color: screen.sel === index ? Theme.accent : Theme.textPrimary
                                    font.pixelSize: Theme.fontNormal
                                    font.bold: screen.sel === index
                                    leftPadding: Theme.spacing + 6
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                background: Rectangle {
                                    color: parent.hovered ? Theme.surfaceHover : "transparent"
                                    Rectangle { width: 3; height: parent.height; color: Theme.accent; visible: screen.sel === index }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.divider }
        }

        // content
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: body.implicitHeight + Theme.spacingLarge * 2
            clip: true
            ScrollBar.vertical: ScrollBar {}
            ColumnLayout {
                id: body
                width: parent.width - Theme.pagePad * 2
                x: Theme.pagePad
                y: Theme.spacingLarge
                spacing: Theme.spacingSmall

                Text {
                    text: screen.selEntry.label || ""
                    color: Theme.textPrimary; font.pixelSize: Theme.fontLarge; font.bold: true
                    Layout.bottomMargin: Theme.spacingSmall
                }

                // stub
                Text {
                    visible: screen.selEntry.kind === "stub"
                    text: qsTr("This panel isn't built natively yet — manage it in the web dashboard for now.")
                    color: Theme.textSecondary; font.pixelSize: Theme.fontNormal; wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                // info (key/value)
                Text {
                    visible: screen.selEntry.kind !== "stub" && screen.panelData === null
                    text: qsTr("Loading…")
                    color: Theme.textSecondary; font.pixelSize: Theme.fontNormal
                }
                Repeater {
                    model: screen.selEntry.kind === "info" ? screen.infoRows(screen.panelData) : []
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Text { text: modelData.k; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: 260; elide: Text.ElideRight }
                        Text { text: modelData.v; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    }
                }

                // list (rows)
                Repeater {
                    model: screen.selEntry.kind === "list" ? screen.listRows(screen.panelData) : []
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: Theme.radius
                        color: Theme.surface
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacing
                            anchors.rightMargin: Theme.spacing
                            Text {
                                text: ("" + (modelData[screen.selEntry.primary] || modelData.Name || "—"))
                                color: Theme.textPrimary; font.pixelSize: Theme.fontNormal
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                            Text {
                                text: screen.selEntry.secondary ? ("" + (modelData[screen.selEntry.secondary] || "")) : ""
                                color: Theme.textSecondary; font.pixelSize: Theme.fontSmall
                                elide: Text.ElideRight; Layout.maximumWidth: 320
                            }
                        }
                    }
                }
                Text {
                    visible: screen.selEntry.kind === "list" && screen.panelData !== null && screen.listRows(screen.panelData).length === 0
                    text: qsTr("Nothing here.")
                    color: Theme.textSecondary; font.pixelSize: Theme.fontNormal
                }
            }
        }
    }
}
