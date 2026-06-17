import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// The top chrome bar (jellyfin-web header): menu, back, home, page title,
// search, cast (stub) and the user menu. Pure signals out; the shell wires them.
Rectangle {
    id: bar
    property string title: ""
    property bool canGoBack: false
    property var client

    signal menuClicked()
    signal backClicked()
    signal homeClicked()
    signal searchClicked()
    signal settingsClicked()
    signal logoutClicked()

    implicitHeight: Theme.appBarHeight
    color: Theme.appBar

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingSmall
        anchors.rightMargin: Theme.spacingSmall
        spacing: Theme.spacingTiny

        JIconButton { text: "☰"; onClicked: bar.menuClicked() }            // ☰
        JIconButton { text: "←"; visible: bar.canGoBack; onClicked: bar.backClicked() } // ←
        JIconButton { text: "\u{1F3E0}"; onClicked: bar.homeClicked() }         // 🏠

        Text {
            text: bar.title
            color: Theme.textPrimary
            font.pixelSize: Theme.fontLarge
            font.bold: true
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingSmall
        }

        JIconButton { text: "\u{1F50D}"; onClicked: bar.searchClicked() }       // 🔍
        JIconButton { text: "\u{1F4FA}"; enabled: Features.cast }               // 📺 cast (stub)
        JIconButton {
            text: "\u{1F464}"                                                   // 👤
            onClicked: userMenu.popup()
            DarkMenu {
                id: userMenu
                DarkMenuItem { text: bar.client ? bar.client.userName : ""; enabled: false }
                DarkMenuItem { text: qsTr("Settings"); onTriggered: bar.settingsClicked() }
                DarkMenuItem { text: qsTr("Log out"); onTriggered: bar.logoutClicked() }
            }
        }
    }

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
}
