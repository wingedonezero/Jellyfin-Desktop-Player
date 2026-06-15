import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import JellyfinDesktop

// The on-screen controls (OSD), styled as the jellyfin-web player skin: a top
// bar (back / title / syncplay / cast) and a bottom bar (scrubber with chapter
// ticks, transport, "ends at", favorite, subtitle/audio menus, volume, and a
// settings menu for aspect / speed / subtitle timing / playback info). Every
// control in the web player is present; ones we can't back yet are rendered
// disabled and gated centrally by Features. Driven by the observed mpv state.
Item {
    id: root
    required property var player
    property string title: ""
    property bool favorite: false

    signal back()
    signal toggleFullscreen()
    signal toggleFavorite()

    // Local skin state (the mpv side is authoritative for speed/delays).
    property string aspectMode: "Auto"
    property real subScale: 1.0
    property bool statsVisible: false
    property var statsRows: []

    // ---- helpers ----------------------------------------------------------
    function fmt(t) {
        if (!t || t < 0 || isNaN(t))
            t = 0
        t = Math.floor(t)
        const h = Math.floor(t / 3600)
        const m = Math.floor((t % 3600) / 60)
        const s = t % 60
        const pad = (n) => (n < 10 ? "0" + n : "" + n)
        return (h > 0 ? h + ":" + pad(m) : "" + m) + ":" + pad(s)
    }
    function fmtSpeed(s) { return (Math.round(s * 100) / 100) + "x" }
    function endsAt() {
        const remain = Math.max(0, root.player.duration - root.player.position)
                       / Math.max(0.01, root.player.speed)
        return Qt.formatTime(new Date(Date.now() + remain * 1000), "h:mm AP")
    }
    function applyAspect(mode) {
        root.aspectMode = mode
        if (mode === "Cover") {
            root.player.setOption("panscan", "1.0")
            root.player.setOption("keepaspect", "yes")
            root.player.setOption("video-aspect-override", "-1")
        } else if (mode === "Fill") {
            root.player.setOption("panscan", "0")
            root.player.setOption("keepaspect", "no")
            root.player.setOption("video-aspect-override", "-1")
        } else { // Auto
            root.player.setOption("panscan", "0")
            root.player.setOption("keepaspect", "yes")
            root.player.setOption("video-aspect-override", "-1")
        }
    }
    function refreshStats() {
        const p = root.player
        const q = (name) => { const v = p.queryProperty(name); return (v && v.length) ? v : "—" }
        const vbr = parseFloat(p.queryProperty("video-bitrate"))
        const abr = parseFloat(p.queryProperty("audio-bitrate"))
        const fps = parseFloat(p.queryProperty("estimated-vf-fps"))
        const cache = parseFloat(p.queryProperty("demuxer-cache-duration"))
        const w = p.queryProperty("width")
        const h = p.queryProperty("height")
        root.statsRows = [
            { k: qsTr("Player"),           v: "mpv (libmpv, direct)" },
            { k: qsTr("Video"),            v: q("video-codec") },
            { k: qsTr("Resolution"),       v: (w && h) ? (w + "×" + h) : "—" },
            { k: qsTr("Frame rate"),       v: isNaN(fps) ? "—" : fps.toFixed(2) + " fps" },
            { k: qsTr("Video bitrate"),    v: isNaN(vbr) ? "—" : (vbr / 1e6).toFixed(2) + " Mbps" },
            { k: qsTr("Dropped frames"),   v: q("frame-drop-count") },
            { k: qsTr("Hardware decoder"), v: q("hwdec-current") },
            { k: qsTr("Audio"),            v: q("audio-codec") },
            { k: qsTr("Audio bitrate"),    v: isNaN(abr) ? "—" : Math.round(abr / 1000) + " kbps" },
            { k: qsTr("Container"),        v: q("file-format") },
            { k: qsTr("Buffered"),         v: isNaN(cache) ? "—" : cache.toFixed(1) + "s" },
        ]
    }

    // ---- reusable skin pieces --------------------------------------------
    component IconButton: Button {
        property color fg: Theme.textPrimary
        flat: true
        hoverEnabled: true
        implicitWidth: Theme.iconButton
        implicitHeight: Theme.iconButton
        font.pixelSize: 18
        background: Rectangle {
            radius: Theme.radius
            color: parent.down ? Theme.elevated
                               : (parent.hovered && parent.enabled ? Theme.surfaceHover : "transparent")
        }
        contentItem: Text {
            text: parent.text
            font: parent.font
            color: parent.enabled ? parent.fg : Theme.textDisabled
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component DarkMenu: Menu {
        implicitWidth: 240
        padding: 4
        background: Rectangle {
            color: Theme.surface
            radius: Theme.radius
            border.color: Theme.divider
            border.width: 1
        }
    }

    component DarkMenuItem: MenuItem {
        id: dmi
        implicitHeight: 38
        contentItem: Text {
            leftPadding: 10
            rightPadding: 10
            text: dmi.text
            font.pixelSize: Theme.fontNormal
            color: dmi.enabled ? Theme.textPrimary : Theme.textDisabled
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: Theme.radius - 2
            color: dmi.highlighted ? Theme.surfaceHover : "transparent"
        }
    }

    // A row in the settings popover: label on the left, current value on the right.
    component SettingRow: ItemDelegate {
        id: sr
        property string label: ""
        property string value: ""
        hoverEnabled: true
        implicitHeight: 44
        Layout.fillWidth: true
        contentItem: RowLayout {
            spacing: Theme.spacingSmall
            Text {
                text: sr.label
                color: sr.enabled ? Theme.textPrimary : Theme.textDisabled
                font.pixelSize: Theme.fontNormal
                verticalAlignment: Text.AlignVCenter
                Layout.fillWidth: true
                Layout.leftMargin: 6
            }
            Text {
                text: sr.value
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSmall
                visible: text.length > 0
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                text: "›" // ›
                color: Theme.textSecondary
                font.pixelSize: Theme.fontMedium
                visible: sr.enabled && sr.value.length === 0 && sr.action === null
                Layout.rightMargin: 6
            }
        }
        background: Rectangle {
            radius: Theme.radius
            color: sr.hovered && sr.enabled ? Theme.surfaceHover : "transparent"
        }
    }

    // ---- top scrim + bar --------------------------------------------------
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 90
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.scrimTop }
            GradientStop { position: 1.0; color: Theme.transparent }
        }
    }
    RowLayout {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.margins: Theme.spacing
        spacing: Theme.spacingSmall

        IconButton { text: "←"; onClicked: root.back() } // ←
        Label {
            text: root.title
            color: Theme.textPrimary
            font.pixelSize: Theme.fontLarge
            font.bold: true
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingSmall
        }
        IconButton { text: "\u{1F465}"; enabled: Features.syncPlay } // 👥 SyncPlay (stub)
        IconButton { text: "\u{1F4FA}"; enabled: Features.cast }     // 📺 Cast (stub)
    }

    // ---- bottom scrim + bar ----------------------------------------------
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 150
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.transparent }
            GradientStop { position: 1.0; color: Theme.scrimBottom }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingLarge
            anchors.rightMargin: Theme.spacingLarge
            anchors.topMargin: Theme.spacing
            anchors.bottomMargin: Theme.spacingSmall
            spacing: Theme.spacingSmall

            // --- scrubber row ---
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing

                Label { text: root.fmt(root.player.position); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall }

                Slider {
                    id: scrubber
                    Layout.fillWidth: true
                    from: 0
                    to: Math.max(1, root.player.duration)
                    property bool seeking: false

                    background: Rectangle {
                        x: scrubber.leftPadding
                        y: scrubber.topPadding + scrubber.availableHeight / 2 - height / 2
                        width: scrubber.availableWidth
                        height: 5
                        radius: 3
                        color: Theme.divider
                        Rectangle {
                            width: scrubber.visualPosition * parent.width
                            height: parent.height
                            radius: 3
                            color: Theme.accent
                        }
                        // chapter ticks
                        Repeater {
                            model: root.player.chapters
                            Rectangle {
                                visible: root.player.duration > 0
                                width: 2
                                height: 9
                                radius: 1
                                y: parent.height / 2 - height / 2
                                x: Math.min(parent.width - width,
                                            (modelData.time / Math.max(1, root.player.duration)) * parent.width)
                                color: "#ccffffff"
                            }
                        }
                    }
                    handle: Rectangle {
                        x: scrubber.leftPadding + scrubber.visualPosition * (scrubber.availableWidth - width)
                        y: scrubber.topPadding + scrubber.availableHeight / 2 - height / 2
                        implicitWidth: 14
                        implicitHeight: 14
                        radius: 7
                        color: Theme.accent
                        border.color: Theme.accentText
                        border.width: scrubber.pressed ? 2 : 0
                    }

                    onPressedChanged: {
                        if (pressed) {
                            seeking = true
                        } else {
                            root.player.seek(value)
                            seeking = false
                        }
                    }
                    Binding {
                        target: scrubber
                        property: "value"
                        value: root.player.position
                        when: !scrubber.seeking
                    }
                }

                Label { text: root.fmt(root.player.duration); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall }
            }

            // --- control row ---
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingTiny

                IconButton { text: "⏮"; enabled: Features.playQueue }                 // ⏮ previous (stub)
                IconButton { text: "⏪"; onClicked: root.player.skip(-10) }            // ⏪ back 10s
                IconButton {
                    text: root.player.paused ? "▶" : "⏸"                          // ▶ / ⏸
                    font.pixelSize: 22
                    onClicked: root.player.setPaused(!root.player.paused)
                }
                IconButton { text: "⏩"; onClicked: root.player.skip(30) }             // ⏩ forward 30s
                IconButton { text: "⏭"; enabled: Features.playQueue }                 // ⏭ next (stub)

                Label {
                    text: qsTr("Ends at %1").arg(root.endsAt())
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSmall
                    Layout.leftMargin: Theme.spacingSmall
                    verticalAlignment: Text.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                // favorite
                IconButton {
                    text: root.favorite ? "♥" : "♡"                               // ♥ / ♡
                    fg: root.favorite ? Theme.accent : Theme.textPrimary
                    onClicked: root.toggleFavorite()
                }

                // subtitle track menu
                IconButton {
                    text: "CC"
                    font.pixelSize: Theme.fontSmall
                    onClicked: subtitleMenu.popup()
                    DarkMenu {
                        id: subtitleMenu
                        DarkMenuItem {
                            text: qsTr("Subtitles off")
                            onTriggered: root.player.setSubtitleTrack(-1)
                        }
                        Instantiator {
                            model: root.player.subtitleTracks
                            delegate: DarkMenuItem {
                                required property var modelData
                                text: (modelData.selected ? "✓ " : "    ") + modelData.label
                                onTriggered: root.player.setSubtitleTrack(modelData.id)
                            }
                            onObjectAdded: (index, object) => subtitleMenu.insertItem(index + 1, object)
                            onObjectRemoved: (index, object) => subtitleMenu.removeItem(object)
                        }
                    }
                }

                // audio track menu
                IconButton {
                    text: "\u{1F3A7}" // 🎧
                    onClicked: audioMenu.popup()
                    DarkMenu {
                        id: audioMenu
                        Instantiator {
                            model: root.player.audioTracks
                            delegate: DarkMenuItem {
                                required property var modelData
                                text: (modelData.selected ? "✓ " : "    ") + modelData.label
                                onTriggered: root.player.setAudioTrack(modelData.id)
                            }
                            onObjectAdded: (index, object) => audioMenu.insertItem(index, object)
                            onObjectRemoved: (index, object) => audioMenu.removeItem(object)
                        }
                    }
                }

                // volume
                IconButton {
                    text: root.player.muted ? "\u{1F507}" : "\u{1F50A}"                     // 🔇 / 🔊
                    onClicked: root.player.setMuted(!root.player.muted)
                }
                Slider {
                    id: volume
                    Layout.preferredWidth: 100
                    from: 0
                    to: 100
                    value: root.player.volume
                    onMoved: root.player.setVolume(value)
                    background: Rectangle {
                        x: volume.leftPadding
                        y: volume.topPadding + volume.availableHeight / 2 - height / 2
                        width: volume.availableWidth
                        height: 4
                        radius: 2
                        color: Theme.divider
                        Rectangle {
                            width: volume.visualPosition * parent.width
                            height: parent.height
                            radius: 2
                            color: Theme.accent
                        }
                    }
                    handle: Rectangle {
                        x: volume.leftPadding + volume.visualPosition * (volume.availableWidth - width)
                        y: volume.topPadding + volume.availableHeight / 2 - height / 2
                        implicitWidth: 12
                        implicitHeight: 12
                        radius: 6
                        color: Theme.accent
                    }
                }

                // settings
                IconButton {
                    id: gearBtn
                    text: "⚙" // ⚙
                    onClicked: settingsMenu.opened ? settingsMenu.close() : settingsMenu.open()

                    Popup {
                        id: settingsMenu
                        width: 280
                        padding: 6
                        x: gearBtn.width - width
                        y: -height - Theme.spacingSmall
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                        background: Rectangle {
                            color: Theme.surface
                            radius: Theme.radius
                            border.color: Theme.divider
                            border.width: 1
                        }
                        property int page: 0
                        onOpened: page = 0

                        contentItem: StackLayout {
                            currentIndex: settingsMenu.page

                            // page 0 — main
                            ColumnLayout {
                                spacing: 2
                                SettingRow {
                                    label: qsTr("Aspect Ratio"); value: root.aspectMode
                                    onClicked: settingsMenu.page = 1
                                }
                                SettingRow {
                                    label: qsTr("Playback Speed"); value: root.fmtSpeed(root.player.speed)
                                    onClicked: settingsMenu.page = 2
                                }
                                SettingRow {
                                    label: qsTr("Quality"); value: qsTr("Auto")
                                    enabled: Features.transcodeQuality
                                }
                                SettingRow {
                                    label: qsTr("Repeat Mode"); value: qsTr("None")
                                    enabled: Features.playQueue
                                }
                                SettingRow {
                                    label: qsTr("Subtitle Settings")
                                    onClicked: settingsMenu.page = 3
                                }
                                SettingRow {
                                    label: qsTr("Playback Info")
                                    onClicked: { root.statsVisible = !root.statsVisible; settingsMenu.close() }
                                }
                            }

                            // page 1 — aspect ratio
                            ColumnLayout {
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    IconButton { text: "←"; implicitWidth: 36; implicitHeight: 36; onClicked: settingsMenu.page = 0 }
                                    Label { text: qsTr("Aspect Ratio"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.fillWidth: true }
                                }
                                Repeater {
                                    model: ["Auto", "Cover", "Fill"]
                                    SettingRow {
                                        label: modelData
                                        value: root.aspectMode === modelData ? "✓" : ""
                                        onClicked: { root.applyAspect(modelData); settingsMenu.page = 0 }
                                    }
                                }
                            }

                            // page 2 — playback speed
                            ColumnLayout {
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    IconButton { text: "←"; implicitWidth: 36; implicitHeight: 36; onClicked: settingsMenu.page = 0 }
                                    Label { text: qsTr("Playback Speed"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.fillWidth: true }
                                }
                                Repeater {
                                    model: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                                    SettingRow {
                                        label: root.fmtSpeed(modelData)
                                        value: Math.abs(root.player.speed - modelData) < 0.01 ? "✓" : ""
                                        onClicked: { root.player.setSpeed(modelData); settingsMenu.page = 0 }
                                    }
                                }
                            }

                            // page 3 — subtitle settings
                            ColumnLayout {
                                spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    IconButton { text: "←"; implicitWidth: 36; implicitHeight: 36; onClicked: settingsMenu.page = 0 }
                                    Label { text: qsTr("Subtitle Settings"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.fillWidth: true }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: qsTr("Subtitle delay"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 6 }
                                    IconButton { text: "−"; implicitWidth: 34; implicitHeight: 34; onClicked: root.player.setSubDelay(root.player.subDelay - 0.1) }
                                    Label { text: root.player.subDelay.toFixed(1) + "s"; color: Theme.textSecondary; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 52 }
                                    IconButton { text: "+"; implicitWidth: 34; implicitHeight: 34; onClicked: root.player.setSubDelay(root.player.subDelay + 0.1) }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: qsTr("Subtitle size"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 6 }
                                    IconButton { text: "−"; implicitWidth: 34; implicitHeight: 34; onClicked: { root.subScale = Math.max(0.25, root.subScale - 0.1); root.player.setOption("sub-scale", root.subScale.toFixed(2)) } }
                                    Label { text: Math.round(root.subScale * 100) + "%"; color: Theme.textSecondary; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 52 }
                                    IconButton { text: "+"; implicitWidth: 34; implicitHeight: 34; onClicked: { root.subScale = Math.min(4.0, root.subScale + 0.1); root.player.setOption("sub-scale", root.subScale.toFixed(2)) } }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: qsTr("Audio delay"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 6 }
                                    IconButton { text: "−"; implicitWidth: 34; implicitHeight: 34; onClicked: root.player.setAudioDelay(root.player.audioDelay - 0.1) }
                                    Label { text: root.player.audioDelay.toFixed(1) + "s"; color: Theme.textSecondary; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 52 }
                                    IconButton { text: "+"; implicitWidth: 34; implicitHeight: 34; onClicked: root.player.setAudioDelay(root.player.audioDelay + 0.1) }
                                }
                            }
                        }
                    }
                }

                IconButton { text: "⛶"; onClicked: root.toggleFullscreen() } // ⛶
            }
        }
    }

    // ---- playback info (stats) overlay -----------------------------------
    Rectangle {
        visible: root.statsVisible
        anchors { right: parent.right; top: parent.top; topMargin: 80; rightMargin: Theme.spacingLarge }
        width: 320
        height: statsCol.implicitHeight + Theme.spacing * 2
        radius: Theme.radius
        color: "#e6202124"
        border.color: Theme.divider
        border.width: 1

        ColumnLayout {
            id: statsCol
            anchors.fill: parent
            anchors.margins: Theme.spacing
            spacing: Theme.spacingTiny

            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Playback Info"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.fillWidth: true }
                IconButton { text: "✕"; implicitWidth: 28; implicitHeight: 28; font.pixelSize: 14; onClicked: root.statsVisible = false }
            }
            Repeater {
                model: root.statsRows
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: modelData.k; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: 130 }
                    Label { text: modelData.v; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }
        }

        Timer {
            interval: 1000
            repeat: true
            running: root.statsVisible
            triggeredOnStart: true
            onTriggered: root.refreshStats()
        }
    }
}
