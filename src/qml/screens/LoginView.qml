import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    required property var client

    Component.onCompleted: {
        if (typeof initialUser !== "undefined")
            userField.text = initialUser
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: 360
        spacing: 14

        Label {
            text: qsTr("Jellyfin Desktop")
            color: "white"
            font.pixelSize: 30
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
        }

        TextField {
            id: serverField
            Layout.fillWidth: true
            placeholderText: qsTr("Server  e.g. http://192.168.1.11:8096")
            text: root.client.serverUrl
        }

        TextField {
            id: userField
            Layout.fillWidth: true
            placeholderText: qsTr("Username")
        }

        TextField {
            id: passField
            Layout.fillWidth: true
            placeholderText: qsTr("Password")
            echoMode: TextInput.Password
            onAccepted: loginButton.clicked()
        }

        Button {
            id: loginButton
            Layout.fillWidth: true
            text: qsTr("Log in")
            onClicked: {
                errorLabel.text = ""
                root.client.serverUrl = serverField.text
                root.client.authenticate(userField.text, passField.text)
            }
        }

        Label {
            id: errorLabel
            Layout.fillWidth: true
            color: "tomato"
            wrapMode: Text.Wrap
            visible: text.length > 0
        }
    }

    Connections {
        target: root.client
        function onAuthenticationFailed(reason) {
            errorLabel.text = reason
        }
    }
}
