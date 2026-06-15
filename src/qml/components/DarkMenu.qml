import QtQuick
import QtQuick.Controls.Basic
import JellyfinDesktop

// Theme-pure dropdown menu. Pair with DarkMenuItem for the rows.
Menu {
    implicitWidth: 240
    padding: 4
    background: Rectangle {
        color: Theme.surface
        radius: Theme.radius
        border.color: Theme.divider
        border.width: 1
    }
}
