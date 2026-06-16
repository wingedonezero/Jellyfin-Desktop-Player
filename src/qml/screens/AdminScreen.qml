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
    property var tasksData: []
    property var usersData: []
    property var selectedUser: null
    property var editPolicy: ({})
    property var serverConfig: null
    property var editConfig: ({})
    property var dynOptions: ({})          // dynamically-fetched select options (e.g. {users: [...]})
    property var pendingAction: null
    readonly property var selEntry: navModel[sel] || ({})

    // field sets for the data-driven server-config editors (kind "config")
    readonly property var generalFields: [
        {label: qsTr("Server name"), key: "ServerName", type: "text"},
        {label: qsTr("Preferred display language"), key: "UICulture", type: "text"},
        {label: qsTr("Cache path"), key: "CachePath", type: "text"},
        {label: qsTr("Metadata path"), key: "MetadataPath", type: "text"},
        {label: qsTr("Enable Quick Connect"), key: "QuickConnectAvailable", type: "toggle"},
        {label: qsTr("Library scan fanout concurrency (0 = auto)"), key: "LibraryScanFanoutConcurrency", type: "number"},
        {label: qsTr("Parallel image encoding limit (0 = auto)"), key: "ParallelImageEncodingLimit", type: "number"}
    ]
    readonly property var brandingFields: [
        {label: qsTr("Enable splash screen"), key: "SplashscreenEnabled", type: "toggle"},
        {label: qsTr("Login disclaimer"), key: "LoginDisclaimer", type: "text"},
        {label: qsTr("Custom CSS"), key: "CustomCss", type: "text"}
    ]
    readonly property var metadataFields: [
        {label: qsTr("Preferred metadata language"), key: "PreferredMetadataLanguage", type: "text"},
        {label: qsTr("Country code"), key: "MetadataCountryCode", type: "text"},
        {label: qsTr("Dummy chapter duration (seconds)"), key: "DummyChapterDuration", type: "number"},
        {label: qsTr("Chapter image resolution"), key: "ChapterImageResolution", type: "text"}
    ]
    readonly property var networkFields: [
        {label: qsTr("Base URL"), key: "BaseUrl", type: "text"},
        {label: qsTr("Enable HTTPS"), key: "EnableHttps", type: "toggle"},
        {label: qsTr("Require HTTPS"), key: "RequireHttps", type: "toggle"},
        {label: qsTr("HTTP port"), key: "InternalHttpPort", type: "number"},
        {label: qsTr("HTTPS port"), key: "InternalHttpsPort", type: "number"},
        {label: qsTr("Public HTTP port"), key: "PublicHttpPort", type: "number"},
        {label: qsTr("Allow remote connections"), key: "EnableRemoteAccess", type: "toggle"},
        {label: qsTr("Enable auto-discovery"), key: "AutoDiscovery", type: "toggle"},
        {label: qsTr("Certificate path"), key: "CertificatePath", type: "text"}
    ]
    readonly property var encodingFields: [
        {label: qsTr("Hardware acceleration"), key: "HardwareAccelerationType", type: "text"},
        {label: qsTr("Encoding thread count (-1 = auto)"), key: "EncodingThreadCount", type: "number"},
        {label: qsTr("Transcode temp path"), key: "TranscodingTempPath", type: "text"},
        {label: qsTr("H.264 CRF"), key: "H264Crf", type: "number"},
        {label: qsTr("Allow HEVC encoding"), key: "AllowHevcEncoding", type: "toggle"},
        {label: qsTr("Enable throttling"), key: "EnableThrottling", type: "toggle"},
        {label: qsTr("Enable audio VBR"), key: "EnableAudioVbr", type: "toggle"}
    ]
    readonly property var resumeFields: [
        {label: qsTr("Minimum resume percentage"), key: "MinResumePct", type: "number"},
        {label: qsTr("Maximum resume percentage"), key: "MaxResumePct", type: "number"},
        {label: qsTr("Minimum audiobook resume (%)"), key: "MinAudiobookResume", type: "number"},
        {label: qsTr("Maximum audiobook resume (%)"), key: "MaxAudiobookResume", type: "number"},
        {label: qsTr("Minimum resume duration (seconds)"), key: "MinResumeDurationSeconds", type: "number"}
    ]
    readonly property var streamingFields: [
        {label: qsTr("Remote client bitrate limit (Mbps, 0 = unlimited)"), key: "RemoteClientBitrateLimit", type: "number", scale: 1000000}
    ]
    readonly property var nfoFields: [
        {label: qsTr("Kodi metadata user"), key: "UserId", type: "select", optionsKey: "users"},
        {label: qsTr("Save image paths in NFO"), key: "SaveImagePathsInNfo", type: "toggle"},
        {label: qsTr("Enable path substitution"), key: "EnablePathSubstitution", type: "toggle"},
        {label: qsTr("Duplicate extra thumbnails (extrafanart/extrathumbs)"), key: "EnableExtraThumbsDuplication", type: "toggle"}
    ]
    // Trickplay lives in the nested ServerConfiguration.TrickplayOptions object → dot-path keys.
    readonly property var trickplayFields: [
        {label: qsTr("Enable hardware decoding"), key: "TrickplayOptions.EnableHwAcceleration", type: "toggle"},
        {label: qsTr("Enable hardware encoding"), key: "TrickplayOptions.EnableHwEncoding", type: "toggle"},
        {label: qsTr("Key-frame-only extraction"), key: "TrickplayOptions.EnableKeyFrameOnlyExtraction", type: "toggle"},
        {label: qsTr("Scan behavior"), key: "TrickplayOptions.ScanBehavior", type: "select", options: [{value: "NonBlocking", text: qsTr("Non-blocking")}, {value: "Blocking", text: qsTr("Blocking")}]},
        {label: qsTr("Process priority"), key: "TrickplayOptions.ProcessPriority", type: "select", options: [{value: "High", text: qsTr("High")}, {value: "AboveNormal", text: qsTr("Above normal")}, {value: "Normal", text: qsTr("Normal")}, {value: "BelowNormal", text: qsTr("Below normal")}, {value: "Idle", text: qsTr("Idle")}]},
        {label: qsTr("Image interval (ms)"), key: "TrickplayOptions.Interval", type: "number"},
        {label: qsTr("Width resolutions (comma-separated)"), key: "TrickplayOptions.WidthResolutions", type: "csv"},
        {label: qsTr("Tile width (images per tile)"), key: "TrickplayOptions.TileWidth", type: "number"},
        {label: qsTr("Tile height (images per tile)"), key: "TrickplayOptions.TileHeight", type: "number"},
        {label: qsTr("JPEG quality (1–100)"), key: "TrickplayOptions.JpegQuality", type: "number"},
        {label: qsTr("Qscale (2–31)"), key: "TrickplayOptions.Qscale", type: "number"},
        {label: qsTr("Process threads (0 = auto)"), key: "TrickplayOptions.ProcessThreads", type: "number"}
    ]

    // group | label | kind (config/info/list/stub) | endpoint | fields | primary/secondary | fmt
    readonly property var navModel: [
        { group: qsTr("Server"),   label: qsTr("Dashboard"),     kind: "dashboard" },
        { group: qsTr("Server"),   label: qsTr("General"),       kind: "config", ep: "/System/Configuration", fields: screen.generalFields },
        { group: qsTr("Server"),   label: qsTr("Branding"),      kind: "config", ep: "/System/Configuration/branding", fields: screen.brandingFields },
        { group: qsTr("Server"),   label: qsTr("Users"),         kind: "users" },
        { group: qsTr("Server"),   label: qsTr("Libraries"),     kind: "stub" },
        { group: qsTr("Server"),   label: qsTr("Metadata"),      kind: "config", ep: "/System/Configuration", fields: screen.metadataFields },
        { group: qsTr("Server"),   label: qsTr("NFO"),           kind: "config", ep: "/System/Configuration/xbmcmetadata", fields: screen.nfoFields },
        { group: qsTr("Server"),   label: qsTr("Playback / Transcoding"), kind: "config", ep: "/System/Configuration/encoding", fields: screen.encodingFields },
        { group: qsTr("Server"),   label: qsTr("Resume"),        kind: "config", ep: "/System/Configuration", fields: screen.resumeFields },
        { group: qsTr("Server"),   label: qsTr("Streaming"),     kind: "config", ep: "/System/Configuration", fields: screen.streamingFields },
        { group: qsTr("Server"),   label: qsTr("Trickplay"),     kind: "config", ep: "/System/Configuration", fields: screen.trickplayFields },
        { group: qsTr("Devices"),  label: qsTr("Devices"),       kind: "list", ep: "/Devices", fmt: "devices" },
        { group: qsTr("Devices"),  label: qsTr("Activity"),      kind: "list", ep: "/System/ActivityLog/Entries?Limit=60", fmt: "activity" },
        { group: qsTr("Live TV"),  label: qsTr("Live TV"),       kind: "stub" },
        { group: qsTr("Live TV"),  label: qsTr("DVR"),           kind: "stub" },
        { group: qsTr("Plugins"),  label: qsTr("Plugins"),       kind: "list", ep: "/Plugins", fmt: "plugins" },
        { group: qsTr("Advanced"), label: qsTr("Networking"),    kind: "config", ep: "/System/Configuration/network", fields: screen.networkFields },
        { group: qsTr("Advanced"), label: qsTr("API Keys"),      kind: "list", ep: "/Auth/Keys", primary: "AppName", secondary: "DateCreated" },
        { group: qsTr("Advanced"), label: qsTr("Backups"),       kind: "stub" },
        { group: qsTr("Advanced"), label: qsTr("Logs"),          kind: "list", ep: "/System/Logs", primary: "Name", secondary: "Size" },
        { group: qsTr("Advanced"), label: qsTr("Scheduled Tasks"), kind: "tasks" }
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
        } else if (selEntry.kind === "tasks") {
            tasksData = []
            client.getJson("/ScheduledTasks", "admin:tasks")
        } else if (selEntry.kind === "users") {
            usersData = []; selectedUser = null
            client.getJson("/Users", "admin:users")
        } else if (selEntry.kind === "config") {
            serverConfig = null; editConfig = ({}); dynOptions = ({})
            client.getJson(selEntry.ep, "admin:config")
            var fs = selEntry.fields || []
            for (var i = 0; i < fs.length; i++) if (fs[i].optionsKey === "users") { client.getJson("/Users", "admin:config:users"); break }
        } else if (selEntry.kind !== "stub") {
            client.getJson(selEntry.ep, "admin:panel")
        }
    }
    // confirm a destructive action before running it (server actions)
    function confirm(msg, action) { confirmPopup.message = msg; pendingAction = action; confirmPopup.open() }
    function relTime(iso) {
        if (!iso) return ""
        const t = Date.parse(iso); if (isNaN(t)) return ""
        const diff = (Date.now() - t) / 1000
        if (diff < 0) return ""
        if (diff < 60) return qsTr("just now")
        if (diff < 3600) return qsTr("%1m ago").arg(Math.floor(diff / 60))
        if (diff < 86400) return qsTr("%1h ago").arg(Math.floor(diff / 3600))
        return qsTr("%1d ago").arg(Math.floor(diff / 86400))
    }
    function durationStr(s, e) {
        if (!s || !e) return ""
        const d = (Date.parse(e) - Date.parse(s)) / 1000
        if (isNaN(d) || d < 0) return ""
        if (d < 90) return qsTr("%1s").arg(Math.round(d))
        if (d < 5400) return qsTr("%1m").arg(Math.round(d / 60))
        return qsTr("%1h").arg(Math.round(d / 3600))
    }
    function infoRows(d) {
        if (!d || typeof d !== "object") return []
        return Object.keys(d).map(function (k) {
            const v = d[k]
            return { k: k, v: (v !== null && typeof v === "object") ? JSON.stringify(v) : ("" + v) }
        })
    }
    // getJson hands back a QVariantList, which QML does NOT see as a native JS
    // Array (Array.isArray is false) — detect list-like by .length, and unwrap
    // the paged { Items: [...] } shape some endpoints use.
    function asArray(d) {
        if (!d) return []
        if (d.length !== undefined) return d
        return d.Items || []
    }
    function listRows(d) { return asArray(d) }
    function listTitle(entry, item) {
        if (!item) return "—"
        if (entry.fmt === "devices") return ("" + (item.CustomName || item.Name || "—"))
        return ("" + (item.Name || item[entry.primary] || "—"))
    }
    function listSub(entry, item) {
        if (!item) return ""
        var parts = []
        if (entry.fmt === "activity") parts = [relTime(item.Date), item.Severity, item.ShortOverview]
        else if (entry.fmt === "devices") parts = [item.AppName, item.LastUserName, item.DateLastActivity ? relTime(item.DateLastActivity) : ""]
        else if (entry.fmt === "plugins") parts = [item.Version ? ("v" + item.Version) : "", item.Status, item.Description]
        else return entry.secondary ? ("" + (item[entry.secondary] || "")) : ""
        return parts.filter(function (x) { return x }).join("  ·  ")
    }

    Connections {
        target: screen.client
        function onJsonReady(tag, data) {
            if (tag === "admin:panel") screen.panelData = data
            else if (tag === "admin:dash:info") screen.dashInfo = data
            else if (tag === "admin:dash:counts") screen.dashCounts = data
            else if (tag === "admin:dash:sessions") screen.dashSessions = screen.asArray(data)
            else if (tag === "admin:tasks") screen.tasksData = screen.asArray(data)
            else if (tag === "admin:users") screen.usersData = screen.asArray(data)
            else if (tag === "admin:config") { screen.serverConfig = data; screen.editConfig = data ? JSON.parse(JSON.stringify(data)) : ({}) }
            else if (tag === "admin:config:users") {
                var opts = [{value: "", text: qsTr("None")}]
                var us = screen.asArray(data)
                for (var i = 0; i < us.length; i++) opts.push({value: us[i].Id, text: us[i].Name})
                screen.dynOptions = Object.assign({}, screen.dynOptions, {users: opts})
            }
        }
    }

    function selectUser(u) {
        selectedUser = u
        editPolicy = (u && u.Policy) ? JSON.parse(JSON.stringify(u.Policy)) : ({})
    }
    function setFlag(key, val) { var p = Object.assign({}, editPolicy); p[key] = val; editPolicy = p }

    component PolicyToggle: RowLayout {
        id: pt
        property string label: ""
        property string flag: ""
        Layout.fillWidth: true
        Text { text: pt.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
        Rectangle {
            id: sw
            readonly property bool on: screen.editPolicy[pt.flag] === true
            width: 44; height: 24; radius: 12
            color: on ? Theme.accent : Theme.elevated
            Rectangle { width: 18; height: 18; radius: 9; y: 3; x: sw.on ? 23 : 3; color: Theme.textPrimary; Behavior on x { NumberAnimation { duration: 120 } } }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: screen.setFlag(pt.flag, !sw.on) }
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

    // editConfig accessors with dot-path support (e.g. "TrickplayOptions.Interval").
    // setConfig deep-clones so a nested edit still flips the top-level ref (reactivity).
    function cfgGet(path) {
        var o = editConfig
        var parts = ("" + path).split(".")
        for (var i = 0; i < parts.length; i++) {
            if (o === null || o === undefined) return undefined
            o = o[parts[i]]
        }
        return o
    }
    function setConfig(path, val) {
        var c = editConfig ? JSON.parse(JSON.stringify(editConfig)) : ({})
        var parts = ("" + path).split(".")
        var o = c
        for (var i = 0; i < parts.length - 1; i++) {
            if (o[parts[i]] === null || o[parts[i]] === undefined) o[parts[i]] = ({})
            o = o[parts[i]]
        }
        o[parts[parts.length - 1]] = val
        editConfig = c
    }
    component ConfigField: RowLayout {
        id: cf
        property string label: ""
        property string key: ""
        property string mode: "text"     // text | number | csv
        property real scale: 1           // number display divisor (e.g. 1e6 = bps shown as Mbps)
        function display() {
            var v = screen.cfgGet(cf.key)
            if (v === undefined || v === null) return ""
            if (cf.mode === "csv") return (typeof v !== "string" && v.length !== undefined) ? v.join(",") : ("" + v)
            if (cf.mode === "number" && cf.scale !== 1) return v ? ("" + (v / cf.scale)) : ""
            return "" + v
        }
        function commit(t) {
            if (cf.mode === "csv")
                screen.setConfig(cf.key, ("" + t).replace(/\s/g, "").split(",").filter(function (x) { return x.length }).map(Number))
            else if (cf.mode === "number")
                screen.setConfig(cf.key, cf.scale !== 1 ? Math.trunc(cf.scale * (parseFloat(t) || 0)) : (parseInt(t) || 0))
            else
                screen.setConfig(cf.key, t)
        }
        Layout.fillWidth: true
        Text { text: cf.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
        TextField {
            Layout.preferredWidth: 340
            text: cf.display()
            color: Theme.textPrimary; placeholderTextColor: Theme.textDisabled; font.pixelSize: Theme.fontSmall
            inputMethodHints: cf.mode === "number" ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
            onEditingFinished: cf.commit(text)
            background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 }
        }
    }
    component ConfigToggle: RowLayout {
        id: ct
        property string label: ""
        property string key: ""
        Layout.fillWidth: true
        Text { text: ct.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
        Rectangle {
            id: cs
            readonly property bool on: screen.cfgGet(ct.key) === true
            width: 44; height: 24; radius: 12; color: on ? Theme.accent : Theme.elevated
            Rectangle { width: 18; height: 18; radius: 9; y: 3; x: cs.on ? 23 : 3; color: Theme.textPrimary; Behavior on x { NumberAnimation { duration: 120 } } }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: screen.setConfig(ct.key, !cs.on) }
        }
    }
    component ConfigSelect: RowLayout {
        id: csel
        property string label: ""
        property string key: ""
        property var options: []          // [{value, text}]
        function syncIndex() {
            var cur = screen.cfgGet(csel.key)
            for (var i = 0; i < csel.options.length; i++)
                if (String(csel.options[i].value) === String(cur)) { cbox.currentIndex = i; return }
            cbox.currentIndex = -1
        }
        onOptionsChanged: syncIndex()
        // editConfig is assigned just after serverConfig, but the Repeater builds us
        // synchronously on the serverConfig change — so re-sync once editConfig lands.
        Connections { target: screen; function onEditConfigChanged() { csel.syncIndex() } }
        Layout.fillWidth: true
        Text { text: csel.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
        ComboBox {
            id: cbox
            Layout.preferredWidth: 340
            implicitHeight: 34
            model: csel.options
            textRole: "text"
            Component.onCompleted: csel.syncIndex()
            onActivated: (idx) => screen.setConfig(csel.key, csel.options[idx].value)
            background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: cbox.activeFocus || cbox.hovered ? Theme.accent : Theme.divider; border.width: 1 }
            contentItem: Text { text: cbox.currentIndex >= 0 ? cbox.displayText : qsTr("—"); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; leftPadding: 10; rightPadding: 26; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            indicator: Text { x: cbox.width - width - 10; y: (cbox.height - height) / 2; text: "▾"; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
            popup: Popup {
                y: cbox.height + 2; width: cbox.width
                implicitHeight: Math.min(clist.contentHeight + 2, 300); padding: 1
                background: Rectangle { color: Theme.elevated; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
                contentItem: ListView {
                    id: clist
                    clip: true
                    model: cbox.popup.visible ? cbox.delegateModel : null
                    currentIndex: cbox.highlightedIndex
                    ScrollBar.vertical: ScrollBar { active: true }
                }
            }
            delegate: ItemDelegate {
                required property var modelData
                required property int index
                width: cbox.width; implicitHeight: 32; hoverEnabled: true
                contentItem: Text { text: modelData.text; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; leftPadding: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                background: Rectangle { color: hovered ? Theme.surfaceHover : "transparent" }
            }
        }
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

                // scheduled tasks — grouped list with Run / Stop
                ColumnLayout {
                    visible: screen.selEntry.kind === "tasks"
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall
                    Repeater {
                        model: screen.tasksData
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 56; radius: Theme.radius; color: Theme.surface
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: Theme.spacing; anchors.rightMargin: Theme.spacing; spacing: Theme.spacing
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Text { text: ("" + (modelData.Name || "—")); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text {
                                        text: {
                                            var s = ("" + (modelData.Category || ""))
                                            if (modelData.State === "Running")
                                                return s + "  ·  " + qsTr("Running %1%").arg(Math.round(modelData.CurrentProgressPercentage || 0))
                                            var lr = modelData.LastExecutionResult
                                            if (lr && lr.Status) {
                                                s += "  ·  " + lr.Status
                                                var when = screen.relTime(lr.EndTimeUtc)
                                                var dur = screen.durationStr(lr.StartTimeUtc, lr.EndTimeUtc)
                                                if (when) s += " " + when
                                                if (dur) s += " (" + dur + ")"
                                            } else {
                                                s += "  ·  " + qsTr("never run")
                                            }
                                            return s
                                        }
                                        color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; elide: Text.ElideRight; Layout.fillWidth: true
                                    }
                                }
                                DashButton { visible: modelData.State !== "Running"; text: qsTr("Run"); onClicked: screen.confirm(qsTr("Run “%1” now?").arg(modelData.Name), function() { screen.client.runScheduledTask(modelData.Id) }) }
                                DashButton { visible: modelData.State === "Running"; text: qsTr("Stop"); danger: true; onClicked: screen.client.stopScheduledTask(modelData.Id) }
                            }
                        }
                    }
                }

                // users — list, then per-user policy detail/edit on selection
                ColumnLayout {
                    visible: screen.selEntry.kind === "users"
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall
                    Repeater {
                        model: screen.selectedUser === null ? screen.usersData : []
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 56; radius: Theme.radius; color: ma2.containsMouse ? Theme.surfaceHover : Theme.surface
                            MouseArea { id: ma2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: screen.selectUser(modelData) }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: Theme.spacing; anchors.rightMargin: Theme.spacing; spacing: Theme.spacing
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Text { text: ("" + (modelData.Name || "—")); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal }
                                    Text { text: modelData.LastActivityDate ? qsTr("Last seen %1").arg(screen.relTime(modelData.LastActivityDate)) : qsTr("Never signed in"); color: Theme.textSecondary; font.pixelSize: Theme.fontTiny }
                                }
                                Text { visible: modelData.Policy && modelData.Policy.IsAdministrator === true; text: qsTr("ADMIN"); color: Theme.accent; font.pixelSize: Theme.fontTiny; font.bold: true }
                                Text { visible: modelData.Policy && modelData.Policy.IsDisabled === true; text: qsTr("DISABLED"); color: Theme.error; font.pixelSize: Theme.fontTiny; font.bold: true }
                            }
                        }
                    }
                    ColumnLayout {
                        visible: screen.selectedUser !== null
                        Layout.fillWidth: true; spacing: Theme.spacingSmall
                        RowLayout {
                            Layout.fillWidth: true
                            DashButton { text: qsTr("← Back"); onClicked: screen.selectedUser = null }
                            Text { text: screen.selectedUser ? screen.selectedUser.Name : ""; color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.fillWidth: true; leftPadding: Theme.spacing; verticalAlignment: Text.AlignVCenter }
                        }
                        Text { text: qsTr("Account"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicyToggle { label: qsTr("Administrator"); flag: "IsAdministrator" }
                        PolicyToggle { label: qsTr("Disable this user"); flag: "IsDisabled" }
                        PolicyToggle { label: qsTr("Hide from login screen"); flag: "IsHidden" }
                        Text { text: qsTr("Playback"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicyToggle { label: qsTr("Allow media playback"); flag: "EnableMediaPlayback" }
                        PolicyToggle { label: qsTr("Allow audio transcoding"); flag: "EnableAudioPlaybackTranscoding" }
                        PolicyToggle { label: qsTr("Allow video transcoding"); flag: "EnableVideoPlaybackTranscoding" }
                        Text { text: qsTr("Permissions"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicyToggle { label: qsTr("Allow downloads"); flag: "EnableContentDownloading" }
                        PolicyToggle { label: qsTr("Allow collection management"); flag: "EnableCollectionManagement" }
                        PolicyToggle { label: qsTr("Allow media deletion"); flag: "EnableContentDeletion" }
                        PolicyToggle { label: qsTr("Remote-control other users"); flag: "EnableRemoteControlOfOtherUsers" }
                        Text {
                            text: qsTr("Library access: %1").arg((screen.editPolicy.EnableAllFolders === true) ? qsTr("all libraries") : qsTr("%1 selected").arg((screen.editPolicy.EnabledFolders || []).length))
                            color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.topMargin: Theme.spacingSmall
                        }
                        RowLayout {
                            Layout.topMargin: Theme.spacing; spacing: Theme.spacingSmall
                            DashButton { text: qsTr("Save changes"); onClicked: screen.confirm(qsTr("Save policy changes for “%1”?").arg(screen.selectedUser.Name), function() { screen.client.setUserPolicy(screen.selectedUser.Id, screen.editPolicy) }) }
                            DashButton { text: qsTr("Delete user"); danger: true; onClicked: screen.confirm(qsTr("Delete the user “%1”? This cannot be undone.").arg(screen.selectedUser.Name), function() { screen.client.deleteUser(screen.selectedUser.Id); screen.selectedUser = null }) }
                        }
                    }
                }

                // config — data-driven server config editor; edits a deep copy, Save POSTs the whole object to selEntry.ep
                ColumnLayout {
                    visible: screen.selEntry.kind === "config"
                    Layout.fillWidth: true; spacing: Theme.spacingSmall
                    Text { visible: screen.serverConfig === null; text: qsTr("Loading…"); color: Theme.textSecondary; font.pixelSize: Theme.fontNormal }
                    Component { id: cfgFieldComp; ConfigField { label: parent.modelData.label; key: parent.modelData.key; mode: parent.modelData.type === "csv" ? "csv" : (parent.modelData.type === "number" ? "number" : "text"); scale: parent.modelData.scale || 1 } }
                    Component { id: cfgToggleComp; ConfigToggle { label: parent.modelData.label; key: parent.modelData.key } }
                    Component { id: cfgSelectComp; ConfigSelect { label: parent.modelData.label; key: parent.modelData.key; options: parent.modelData.options || (parent.modelData.optionsKey ? (screen.dynOptions[parent.modelData.optionsKey] || []) : []) } }
                    Repeater {
                        model: (screen.serverConfig !== null && screen.selEntry.fields) ? screen.selEntry.fields : []
                        Loader {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            sourceComponent: modelData.type === "toggle" ? cfgToggleComp : (modelData.type === "select" ? cfgSelectComp : cfgFieldComp)
                        }
                    }
                    RowLayout {
                        visible: screen.serverConfig !== null
                        Layout.topMargin: Theme.spacing
                        DashButton { text: qsTr("Save changes"); onClicked: screen.confirm(qsTr("Save these server settings?"), function() { screen.client.postJson(screen.selEntry.ep, screen.editConfig) }) }
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
                    visible: screen.selEntry.kind !== "stub" && screen.selEntry.kind !== "dashboard" && screen.selEntry.kind !== "tasks" && screen.selEntry.kind !== "users" && screen.selEntry.kind !== "config" && screen.panelData === null
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

                // list (rows) — 2-line, formatted per panel via listTitle/listSub
                Repeater {
                    model: screen.selEntry.kind === "list" ? screen.listRows(screen.panelData) : []
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: Theme.radius
                        color: Theme.surface
                        ColumnLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: Theme.spacing; anchors.rightMargin: Theme.spacing
                            spacing: 2
                            Text {
                                text: screen.listTitle(screen.selEntry, modelData)
                                color: Theme.textPrimary; font.pixelSize: Theme.fontNormal
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                            Text {
                                text: screen.listSub(screen.selEntry, modelData)
                                visible: text.length > 0
                                color: Theme.textSecondary; font.pixelSize: Theme.fontTiny
                                Layout.fillWidth: true; elide: Text.ElideRight
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
