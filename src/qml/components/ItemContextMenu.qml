import QtQuick
import JellyfinDesktop

// The jellyfin-web item right-click menu, shared by MediaCard + MediaWideRow.
// It performs the self-contained user-data actions directly (favorite / watched
// / copy stream URL via the client) and bubbles the rest up as signals so the
// host card can route them (play / queue / play-next / add-to-*). Greyed rows
// (Download / Edit metadata) stay as web-parity placeholders.
DarkMenu {
    id: menu
    property var item
    property var client
    property bool playable: false
    property bool canAddTo: false

    signal play(var item)              // "Play" / "Play from beginning" (ticks pre-zeroed)
    signal queue(var item)             // add to queue
    signal playNext(var item)
    signal addToCollection(var item)
    signal addToPlaylist(var item)

    DarkMenuItem { text: qsTr("Play"); visible: menu.playable; onTriggered: menu.play(menu.item) }
    DarkMenuItem {
        text: qsTr("Play from beginning")
        visible: menu.playable && menu.item && (menu.item.playbackTicks > 0)
        onTriggered: { var it = Object.assign({}, menu.item); it.playbackTicks = 0; menu.play(it) }
    }
    DarkMenuItem { text: qsTr("Add to queue"); visible: menu.playable; onTriggered: menu.queue(menu.item) }
    DarkMenuItem { text: qsTr("Play next"); visible: menu.playable; onTriggered: menu.playNext(menu.item) }
    DarkMenuItem {
        text: (menu.item && menu.item.isFavorite) ? qsTr("Remove from favorites") : qsTr("Add to favorites")
        onTriggered: if (menu.client) menu.client.setFavorite(menu.item.id, !(menu.item.isFavorite === true))
    }
    DarkMenuItem {
        text: (menu.item && menu.item.played) ? qsTr("Mark as unplayed") : qsTr("Mark as played")
        onTriggered: if (menu.client) menu.client.setWatched(menu.item.id, !(menu.item.played === true))
    }
    DarkMenuItem { text: qsTr("Add to collection"); visible: menu.canAddTo; enabled: Features.collections; onTriggered: menu.addToCollection(menu.item) }
    DarkMenuItem { text: qsTr("Add to playlist"); visible: menu.canAddTo; enabled: Features.playlists; onTriggered: menu.addToPlaylist(menu.item) }
    DarkMenuItem { text: qsTr("Download"); enabled: Features.downloads }
    DarkMenuItem { text: qsTr("Copy stream URL"); visible: menu.playable; onTriggered: if (menu.client) menu.client.copyStreamUrl(menu.item.id) }
    DarkMenuItem { text: qsTr("Edit metadata"); enabled: Features.metadataEdit }
    DarkMenuItem { text: qsTr("Edit images"); enabled: Features.metadataEdit }
    DarkMenuItem { text: qsTr("Edit subtitles"); enabled: Features.metadataEdit }
    DarkMenuItem { text: qsTr("Identify"); enabled: Features.metadataEdit }
}
