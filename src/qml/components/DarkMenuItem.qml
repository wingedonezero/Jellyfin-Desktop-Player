import QtQuick
import QtQuick.Controls.Basic
import JellyfinDesktop

MenuItem {
    id: mi
    implicitHeight: 38
    contentItem: Text {
        leftPadding: 10
        rightPadding: 10
        text: mi.text
        font.pixelSize: Theme.fontNormal
        color: mi.enabled ? Theme.textPrimary : Theme.textDisabled
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: Theme.radius - 2
        color: mi.highlighted ? Theme.surfaceHover : "transparent"
    }
}
