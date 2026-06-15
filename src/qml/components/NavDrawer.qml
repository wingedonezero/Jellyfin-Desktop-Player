import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// The left navigation drawer (jellyfin-web side menu): Home, Favorites, the
// user's libraries, then Settings / Admin / Log out. Libraries are passed in;
// everything emits a signal the shell routes.
Drawer {
    id: drawer
    property var client
    property var libraries: []

    signal navHome()
    signal navFavorites()
    signal navLibrary(var lib)
    signal navSettings()
    signal navAdmin()
    signal doLogout()

    width: Theme.drawerWidth
    height: parent ? parent.height : 0 // overriding contentItem drops the implicit full height
    edge: Qt.LeftEdge
    dim: true

    background: Rectangle {
        color: Theme.drawer
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.divider }
    }

    function iconFor(collectionType) {
        switch (collectionType) {
        case "movies":     return "\u{1F3AC}" // 🎬
        case "tvshows":    return "\u{1F4FA}" // 📺
        case "music":      return "\u{1F3B5}" // 🎵
        case "books":      return "\u{1F4DA}" // 📚
        case "photos":     return "\u{1F5BC}" // 🖼
        case "musicvideos":return "\u{1F3B8}" // 🎸
        case "boxsets":    return "\u{1F4E6}" // 📦
        case "livetv":     return "\u{1F4E1}" // 📡
        default:           return "\u{1F4C1}" // 📁
        }
    }

    component NavItem: ItemDelegate {
        id: ni
        property string glyph: ""
        property color glyphColor: Theme.textSecondary
        hoverEnabled: true
        Layout.fillWidth: true
        implicitHeight: 46
        contentItem: RowLayout {
            spacing: Theme.spacing
            Text { text: ni.glyph; color: ni.glyphColor; font.pixelSize: Theme.fontMedium; Layout.leftMargin: Theme.spacing }
            Text { text: ni.text; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
        }
        background: Rectangle { color: ni.hovered ? Theme.surfaceHover : "transparent" }
    }

    component NavDivider: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacingSmall
        Layout.bottomMargin: Theme.spacingSmall
        Layout.leftMargin: Theme.spacing
        Layout.rightMargin: Theme.spacing
        implicitHeight: 1
        color: Theme.divider
    }

    contentItem: Flickable {
        contentHeight: col.implicitHeight
        clip: true
        ColumnLayout {
            id: col
            width: parent.width
            spacing: 0

            // header
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.appBarHeight
                color: Theme.backgroundAlt
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing
                    spacing: Theme.spacingSmall
                    Text { text: "Jellyfin"; color: Theme.accent; font.pixelSize: Theme.fontLarge; font.bold: true; Layout.fillWidth: true; verticalAlignment: Text.AlignVCenter }
                }
            }

            NavItem { text: qsTr("Home"); glyph: "\u{1F3E0}"; onClicked: { drawer.close(); drawer.navHome() } }
            NavItem { text: qsTr("Favorites"); glyph: "♥"; glyphColor: Theme.accent; onClicked: { drawer.close(); drawer.navFavorites() } }

            NavDivider {}
            Text {
                text: qsTr("Media")
                color: Theme.textDisabled
                font.pixelSize: Theme.fontTiny
                font.bold: true
                Layout.leftMargin: Theme.spacing
                Layout.bottomMargin: Theme.spacingTiny
            }
            Repeater {
                model: drawer.libraries
                NavItem {
                    required property var modelData
                    text: modelData.name
                    glyph: drawer.iconFor(modelData.collectionType)
                    onClicked: { drawer.close(); drawer.navLibrary(modelData) }
                }
            }

            NavDivider {}
            NavItem { text: qsTr("Settings"); glyph: "⚙"; onClicked: { drawer.close(); drawer.navSettings() } }
            NavItem { text: qsTr("Administration"); glyph: "\u{1F6E0}"; visible: drawer.client && drawer.client.isAdmin; onClicked: { drawer.close(); drawer.navAdmin() } } // 🛠 admins only
            NavItem { text: qsTr("Log out"); glyph: "\u{23FB}"; onClicked: { drawer.close(); drawer.doLogout() } } // ⏻
        }
    }
}
