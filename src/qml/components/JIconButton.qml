import QtQuick
import QtQuick.Controls.Basic
import JellyfinDesktop

// A flat, theme-pure icon/text button used across the OSD and chrome.
Button {
    id: control
    property color fg: Theme.textPrimary
    flat: true
    hoverEnabled: true
    implicitWidth: Theme.iconButton
    implicitHeight: Theme.iconButton
    font.pixelSize: 18
    background: Rectangle {
        radius: Theme.radius
        color: control.down ? Theme.elevated
                            : (control.hovered && control.enabled ? Theme.surfaceHover : "transparent")
    }
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled ? control.fg : Theme.textDisabled
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
