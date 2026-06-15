import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// Settings (jellyfin-web style): a left section nav + a content pane. Wired:
// Display (skin), Playback (default quality), Subtitles (size), Player (live
// mpv.conf editor — our "fully configurable mpv" surface), About. Server
// Administration is listed but stubbed (Features.adminDashboard).
Item {
    id: screen
    property var client
    property var config
    property string pageTitle: qsTr("Settings")
    signal logout()

    property int section: 0
    readonly property var sections: [qsTr("Display"), qsTr("Playback"), qsTr("Subtitles"),
                                     qsTr("Player"), qsTr("Administration"), qsTr("About")]
    readonly property var bitrates: [0, 120000000, 60000000, 40000000, 20000000, 10000000,
                                     8000000, 4000000, 2000000, 1000000]

    function fmtBitrate(bps) {
        if (!bps || bps <= 0) return qsTr("Auto (direct play)")
        return (bps >= 1000000) ? ((Math.round(bps / 100000) / 10) + " Mbps") : (Math.round(bps / 1000) + " kbps")
    }

    component SectionTitle: Text {
        color: Theme.textPrimary
        font.pixelSize: Theme.fontLarge
        font.bold: true
        Layout.bottomMargin: Theme.spacingSmall
    }
    component Hint: Text {
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSmall
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
    // a selectable option row (label + check when current)
    component OptionRow: ItemDelegate {
        id: orow
        property bool current: false
        property bool stub: false
        hoverEnabled: true
        Layout.fillWidth: true
        implicitHeight: 42
        enabled: !stub
        contentItem: RowLayout {
            Text { text: orow.text; color: orow.enabled ? Theme.textPrimary : Theme.textDisabled
                   font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 8; verticalAlignment: Text.AlignVCenter }
            Text { text: orow.current ? "✓" : ""; color: Theme.accent; font.pixelSize: Theme.fontMedium; Layout.rightMargin: 10 }
        }
        background: Rectangle { radius: Theme.radius; color: orow.hovered && orow.enabled ? Theme.surfaceHover : "transparent" }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // --- section nav ---
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
                        Layout.fillWidth: true
                        implicitHeight: 44
                        hoverEnabled: true
                        onClicked: screen.section = index
                        contentItem: Text {
                            text: modelData
                            color: screen.section === index ? Theme.accent : Theme.textPrimary
                            font.pixelSize: Theme.fontNormal
                            font.bold: screen.section === index
                            leftPadding: Theme.spacing
                            verticalAlignment: Text.AlignVCenter
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

        // --- content ---
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: screen.section

            // 0 — Display
            Flickable {
                contentHeight: dispCol.implicitHeight + Theme.spacingLarge * 2
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: dispCol
                    width: parent.width - Theme.pagePad * 2
                    x: Theme.pagePad; y: Theme.spacingLarge
                    spacing: Theme.spacingSmall
                    SectionTitle { text: qsTr("Display") }
                    Hint { text: qsTr("Theme — the app is fully skinnable; the default replicates the Jellyfin web layout. More skins coming.") }
                    OptionRow { text: qsTr("Jellyfin Web — Dark"); current: true }
                    OptionRow { text: qsTr("Jellyfin Web — Light"); stub: true }
                }
            }

            // 1 — Playback
            Flickable {
                contentHeight: playCol.implicitHeight + Theme.spacingLarge * 2
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: playCol
                    width: parent.width - Theme.pagePad * 2
                    x: Theme.pagePad; y: Theme.spacingLarge
                    spacing: Theme.spacingSmall
                    SectionTitle { text: qsTr("Playback") }
                    Hint { text: qsTr("Default streaming quality. Auto direct-plays the original file (mpv handles any codec); a cap transcodes on the server. Applies to the next video.") }
                    Repeater {
                        model: screen.bitrates
                        OptionRow {
                            text: screen.fmtBitrate(modelData)
                            current: screen.defaultBitrate === modelData
                            onClicked: { screen.defaultBitrate = modelData; if (screen.config) screen.config.setValue("playback/maxBitrate", modelData) }
                        }
                    }
                }
            }

            // 2 — Subtitles
            Flickable {
                contentHeight: subCol.implicitHeight + Theme.spacingLarge * 2
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: subCol
                    width: parent.width - Theme.pagePad * 2
                    x: Theme.pagePad; y: Theme.spacingLarge
                    spacing: Theme.spacing
                    SectionTitle { text: qsTr("Subtitles") }
                    Hint { text: qsTr("Default subtitle size. You can also adjust delay/size live from the player's settings.") }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: qsTr("Subtitle size"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true }
                        JIconButton { text: "−"; implicitWidth: 36; implicitHeight: 36
                            onClicked: { screen.subScale = Math.max(0.5, screen.subScale - 0.1); if (screen.config) screen.config.setValue("subtitles/scale", screen.subScale) } }
                        Text { text: Math.round(screen.subScale * 100) + "%"
                               color: Theme.textSecondary; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 56 }
                        JIconButton { text: "+"; implicitWidth: 36; implicitHeight: 36
                            onClicked: { screen.subScale = Math.min(3.0, screen.subScale + 0.1); if (screen.config) screen.config.setValue("subtitles/scale", screen.subScale) } }
                    }
                    OptionRow { text: qsTr("Preferred subtitle language"); stub: true }
                    OptionRow { text: qsTr("Burn in subtitles"); stub: true }
                }
            }

            // 3 — Player (mpv.conf editor)
            ColumnLayout {
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: Theme.pagePad
                    Layout.bottomMargin: Theme.spacingSmall
                    spacing: Theme.spacingSmall
                    SectionTitle { text: qsTr("Player (mpv)") }
                    Hint { text: qsTr("Edit mpv.conf directly — hwdec, deinterlace, scaling, shaders, audio output, video-sync, etc. Saved changes apply to the next video.") }
                    Text { text: screen.config ? screen.config.mpvConfPath : ""; color: Theme.textDisabled; font.pixelSize: Theme.fontTiny; font.family: "monospace" }
                }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: Theme.pagePad
                    Layout.rightMargin: Theme.pagePad
                    TextArea {
                        id: mpvEditor
                        color: Theme.textPrimary
                        font.family: "monospace"
                        font.pixelSize: Theme.fontSmall
                        wrapMode: TextEdit.NoWrap
                        selectByMouse: true
                        background: Rectangle { color: Theme.background; border.color: Theme.divider; border.width: 1; radius: Theme.radius }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: Theme.pagePad
                    Layout.topMargin: Theme.spacingSmall
                    Text { id: mpvSaved; text: ""; color: Theme.watched; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; verticalAlignment: Text.AlignVCenter }
                    Button {
                        text: qsTr("Reload")
                        onClicked: { mpvEditor.text = screen.config ? screen.config.readMpvConf() : ""; mpvSaved.text = "" }
                        background: Rectangle { radius: Theme.radius; color: parent.hovered ? Theme.surfaceHover : Theme.surface; border.color: Theme.divider; border.width: 1 }
                        contentItem: Text { text: parent.text; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; leftPadding: 14; rightPadding: 14; verticalAlignment: Text.AlignVCenter }
                    }
                    Button {
                        text: qsTr("Save")
                        onClicked: if (screen.config) mpvSaved.text = screen.config.writeMpvConf(mpvEditor.text) ? qsTr("Saved ✓") : qsTr("Save failed")
                        background: Rectangle { radius: Theme.radius; color: parent.hovered ? Theme.accentHover : Theme.accent }
                        contentItem: Text { text: parent.text; color: Theme.accentText; font.pixelSize: Theme.fontNormal; font.bold: true; leftPadding: 16; rightPadding: 16; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }

            // 4 — Administration (stub — present, matches web nav)
            Flickable {
                contentHeight: admCol.implicitHeight + Theme.spacingLarge * 2
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: admCol
                    width: parent.width - Theme.pagePad * 2
                    x: Theme.pagePad; y: Theme.spacingLarge
                    spacing: 2
                    SectionTitle { text: qsTr("Administration") }
                    Hint { text: qsTr("Server administration. Native dashboard panels are not built yet — use the web dashboard for now.") }
                    Item { Layout.preferredHeight: Theme.spacingSmall }
                    Repeater {
                        model: [qsTr("Dashboard"), qsTr("Users"), qsTr("Libraries"), qsTr("Playback / Transcoding"),
                                qsTr("Plugins"), qsTr("Scheduled Tasks"), qsTr("Logs"), qsTr("API Keys"), qsTr("Networking")]
                        OptionRow { text: modelData; stub: true }
                    }
                }
            }

            // 5 — About
            Flickable {
                contentHeight: aboutCol.implicitHeight + Theme.spacingLarge * 2
                clip: true
                ColumnLayout {
                    id: aboutCol
                    width: parent.width - Theme.pagePad * 2
                    x: Theme.pagePad; y: Theme.spacingLarge
                    spacing: Theme.spacingSmall
                    SectionTitle { text: qsTr("About") }
                    Text { text: qsTr("Jellyfin Desktop"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true }
                    Text { text: qsTr("Version %1").arg(screen.config ? screen.config.version : ""); color: Theme.textSecondary; font.pixelSize: Theme.fontNormal }
                    Text { text: qsTr("Native C++ / Qt6 / libmpv — no web engine, no SDKs."); color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
                    Item { Layout.preferredHeight: Theme.spacing }
                    Text { text: qsTr("Server: %1").arg(screen.client ? screen.client.serverUrl : ""); color: Theme.textSecondary; font.pixelSize: Theme.fontNormal }
                    Text { text: qsTr("Signed in as %1").arg(screen.client ? screen.client.userName : ""); color: Theme.textSecondary; font.pixelSize: Theme.fontNormal }
                    Item { Layout.preferredHeight: Theme.spacing }
                    Button {
                        text: qsTr("Log out")
                        onClicked: screen.logout()
                        background: Rectangle { radius: Theme.radius; color: parent.hovered ? Theme.surfaceHover : Theme.surface; border.color: Theme.divider; border.width: 1 }
                        contentItem: Text { text: parent.text; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8 }
                    }
                }
            }
        }
    }

    // Reactive copies of the persisted prefs (config.value isn't bindable).
    property int defaultBitrate: 0
    property real subScale: 1.0

    Component.onCompleted: {
        if (config) {
            defaultBitrate = config.value("playback/maxBitrate", 0)
            subScale = config.value("subtitles/scale", 1.0)
            mpvEditor.text = config.readMpvConf()
        }
    }
}
