import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The on-screen controls (OSD): back button + a bottom bar with play/pause,
// a scrubber, and time readouts. Driven entirely by the player's observed
// state (mpv is authoritative).
Item {
    id: root
    required property var player
    signal back()

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
        height: 76
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 1.0; color: "#dd000000" }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 18
            anchors.bottomMargin: 10
            spacing: 14

            Button {
                text: root.player.paused ? qsTr("▶") : qsTr("⏸")
                onClicked: root.player.setPaused(!root.player.paused)
            }

            Label {
                text: root.fmt(root.player.position)
                color: "white"
            }

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

                // Follow playback except while the user is dragging.
                Binding {
                    target: scrubber
                    property: "value"
                    value: root.player.position
                    when: !scrubber.seeking
                }
            }

            Label {
                text: root.fmt(root.player.duration)
                color: "white"
            }
        }
    }
}
