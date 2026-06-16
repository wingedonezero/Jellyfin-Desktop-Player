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
    property var dashInfo: null
    property var dashCounts: null
    property var dashSessions: []
    property var pendingAction: null
    readonly property var selEntry: navModel[sel] || ({})

    // group | label | kind (info/list/stub) | endpoint | primary/secondary field
    readonly property var navModel: [
        { group: qsTr("Server"),   label: qsTr("Dashboard"),     kind: "dashboard" },
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
        if (!client) return
        if (selEntry.kind === "dashboard") {
            client.getJson("/System/Info", "admin:dash:info")
            client.getJson("/Items/Counts", "admin:dash:counts")
            client.getJson("/Sessions", "admin:dash:sessions")
        } else if (selEntry.kind !== "stub") {
            client.getJson(selEntry.ep, "admin:panel")
        }
    }
    // confirm a destructive action before running it (server actions)
    function confirm(msg, action) { confirmPopup.message = msg; pendingAction = action; confirmPopup.open() }
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
        function onJsonReady(tag, data) {
            if (tag === "admin:panel") screen.panelData = data
            else if (tag === "admin:dash:info") screen.dashInfo = data
            else if (tag === "admin:dash:counts") screen.dashCounts = data
            else if (tag === "admin:dash:sessions") screen.dashSessions = Array.isArray(data) ? data : []
        }
    }

    component DashButton: Rectangle {
        id: db
        property string text: ""
        property bool danger: false
        signal clicked()
        implicitHeight: 34; implicitWidth: lbl.implicitWidth + 28; radius: Theme.radius
        color: ma.containsMouse ? Theme.surfaceHover : Theme.surface
        border.color: danger ? Theme.error : Theme.divider; border.width: 1
        Text { id: lbl; anchors.centerIn: parent; text: db.text; color: db.danger ? Theme.error : Theme.textPrimary; font.pixelSize: Theme.fontSmall }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: db.clicked() }
    }

    Popup {
        id: confirmPopup
        property string message: ""
        x: (screen.width - width) / 2
        y: (screen.height - height) / 2
        modal: true; dim: true
        width: 380; padding: Theme.spacing
        background: Rectangle { color: Theme.elevated; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
        contentItem: ColumnLayout {
            spacing: Theme.spacing
            Text { text: confirmPopup.message; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.preferredWidth: 340 }
            RowLayout {
                Layout.alignment: Qt.AlignRight; spacing: Theme.spacingSmall
                DashButton { text: qsTr("Cancel"); onClicked: confirmPopup.close() }
                DashButton { text: qsTr("Confirm"); danger: true; onClicked: { confirmPopup.close(); if (screen.pendingAction) screen.pendingAction() } }
            }
        }
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

                // dashboard — formatted server card + library counts + sessions + actions
                ColumnLayout {
                    visible: screen.selEntry.kind === "dashboard"
                    Layout.fillWidth: true
                    spacing: Theme.spacing
                    Rectangle {
                        Layout.fillWidth: true; radius: Theme.radius; color: Theme.surface
                        implicitHeight: srv.implicitHeight + Theme.spacing * 2
                        ColumnLayout {
                            id: srv
                            x: Theme.spacing; y: Theme.spacing; width: parent.width - Theme.spacing * 2
                            spacing: 4
                            Text { text: (screen.dashInfo ? screen.dashInfo.ServerName : qsTr("Server")) + "  ·  Jellyfin " + (screen.dashInfo ? screen.dashInfo.Version : "—"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true }
                            Text { text: screen.dashInfo ? (screen.dashInfo.OperatingSystemDisplayName + " · " + screen.dashInfo.SystemArchitecture) : ""; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
                            RowLayout {
                                Layout.topMargin: Theme.spacingSmall; spacing: Theme.spacingSmall
                                DashButton { text: qsTr("Scan all libraries"); onClicked: screen.confirm(qsTr("Start a scan of all libraries now?"), function() { screen.client.scanAllLibraries() }) }
                                DashButton { text: qsTr("Restart"); danger: true; onClicked: screen.confirm(qsTr("Restart the Jellyfin server now?"), function() { screen.client.restartServer() }) }
                                DashButton { text: qsTr("Shut down"); danger: true; onClicked: screen.confirm(qsTr("Shut down the Jellyfin server now?"), function() { screen.client.shutdownServer() }) }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.spacingSmall
                        Repeater {
                            model: [{k: "MovieCount", t: qsTr("Movies")}, {k: "SeriesCount", t: qsTr("Series")}, {k: "EpisodeCount", t: qsTr("Episodes")}, {k: "BoxSetCount", t: qsTr("Collections")}]
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true; implicitHeight: 64; radius: Theme.radius; color: Theme.surface
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: 0
                                    Text { text: screen.dashCounts ? ("" + (screen.dashCounts[modelData.k] || 0)) : "—"; color: Theme.accent; font.pixelSize: Theme.fontLarge; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                                    Text { text: modelData.t; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.alignment: Qt.AlignHCenter }
                                }
                            }
                        }
                    }
                    Text { text: qsTr("Active devices (%1)").arg(screen.dashSessions.length); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                    Repeater {
                        model: screen.dashSessions
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 44; radius: Theme.radius; color: Theme.surface
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: Theme.spacing; anchors.rightMargin: Theme.spacing; spacing: Theme.spacing
                                Text { text: ("" + (modelData.UserName || "—")); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: 140; elide: Text.ElideRight }
                                Text { text: ((modelData.Client || "") + " · " + (modelData.DeviceName || "")); color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: (modelData.NowPlayingItem ? ("▶ " + modelData.NowPlayingItem.Name) : ""); color: Theme.accent; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.maximumWidth: 260 }
                            }
                        }
                    }
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
                    visible: screen.selEntry.kind !== "stub" && screen.selEntry.kind !== "dashboard" && screen.panelData === null
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
