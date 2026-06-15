import QtQuick
import QtQuick.Controls.Basic
import JellyfinDesktop

ApplicationWindow {
    id: win
    width: 1280
    height: 720
    visible: true
    title: qsTr("Jellyfin Desktop — mpv spike")
    color: "black"

    MpvVideoItem {
        id: player
        anchors.fill: parent

        onFileLoaded: console.log("[mpv] file loaded")
        onEndFile: (reason) => console.log("[mpv] end-file, reason:", reason)
    }

    // Minimal controls bar — just enough to prove playback works.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 56
        color: "#cc101010"

        Row {
            anchors.centerIn: parent
            spacing: 16

            Button {
                text: qsTr("Play / Pause")
                onClicked: player.command(["cycle", "pause"])
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                color: "white"
                text: qsTr("pass a media file or URL as the last argument")
            }
        }
    }

    Component.onCompleted: {
        const args = Qt.application.arguments
        if (args.length > 1)
            player.play(args[args.length - 1])
    }
}
