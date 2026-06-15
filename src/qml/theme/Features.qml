pragma Singleton
import QtQuick

// ----------------------------------------------------------------------------
// Features — central registry of capabilities the skin draws but that aren't
// wired yet. The UI renders every button/menu to match jellyfin-web 1:1; the
// ones gated here are shown disabled ("marked") until the backing feature lands.
// Lighting one up — or removing it — is a one-line flip here, with no change to
// the skin. See the capability tiers discussed for the player.
// ----------------------------------------------------------------------------
QtObject {
    readonly property bool transcodeQuality: true  // server-side quality/bitrate (transcode pipeline)
    readonly property bool playQueue:        true  // previous/next, repeat, auto-play-next
    readonly property bool cast:             false // casting out to Chromecast/DLNA
    readonly property bool syncPlay:         false // watch-together (Jellyfin SyncPlay)
    readonly property bool trickplay:        false // scrubber thumbnail previews
    readonly property bool libraryFilters:   false // library filter panel (genre/year/unwatched/...)
    readonly property bool adminDashboard:   false // native server admin (huge; web-only for now)
    readonly property bool playlists:        true  // add to / manage playlists
    readonly property bool collections:      true  // add to / manage collections
    readonly property bool downloads:        false // download for offline
    readonly property bool metadataEdit:     false // edit / refresh item metadata
    readonly property bool deleteMedia:      false // delete media from the server
}
