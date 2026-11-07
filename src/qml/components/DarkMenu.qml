import QtQuick
import QtQuick.Controls.Basic
import JellyfinDesktop

// Theme-pure dropdown menu. Pair with DarkMenuItem for the rows.
Menu {
    implicitWidth: 240
    padding: 4
    // Modal so the click that dismisses the menu doesn't ALSO act on what's
    // under it (over the video that's the pause area; on a card, its ▶/detail).
    modal: true
    dim: false
    background: Rectangle {
        color: Theme.surface
        radius: Theme.radius
        border.color: Theme.divider
        border.width: 1
    }
}
