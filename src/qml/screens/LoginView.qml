import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import JellyfinDesktop

// Server + credentials sign-in. Theme-pure (matches the default jellyfin-web skin).
Item {
    id: root
    required property var client

    Component.onCompleted: {
        if (typeof initialUser !== "undefined")
            userField.text = initialUser
    }

    Rectangle { anchors.fill: parent; color: Theme.background }

    component LoginField: TextField {
        Layout.fillWidth: true
        color: Theme.textPrimary
        placeholderTextColor: Theme.textDisabled
        font.pixelSize: Theme.fontNormal
        leftPadding: 12
        rightPadding: 12
        background: Rectangle {
            implicitHeight: Theme.controlHeight
            radius: Theme.radius
            color: Theme.surface
            border.color: parent.activeFocus ? Theme.accent : Theme.divider
            border.width: 1
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: 360
        spacing: Theme.spacing

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 0
            Label { text: "Jellyfin"; color: Theme.accent; font.pixelSize: Theme.fontTitle; font.bold: true }
            Label { text: qsTr(" Desktop"); color: Theme.textPrimary; font.pixelSize: Theme.fontTitle; font.bold: true }
        }
        Item { Layout.preferredHeight: Theme.spacingSmall }

        LoginField {
            id: serverField
            placeholderText: qsTr("Server  e.g. http://192.168.1.11:8096")
            text: root.client.serverUrl
        }
        LoginField { id: userField; placeholderText: qsTr("Username") }
        LoginField {
            id: passField
            placeholderText: qsTr("Password")
            echoMode: TextInput.Password
            onAccepted: loginButton.clicked()
        }

        Button {
            id: loginButton
            Layout.fillWidth: true
            text: qsTr("Sign in")
            hoverEnabled: true
            implicitHeight: Theme.controlHeight
            onClicked: {
                errorLabel.text = ""
                root.client.serverUrl = serverField.text
                root.client.authenticate(userField.text, passField.text)
            }
            background: Rectangle { radius: Theme.radius; color: loginButton.hovered ? Theme.accentHover : Theme.accent }
            contentItem: Text {
                text: loginButton.text
                color: Theme.accentText
                font.pixelSize: Theme.fontNormal
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Label {
            id: errorLabel
            Layout.fillWidth: true
            color: Theme.error
            wrapMode: Text.Wrap
            visible: text.length > 0
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Connections {
        target: root.client
        function onAuthenticationFailed(reason) { errorLabel.text = reason }
    }
}
