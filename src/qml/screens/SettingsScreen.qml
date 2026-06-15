import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// Settings (jellyfin-web layout: section nav + content pane). Sections mirror
// the web client. Wired: Profile (password), Home (row visibility), Playback
// (default quality, auto-play-next, skip intervals), Subtitles (size/position),
// Player (live mpv.conf editor). Stubbed (present, disabled): Display extras,
// Quick Connect, Administration, language/passthrough/etc.
Item {
    id: screen
    property var client
    property var config
    property string pageTitle: qsTr("Settings")
    signal logout()

    property int section: 0
    readonly property var sections: [qsTr("Profile"), qsTr("Display"), qsTr("Home"), qsTr("Playback"),
                                     qsTr("Subtitles"), qsTr("Controls"), qsTr("Player"),
                                     qsTr("Quick Connect"), qsTr("About")]
    readonly property var bitrates: [0, 120000000, 60000000, 40000000, 20000000, 10000000, 8000000, 4000000, 2000000, 1000000]

    // reactive copies of persisted prefs
    property int defaultBitrate: 0
    property real subScale: 1.0
    property int subPos: 100
    property bool autoPlayNext: true
    property int skipBack: 10
    property int skipForward: 30
    property bool homeContinue: true
    property bool homeNextUp: true
    property bool homeLatest: true

    function pref(key, def) { return config ? config.value(key, def) : def }
    function setPref(key, v) { if (config) config.setValue(key, v) }
    function fmtBitrate(bps) {
        if (!bps || bps <= 0) return qsTr("Auto (direct play)")
        return (bps >= 1000000) ? ((Math.round(bps / 100000) / 10) + " Mbps") : (Math.round(bps / 1000) + " kbps")
    }

    Component.onCompleted: {
        defaultBitrate = pref("playback/maxBitrate", 0)
        subScale = pref("subtitles/scale", 1.0)
        subPos = pref("subtitles/pos", 100)
        autoPlayNext = pref("playback/autoPlayNext", true)
        skipBack = pref("playback/skipBack", 10)
        skipForward = pref("playback/skipForward", 30)
        homeContinue = pref("home/continueWatching", true)
        homeNextUp = pref("home/nextUp", true)
        homeLatest = pref("home/latest", true)
        mpvEditor.text = config ? config.readMpvConf() : ""
    }

    // ---- reusable bits ----
    component SectionTitle: Text {
        color: Theme.textPrimary; font.pixelSize: Theme.fontLarge; font.bold: true
        Layout.bottomMargin: Theme.spacingSmall
    }
    component Hint: Text {
        color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    component OptionRow: ItemDelegate {
        id: orow
        property bool current: false
        property bool stub: false
        hoverEnabled: true; Layout.fillWidth: true; implicitHeight: 42; enabled: !stub
        contentItem: RowLayout {
            Text { text: orow.text; color: orow.enabled ? Theme.textPrimary : Theme.textDisabled; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 8; verticalAlignment: Text.AlignVCenter }
            Text { text: orow.current ? "✓" : ""; color: Theme.accent; font.pixelSize: Theme.fontMedium; Layout.rightMargin: 10 }
        }
        background: Rectangle { radius: Theme.radius; color: orow.hovered && orow.enabled ? Theme.surfaceHover : "transparent" }
    }
    component ToggleRow: ItemDelegate {
        id: tr
        property string label: ""
        property bool on: false
        property bool stub: false
        signal toggled(bool value)
        hoverEnabled: true; Layout.fillWidth: true; implicitHeight: 46; enabled: !stub
        onClicked: if (!stub) tr.toggled(!tr.on)
        contentItem: RowLayout {
            Text { text: tr.label; color: tr.enabled ? Theme.textPrimary : Theme.textDisabled; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 8; verticalAlignment: Text.AlignVCenter }
            Rectangle {
                Layout.rightMargin: 10
                width: 44; height: 24; radius: 12
                color: tr.on && tr.enabled ? Theme.accent : Theme.elevated
                Rectangle { width: 18; height: 18; radius: 9; y: 3; color: Theme.textPrimary
                    x: tr.on ? 23 : 3; Behavior on x { NumberAnimation { duration: 120 } } }
            }
        }
        background: Rectangle { radius: Theme.radius; color: tr.hovered && tr.enabled ? Theme.surfaceHover : "transparent" }
    }
    component StepperRow: RowLayout {
        id: sr
        property string label: ""
        property int value: 0
        property int step: 5
        property int minValue: 0
        property int maxValue: 600
        property string suffix: "s"
        signal changed(int v)
        Layout.fillWidth: true
        Text { text: sr.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 8; verticalAlignment: Text.AlignVCenter }
        JIconButton { text: "−"; implicitWidth: 36; implicitHeight: 36; onClicked: sr.changed(Math.max(sr.minValue, sr.value - sr.step)) }
        Text { text: sr.value + sr.suffix; color: Theme.textSecondary; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 56 }
        JIconButton { text: "+"; implicitWidth: 36; implicitHeight: 36; onClicked: sr.changed(Math.min(sr.maxValue, sr.value + sr.step)) }
    }
    component PanelButton: Button {
        property bool primary: false
        hoverEnabled: true; implicitHeight: Theme.controlHeight
        background: Rectangle {
            radius: Theme.radius
            color: parent.primary ? (parent.hovered ? Theme.accentHover : Theme.accent) : (parent.hovered ? Theme.surfaceHover : Theme.surface)
            border.color: parent.primary ? Theme.transparent : Theme.divider; border.width: parent.primary ? 0 : 1
        }
        contentItem: Text { text: parent.text; color: parent.primary ? Theme.accentText : Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: parent.primary; leftPadding: 16; rightPadding: 16; verticalAlignment: Text.AlignVCenter }
    }
    component Field: TextField {
        Layout.fillWidth: true
        color: Theme.textPrimary
        placeholderTextColor: Theme.textDisabled
        font.pixelSize: Theme.fontNormal
        background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: Theme.controlHeight }
    }

    // helper: a scrollable padded column panel
    component Panel: Flickable {
        default property alias content: inner.data
        contentWidth: width
        contentHeight: inner.implicitHeight + Theme.spacingLarge * 2
        clip: true
        ScrollBar.vertical: ScrollBar {}
        ColumnLayout {
            id: inner
            width: parent.width - Theme.pagePad * 2
            x: Theme.pagePad
            y: Theme.spacingLarge
            spacing: Theme.spacingSmall
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // section nav
        Rectangle {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            color: Theme.backgroundAlt
            ColumnLayout {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.topMargin: Theme.spacing
                spacing: 2
                Repeater {
                    model: screen.sections
                    ItemDelegate {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: 44; hoverEnabled: true
                        onClicked: screen.section = index
                        contentItem: Text {
                            text: modelData
                            color: screen.section === index ? Theme.accent : Theme.textPrimary
                            font.pixelSize: Theme.fontNormal; font.bold: screen.section === index
                            leftPadding: Theme.spacing; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.hovered ? Theme.surfaceHover : "transparent"
                            Rectangle { width: 3; height: parent.height; color: Theme.accent; visible: screen.section === index }
                        }
                    }
                }
            }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.divider }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: screen.section

            // 0 — Profile
            Panel {
                SectionTitle { text: qsTr("Profile") }
                Text { text: screen.client ? screen.client.userName : ""; color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true }
                Text { text: qsTr("Server: %1").arg(screen.client ? screen.client.serverUrl : ""); color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
                Item { Layout.preferredHeight: Theme.spacing }
                Text { text: qsTr("Change password"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true }
                Field { id: curPw; placeholderText: qsTr("Current password"); echoMode: TextInput.Password }
                Field { id: newPw; placeholderText: qsTr("New password"); echoMode: TextInput.Password }
                RowLayout {
                    Layout.topMargin: Theme.spacingSmall
                    Text { id: pwResult; text: ""; color: Theme.watched; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; verticalAlignment: Text.AlignVCenter }
                    PanelButton { primary: true; text: qsTr("Update password"); onClicked: if (screen.client) screen.client.changePassword(curPw.text, newPw.text) }
                }
                Connections {
                    target: screen.client
                    function onPasswordChanged(ok, message) { pwResult.text = message; pwResult.color = ok ? Theme.watched : Theme.error; if (ok) { curPw.clear(); newPw.clear() } }
                }
            }

            // 1 — Display
            Panel {
                SectionTitle { text: qsTr("Display") }
                Hint { text: qsTr("Theme — the app is fully skinnable; the default replicates the Jellyfin web layout. More skins coming.") }
                OptionRow { text: qsTr("Jellyfin Web — Dark"); current: true }
                OptionRow { text: qsTr("Jellyfin Web — Light"); stub: true }
                Item { Layout.preferredHeight: Theme.spacing }
                OptionRow { text: qsTr("Language"); stub: true }
                OptionRow { text: qsTr("Show backdrops"); stub: true }
                OptionRow { text: qsTr("Enable cinema mode"); stub: true }
            }

            // 2 — Home
            Panel {
                SectionTitle { text: qsTr("Home") }
                Hint { text: qsTr("Which rows appear on the home screen. Applies on next launch.") }
                ToggleRow { label: qsTr("Continue Watching"); on: screen.homeContinue; onToggled: (v) => { screen.homeContinue = v; screen.setPref("home/continueWatching", v) } }
                ToggleRow { label: qsTr("Next Up"); on: screen.homeNextUp; onToggled: (v) => { screen.homeNextUp = v; screen.setPref("home/nextUp", v) } }
                ToggleRow { label: qsTr("Latest media"); on: screen.homeLatest; onToggled: (v) => { screen.homeLatest = v; screen.setPref("home/latest", v) } }
            }

            // 3 — Playback
            Panel {
                SectionTitle { text: qsTr("Playback") }
                Hint { text: qsTr("Default streaming quality. Auto direct-plays the original file; a cap transcodes on the server. Applies to the next video.") }
                Repeater {
                    model: screen.bitrates
                    OptionRow {
                        text: screen.fmtBitrate(modelData)
                        current: screen.defaultBitrate === modelData
                        onClicked: { screen.defaultBitrate = modelData; screen.setPref("playback/maxBitrate", modelData) }
                    }
                }
                Item { Layout.preferredHeight: Theme.spacing }
                ToggleRow { label: qsTr("Play next episode automatically"); on: screen.autoPlayNext; onToggled: (v) => { screen.autoPlayNext = v; screen.setPref("playback/autoPlayNext", v) } }
                StepperRow { label: qsTr("Skip back interval"); value: screen.skipBack; step: 5; minValue: 5; maxValue: 120; onChanged: (v) => { screen.skipBack = v; screen.setPref("playback/skipBack", v) } }
                StepperRow { label: qsTr("Skip forward interval"); value: screen.skipForward; step: 5; minValue: 5; maxValue: 120; onChanged: (v) => { screen.skipForward = v; screen.setPref("playback/skipForward", v) } }
                Item { Layout.preferredHeight: Theme.spacing }
                OptionRow { text: qsTr("Preferred audio language"); stub: true }
                OptionRow { text: qsTr("Allow audio passthrough"); stub: true }
            }

            // 4 — Subtitles
            Panel {
                SectionTitle { text: qsTr("Subtitles") }
                Hint { text: qsTr("Defaults applied when a video starts; you can also adjust live from the player.") }
                StepperRow { label: qsTr("Subtitle size"); value: Math.round(screen.subScale * 100); step: 10; minValue: 50; maxValue: 300; suffix: "%"; onChanged: (v) => { screen.subScale = v / 100; screen.setPref("subtitles/scale", screen.subScale) } }
                StepperRow { label: qsTr("Subtitle position"); value: screen.subPos; step: 5; minValue: 0; maxValue: 150; suffix: ""; onChanged: (v) => { screen.subPos = v; screen.setPref("subtitles/pos", v) } }
                Item { Layout.preferredHeight: Theme.spacing }
                OptionRow { text: qsTr("Subtitle mode"); stub: true }
                OptionRow { text: qsTr("Preferred subtitle language"); stub: true }
                OptionRow { text: qsTr("Burn in subtitles"); stub: true }
            }

            // 5 — Controls (keyboard) — stub
            Panel {
                SectionTitle { text: qsTr("Controls") }
                Hint { text: qsTr("Keyboard & remote shortcuts. Customisation isn't wired yet.") }
                OptionRow { text: qsTr("Space — Play / Pause"); stub: true }
                OptionRow { text: qsTr("Left / Right — Skip"); stub: true }
                OptionRow { text: qsTr("F — Fullscreen"); stub: true }
                OptionRow { text: qsTr("Customise shortcuts"); stub: true }
            }

            // 6 — Player (mpv.conf)
            ColumnLayout {
                ColumnLayout {
                    Layout.fillWidth: true; Layout.margins: Theme.pagePad; Layout.bottomMargin: Theme.spacingSmall; spacing: Theme.spacingSmall
                    SectionTitle { text: qsTr("Player (mpv)") }
                    Hint { text: qsTr("Edit mpv.conf directly — hwdec, deinterlace, scaling, shaders, audio output, video-sync, etc. Saved changes apply to the next video.") }
                    Text { text: screen.config ? screen.config.mpvConfPath : ""; color: Theme.textDisabled; font.pixelSize: Theme.fontTiny; font.family: "monospace" }
                }
                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.leftMargin: Theme.pagePad; Layout.rightMargin: Theme.pagePad
                    TextArea {
                        id: mpvEditor
                        color: Theme.textPrimary; font.family: "monospace"; font.pixelSize: Theme.fontSmall
                        wrapMode: TextEdit.NoWrap; selectByMouse: true
                        background: Rectangle { color: Theme.background; border.color: Theme.divider; border.width: 1; radius: Theme.radius }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.margins: Theme.pagePad; Layout.topMargin: Theme.spacingSmall
                    Text { id: mpvSaved; text: ""; color: Theme.watched; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; verticalAlignment: Text.AlignVCenter }
                    PanelButton { text: qsTr("Reload"); onClicked: { mpvEditor.text = screen.config ? screen.config.readMpvConf() : ""; mpvSaved.text = "" } }
                    PanelButton { primary: true; text: qsTr("Save"); onClicked: if (screen.config) mpvSaved.text = screen.config.writeMpvConf(mpvEditor.text) ? qsTr("Saved ✓") : qsTr("Save failed") }
                }
            }

            // 6 — Quick Connect
            Panel {
                SectionTitle { text: qsTr("Quick Connect") }
                Hint { text: qsTr("Authorize a sign-in code from another device. Not implemented yet.") }
                Field { placeholderText: qsTr("Quick Connect code"); enabled: false }
                PanelButton { text: qsTr("Authorize"); enabled: false }
            }

            // 8 — About
            Panel {
                SectionTitle { text: qsTr("About") }
                Text { text: qsTr("Jellyfin Desktop"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true }
                Text { text: qsTr("Version %1").arg(screen.config ? screen.config.version : ""); color: Theme.textSecondary; font.pixelSize: Theme.fontNormal }
                Text { text: qsTr("Native C++ / Qt6 / libmpv — no web engine, no SDKs."); color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
                Item { Layout.preferredHeight: Theme.spacing }
                PanelButton { text: qsTr("Log out"); onClicked: screen.logout() }
            }
        }
    }
}
