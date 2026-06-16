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
    property string subStyle: "auto"
    property bool subBold: false
    property string subFont: ""
    property string subColor: "#FFFFFF"
    property string subEdge: "outline"
    property var audioLangs: []   // [{value, text}] built from /Localization/Cultures
    property var subLangs: []
    readonly property var bitrateOptions: bitrates.map(b => ({value: b, text: fmtBitrate(b)}))
    readonly property var segmentActions: [{value: "None", text: qsTr("None")}, {value: "AskToSkip", text: qsTr("Ask to skip")}, {value: "Skip", text: qsTr("Skip automatically")}]
    property bool autoPlayNext: true
    property int skipBack: 10
    property int skipForward: 30
    property bool homeContinue: true
    property bool homeNextUp: true
    property bool homeLatest: true

    property int prefRev: 0   // bump so pref()/prefBool()-bound controls re-evaluate
    function pref(key, def) { prefRev; return config ? config.value(key, def) : def }
    function setPref(key, v) { if (config) { config.setValue(key, v); prefRev++ } }
    function prefBool(key, def) { const v = pref(key, def); return v === true || v === "true" || v === 1 || v === "1" }
    // read a field of the server-side user Configuration (null/absent → default)
    function cfg(key, def) {
        const c = (client && client.userConfig) ? client.userConfig : ({})
        const v = c[key]
        return (v === undefined || v === null) ? def : v
    }
    function buildLangModels(cultures) {
        const audio = [{value: "", text: qsTr("Any language")}, {value: "OriginalLanguage", text: qsTr("Play in original language")}]
        const sub = [{value: "", text: qsTr("Any language")}]
        for (var i = 0; i < cultures.length; i++) {
            const code = cultures[i].ThreeLetterISOLanguageName
            if (!code) continue
            const name = cultures[i].DisplayName || cultures[i].Name || code
            audio.push({value: code, text: name}); sub.push({value: code, text: name})
        }
        screen.audioLangs = audio; screen.subLangs = sub
    }
    function fmtBitrate(bps) {
        if (!bps || bps <= 0) return qsTr("Auto (direct play)")
        return (bps >= 1000000) ? ((Math.round(bps / 100000) / 10) + " Mbps") : (Math.round(bps / 1000) + " kbps")
    }

    Component.onCompleted: {
        defaultBitrate = pref("playback/maxBitrate", 0)
        subScale = pref("subtitles/scale", 1.0)
        subPos = pref("subtitles/pos", 100)
        subStyle = pref("subtitles/styleMode", "auto")
        subBold = prefBool("subtitles/bold", false)
        subFont = pref("subtitles/font", "")
        subColor = pref("subtitles/color", "#FFFFFF")
        subEdge = pref("subtitles/edge", "outline")
        autoPlayNext = pref("playback/autoPlayNext", true)
        skipBack = pref("playback/skipBack", 10)
        skipForward = pref("playback/skipForward", 30)
        homeContinue = pref("home/continueWatching", true)
        homeNextUp = pref("home/nextUp", true)
        homeLatest = pref("home/latest", true)
        mpvEditor.text = config ? config.readMpvConf() : ""
        if (client && client.authenticated) {
            client.fetchUserConfig()
            client.getJson("/Localization/Cultures", "settings:cultures")
        }
    }

    Connections {
        target: screen.client
        function onJsonReady(tag, data) { if (tag === "settings:cultures" && data) screen.buildLangModels(data) }
    }

    // ---- reusable bits ----
    component SectionTitle: Text {
        color: Theme.textPrimary; font.pixelSize: Theme.fontLarge; font.bold: true
        Layout.bottomMargin: Theme.spacingSmall
    }
    component Hint: Text {
        color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    component GroupLabel: Text {
        color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true
        Layout.topMargin: Theme.spacing; Layout.leftMargin: 8; Layout.bottomMargin: 2
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
        signal switched(bool value)
        hoverEnabled: true; Layout.fillWidth: true; implicitHeight: 46; enabled: !stub
        onClicked: if (!stub) tr.switched(!tr.on)
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
    // a compact segmented selector: label + a pill per option, the current one filled
    component ChoiceRow: RowLayout {
        id: chrow
        property string label: ""
        property var options: []        // [{value, text}]
        property var value
        signal picked(var value)
        Layout.fillWidth: true
        spacing: Theme.spacingSmall
        Text { text: chrow.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 8; verticalAlignment: Text.AlignVCenter }
        Repeater {
            model: chrow.options
            Button {
                id: pill
                required property var modelData
                text: modelData.text
                hoverEnabled: true; implicitHeight: 32
                readonly property bool sel: chrow.value === modelData.value
                background: Rectangle {
                    radius: Theme.radius
                    color: pill.sel ? Theme.accent : (pill.hovered ? Theme.surfaceHover : Theme.surface)
                    border.color: pill.sel ? Theme.transparent : Theme.divider; border.width: 1
                }
                contentItem: Text {
                    text: pill.text; color: pill.sel ? Theme.accentText : Theme.textPrimary
                    font.pixelSize: Theme.fontSmall; leftPadding: 12; rightPadding: 12
                    verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                }
                onClicked: chrow.picked(modelData.value)
            }
        }
    }
    // a label + a row of selectable color swatches
    component SwatchRow: RowLayout {
        id: swrow
        property string label: ""
        property var options: []        // [{value, color}]
        property var value
        signal picked(var value)
        Layout.fillWidth: true
        spacing: Theme.spacingSmall
        Text { text: swrow.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 8; verticalAlignment: Text.AlignVCenter }
        Repeater {
            model: swrow.options
            Rectangle {
                required property var modelData
                readonly property bool sel: swrow.value === modelData.value
                width: 30; height: 30; radius: 6
                color: modelData.color
                border.color: sel ? Theme.accent : Theme.divider; border.width: sel ? 3 : 1
                TapHandler { onTapped: swrow.picked(modelData.value) }
            }
        }
    }
    // a themed dropdown for long lists (languages, etc.)
    component ComboRow: RowLayout {
        id: cr
        property string label: ""
        property var options: []        // [{value, text}]
        property var value: ""
        signal picked(var value)
        function syncIndex() {
            for (var i = 0; i < options.length; i++) if (String(options[i].value) === String(cr.value)) { combo.currentIndex = i; return }
            combo.currentIndex = -1
        }
        onValueChanged: syncIndex()
        onOptionsChanged: syncIndex()
        Layout.fillWidth: true
        Text { text: cr.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 8; verticalAlignment: Text.AlignVCenter }
        ComboBox {
            id: combo
            Layout.preferredWidth: 280
            implicitHeight: 36
            model: cr.options
            textRole: "text"
            Component.onCompleted: cr.syncIndex()
            onActivated: (idx) => cr.picked(cr.options[idx].value)
            background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: combo.activeFocus || combo.hovered ? Theme.accent : Theme.divider; border.width: 1 }
            contentItem: Text { text: combo.currentIndex >= 0 ? combo.displayText : qsTr("—"); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; leftPadding: 10; rightPadding: 26; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            indicator: Text { x: combo.width - width - 10; y: (combo.height - height) / 2; text: "▾"; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
            popup: Popup {
                y: combo.height + 2; width: combo.width
                implicitHeight: Math.min(list.contentHeight + 2, 300); padding: 1
                background: Rectangle { color: Theme.elevated; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
                contentItem: ListView {
                    id: list
                    clip: true
                    model: combo.popup.visible ? combo.delegateModel : null
                    currentIndex: combo.highlightedIndex
                    ScrollBar.vertical: ScrollBar { active: true }
                }
            }
            delegate: ItemDelegate {
                required property var modelData
                required property int index
                width: combo.width; implicitHeight: 32; hoverEnabled: true
                contentItem: Text { text: modelData.text; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; leftPadding: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                background: Rectangle { color: hovered ? Theme.surfaceHover : "transparent" }
            }
        }
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
                ToggleRow { label: qsTr("Continue Watching"); on: screen.homeContinue; onSwitched: (v) => { screen.homeContinue = v; screen.setPref("home/continueWatching", v) } }
                ToggleRow { label: qsTr("Next Up"); on: screen.homeNextUp; onSwitched: (v) => { screen.homeNextUp = v; screen.setPref("home/nextUp", v) } }
                ToggleRow { label: qsTr("Latest media"); on: screen.homeLatest; onSwitched: (v) => { screen.homeLatest = v; screen.setPref("home/latest", v) } }
            }

            // 3 — Playback
            Panel {
                SectionTitle { text: qsTr("Playback") }

                GroupLabel { text: qsTr("QUALITY") }
                Hint { text: qsTr("Auto direct-plays the original file (mpv handles every codec); a cap makes the server transcode. Applies to the next video.") }
                ComboRow { label: qsTr("Max video quality (in-network)"); options: screen.bitrateOptions; value: screen.pref("playback/maxBitrate", 0); onPicked: (v) => screen.setPref("playback/maxBitrate", v) }
                ComboRow { label: qsTr("Max video quality (internet)"); options: screen.bitrateOptions; value: screen.pref("playback/maxBitrateInternet", 0); onPicked: (v) => screen.setPref("playback/maxBitrateInternet", v) }

                GroupLabel { text: qsTr("AUDIO") }
                ComboRow { label: qsTr("Preferred audio language"); options: screen.audioLangs; value: screen.cfg("AudioLanguagePreference", ""); onPicked: (v) => { if (screen.client) screen.client.setUserConfig("AudioLanguagePreference", v) } }
                ToggleRow { label: qsTr("Play default audio track regardless of language"); on: screen.cfg("PlayDefaultAudioTrack", false) === true; onSwitched: (v) => { if (screen.client) screen.client.setUserConfig("PlayDefaultAudioTrack", v) } }
                ComboRow { label: qsTr("Allowed audio channels"); options: [{value: 0, text: qsTr("Auto")}, {value: 2, text: qsTr("Stereo")}, {value: 6, text: qsTr("5.1")}, {value: 8, text: qsTr("7.1")}]; value: screen.pref("playback/audioChannels", 0); onPicked: (v) => screen.setPref("playback/audioChannels", v) }
                ComboRow { label: qsTr("Audio normalization"); options: [{value: "TrackGain", text: qsTr("Track")}, {value: "AlbumGain", text: qsTr("Album")}, {value: "None", text: qsTr("Off")}]; value: screen.pref("playback/audioNormalization", "TrackGain"); onPicked: (v) => screen.setPref("playback/audioNormalization", v) }
                ToggleRow { label: qsTr("Disable VBR audio encoding"); on: screen.prefBool("playback/disableVbrAudio", false); onSwitched: (v) => screen.setPref("playback/disableVbrAudio", v) }
                ToggleRow { label: qsTr("Allow DTS (audio passthrough)"); on: screen.prefBool("playback/enableDts", false); onSwitched: (v) => screen.setPref("playback/enableDts", v) }
                ToggleRow { label: qsTr("Allow TrueHD (audio passthrough)"); on: screen.prefBool("playback/enableTrueHd", false); onSwitched: (v) => screen.setPref("playback/enableTrueHd", v) }

                GroupLabel { text: qsTr("VIDEO") }
                ComboRow { label: qsTr("Max video resolution"); options: [{value: 0, text: qsTr("Auto (source)")}, {value: 3840, text: qsTr("4K — 2160p")}, {value: 2560, text: qsTr("1440p")}, {value: 1920, text: qsTr("1080p")}, {value: 1280, text: qsTr("720p")}, {value: 854, text: qsTr("480p")}]; value: screen.pref("playback/maxResolutionWidth", 0); onPicked: (v) => screen.setPref("playback/maxResolutionWidth", v) }
                ToggleRow { label: qsTr("Limit to the display's resolution"); on: screen.prefBool("playback/limitResolution", false); onSwitched: (v) => screen.setPref("playback/limitResolution", v) }
                ComboRow { label: qsTr("Preferred transcode video codec"); options: [{value: "", text: qsTr("Auto (H.264)")}, {value: "h264", text: "H.264"}, {value: "hevc", text: qsTr("HEVC (H.265)")}, {value: "av1", text: "AV1"}]; value: screen.pref("playback/transcodeVideoCodec", ""); onPicked: (v) => screen.setPref("playback/transcodeVideoCodec", v) }
                ComboRow { label: qsTr("Preferred transcode audio codec"); options: [{value: "", text: qsTr("Auto (AAC)")}, {value: "aac", text: "AAC"}, {value: "ac3", text: "AC3"}, {value: "eac3", text: "E-AC3"}, {value: "flac", text: "FLAC"}]; value: screen.pref("playback/transcodeAudioCodec", ""); onPicked: (v) => screen.setPref("playback/transcodeAudioCodec", v) }
                ToggleRow { label: qsTr("Allow 10-bit H.264 (Hi10P)"); on: screen.prefBool("playback/enableHi10p", true); onSwitched: (v) => screen.setPref("playback/enableHi10p", v) }
                ToggleRow { label: qsTr("Prefer fMP4-HLS container"); on: screen.prefBool("playback/preferFmp4", false); onSwitched: (v) => screen.setPref("playback/preferFmp4", v) }

                GroupLabel { text: qsTr("BEHAVIOUR") }
                ToggleRow { label: qsTr("Play next episode automatically"); on: screen.autoPlayNext; onSwitched: (v) => { screen.autoPlayNext = v; screen.setPref("playback/autoPlayNext", v) } }
                ToggleRow { label: qsTr("Remember audio selections"); on: screen.cfg("RememberAudioSelections", false) === true; onSwitched: (v) => { if (screen.client) screen.client.setUserConfig("RememberAudioSelections", v) } }
                ToggleRow { label: qsTr("Remember subtitle selections"); on: screen.cfg("RememberSubtitleSelections", false) === true; onSwitched: (v) => { if (screen.client) screen.client.setUserConfig("RememberSubtitleSelections", v) } }
                StepperRow { label: qsTr("Skip back interval"); value: screen.skipBack; step: 5; minValue: 5; maxValue: 120; onChanged: (v) => { screen.skipBack = v; screen.setPref("playback/skipBack", v) } }
                StepperRow { label: qsTr("Skip forward interval"); value: screen.skipForward; step: 5; minValue: 5; maxValue: 120; onChanged: (v) => { screen.skipForward = v; screen.setPref("playback/skipForward", v) } }
                ToggleRow { label: qsTr("Enable cinema mode (trailers / intros)"); on: screen.prefBool("playback/cinemaMode", false); stub: true }
                ToggleRow { label: qsTr("Show next-video info overlay"); on: screen.prefBool("playback/nextVideoOverlay", true); stub: true }
                ToggleRow { label: qsTr("Enable external video players"); on: screen.prefBool("playback/externalPlayers", false); stub: true }

                GroupLabel { text: qsTr("MEDIA SEGMENTS") }
                Hint { text: qsTr("What to do at each marked segment. The skip behaviour isn't wired to the player yet.") }
                ComboRow { enabled: false; label: qsTr("Intro"); options: screen.segmentActions; value: screen.pref("playback/segIntro", "None"); onPicked: (v) => screen.setPref("playback/segIntro", v) }
                ComboRow { enabled: false; label: qsTr("Recap"); options: screen.segmentActions; value: screen.pref("playback/segRecap", "None"); onPicked: (v) => screen.setPref("playback/segRecap", v) }
                ComboRow { enabled: false; label: qsTr("Preview"); options: screen.segmentActions; value: screen.pref("playback/segPreview", "None"); onPicked: (v) => screen.setPref("playback/segPreview", v) }
                ComboRow { enabled: false; label: qsTr("Outro / Credits"); options: screen.segmentActions; value: screen.pref("playback/segOutro", "None"); onPicked: (v) => screen.setPref("playback/segOutro", v) }
                ComboRow { enabled: false; label: qsTr("Commercial"); options: screen.segmentActions; value: screen.pref("playback/segCommercial", "None"); onPicked: (v) => screen.setPref("playback/segCommercial", v) }
            }

            // 4 — Subtitles
            Panel {
                SectionTitle { text: qsTr("Subtitles") }
                Hint { text: qsTr("Defaults applied when a video starts; size & delay can also be tweaked live from the player.") }
                ChoiceRow {
                    label: qsTr("Styling")
                    options: [{value: "native", text: qsTr("Native")}, {value: "auto", text: qsTr("Auto")}, {value: "custom", text: qsTr("Custom")}]
                    value: screen.subStyle
                    onPicked: (v) => { screen.subStyle = v; screen.setPref("subtitles/styleMode", v) }
                }
                Hint { text: qsTr("Native keeps each subtitle's own look · Auto keeps the look but lets you resize · Custom forces the appearance below (best for plain SRT; overrides styled ASS/SSA).") }
                StepperRow { label: qsTr("Size"); value: Math.round(screen.subScale * 100); step: 10; minValue: 50; maxValue: 300; suffix: "%"; onChanged: (v) => { screen.subScale = v / 100; screen.setPref("subtitles/scale", screen.subScale) } }
                StepperRow { label: qsTr("Vertical position"); value: screen.subPos; step: 5; minValue: 0; maxValue: 150; suffix: ""; onChanged: (v) => { screen.subPos = v; screen.setPref("subtitles/pos", v) } }
                ToggleRow { label: qsTr("Bold"); on: screen.subBold; onSwitched: (v) => { screen.subBold = v; screen.setPref("subtitles/bold", v) } }
                ChoiceRow {
                    label: qsTr("Font")
                    options: [{value: "", text: qsTr("Default")}, {value: "sans-serif", text: qsTr("Sans")}, {value: "serif", text: qsTr("Serif")}, {value: "monospace", text: qsTr("Mono")}]
                    value: screen.subFont
                    onPicked: (v) => { screen.subFont = v; screen.setPref("subtitles/font", v) }
                }
                SwatchRow {
                    label: qsTr("Text color")
                    options: [{value: "#FFFFFF", color: "#FFFFFF"}, {value: "#FFFF00", color: "#FFFF00"}, {value: "#D3D3D3", color: "#D3D3D3"}, {value: "#00FFFF", color: "#00FFFF"}, {value: "#00FF00", color: "#00FF00"}, {value: "#FF0000", color: "#FF0000"}, {value: "#000000", color: "#000000"}]
                    value: screen.subColor
                    onPicked: (v) => { screen.subColor = v; screen.setPref("subtitles/color", v) }
                }
                ChoiceRow {
                    label: qsTr("Edge")
                    options: [{value: "none", text: qsTr("None")}, {value: "outline", text: qsTr("Outline")}, {value: "shadow", text: qsTr("Shadow")}, {value: "both", text: qsTr("Both")}]
                    value: screen.subEdge
                    onPicked: (v) => { screen.subEdge = v; screen.setPref("subtitles/edge", v) }
                }
                Item { Layout.preferredHeight: Theme.spacing }
                ChoiceRow {
                    label: qsTr("Subtitle mode")
                    options: [{value: "Default", text: qsTr("Default")}, {value: "Smart", text: qsTr("Smart")}, {value: "OnlyForced", text: qsTr("Only forced")}, {value: "Always", text: qsTr("Always")}, {value: "None", text: qsTr("None")}]
                    value: screen.cfg("SubtitleMode", "Default")
                    onPicked: (v) => { if (screen.client) screen.client.setUserConfig("SubtitleMode", v) }
                }
                ComboRow {
                    label: qsTr("Preferred subtitle language")
                    options: screen.subLangs
                    value: screen.cfg("SubtitleLanguagePreference", "")
                    onPicked: (v) => { if (screen.client) screen.client.setUserConfig("SubtitleLanguagePreference", v) }
                }
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
