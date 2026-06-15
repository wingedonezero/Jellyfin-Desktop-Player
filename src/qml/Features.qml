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
    readonly property bool transcodeQuality: false // server-side quality/bitrate (transcode pipeline)
    readonly property bool playQueue:        false // previous/next, repeat, auto-play-next (needs a queue)
    readonly property bool cast:             false // casting out to Chromecast/DLNA
    readonly property bool syncPlay:         false // watch-together (Jellyfin SyncPlay)
    readonly property bool trickplay:        false // scrubber thumbnail previews
}
