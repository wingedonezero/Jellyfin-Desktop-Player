import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The on-screen controls (OSD): a back button plus a bottom bar with a scrubber
// row and a control row (play/pause, skip, volume, subtitle/audio menus,
// fullscreen). Driven entirely by the player's observed state.
Item {
    id: root
    required property var player
    signal back()
    signal toggleFullscreen()

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

    Button {
        text: qsTr("◀  Back")
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 16
        onClicked: root.back()
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 120
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 1.0; color: "#e6000000" }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 18
            anchors.bottomMargin: 12
            spacing: 6

            // --- scrubber row ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Label { text: root.fmt(root.player.position); color: "white" }

                Slider {
                    id: scrubber
                    Layout.fillWidth: true
                    from: 0
                    to: Math.max(1, root.player.duration)

                    property bool seeking: false
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

                Label { text: root.fmt(root.player.duration); color: "white" }
            }

            // --- control row ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button { text: qsTr("⏪ 10"); onClicked: root.player.skip(-10) }
                Button {
                    text: root.player.paused ? qsTr("▶") : qsTr("⏸")
                    onClicked: root.player.setPaused(!root.player.paused)
                }
                Button { text: qsTr("30 ⏩"); onClicked: root.player.skip(30) }

                Item { Layout.fillWidth: true }

                // volume
                Button {
                    text: root.player.muted ? qsTr("🔇") : qsTr("🔊")
                    onClicked: root.player.setMuted(!root.player.muted)
                }
                Slider {
                    Layout.preferredWidth: 110
                    from: 0
                    to: 100
                    value: root.player.volume
                    onMoved: root.player.setVolume(value)
                }

                // subtitle track menu
                Button {
                    text: qsTr("CC")
                    onClicked: subtitleMenu.popup()
                    Menu {
                        id: subtitleMenu
                        MenuItem {
                            text: qsTr("Subtitles off")
                            onTriggered: root.player.setSubtitleTrack(-1)
                        }
                        Instantiator {
                            model: root.player.subtitleTracks
                            delegate: MenuItem {
                                required property var modelData
                                text: (modelData.selected ? "● " : "   ") + modelData.label
                                onTriggered: root.player.setSubtitleTrack(modelData.id)
                            }
                            onObjectAdded: (index, object) => subtitleMenu.insertItem(index + 1, object)
                            onObjectRemoved: (index, object) => subtitleMenu.removeItem(object)
                        }
                    }
                }

                // audio track menu
                Button {
                    text: qsTr("Audio")
                    onClicked: audioMenu.popup()
                    Menu {
                        id: audioMenu
                        Instantiator {
                            model: root.player.audioTracks
                            delegate: MenuItem {
                                required property var modelData
                                text: (modelData.selected ? "● " : "   ") + modelData.label
                                onTriggered: root.player.setAudioTrack(modelData.id)
                            }
                            onObjectAdded: (index, object) => audioMenu.insertItem(index, object)
                            onObjectRemoved: (index, object) => audioMenu.removeItem(object)
                        }
                    }
                }

                Button { text: qsTr("⛶"); onClicked: root.toggleFullscreen() }
            }
        }
    }
}
