pragma Singleton
import QtQuick

// ----------------------------------------------------------------------------
// Theme — the SINGLE source of truth for the skin. Every color, metric and font
// the UI uses comes from here; nothing else hard-codes a style. Re-skinning is
// changing these values (later: loaded from a JSON theme file). The default
// values replicate the jellyfin-web "Dark" skin. Components must stay
// theme-pure — read from Theme, never literal colors/sizes.
// ----------------------------------------------------------------------------
QtObject {
    // --- palette ---
    readonly property color background:    "#101010" // app background
    readonly property color backgroundAlt: "#181818"
    readonly property color appBar:        "#101010" // top bar
    readonly property color drawer:        "#202124" // side menu
    readonly property color surface:       "#202124" // cards, menus, popovers
    readonly property color surfaceHover:  "#34353a"
    readonly property color elevated:      "#2a2b2f"
    readonly property color overlay:       "#99000000" // hover/scrim over media
    readonly property color accent:        "#00a4dc"   // Jellyfin blue
    readonly property color accentHover:   "#33b5e5"
    readonly property color accentText:    "#ffffff"   // foreground on accent
    readonly property color textPrimary:   "#ffffff"
    readonly property color textSecondary: "#b6b6b6"
    readonly property color textDisabled:  "#6a6a6a"
    readonly property color divider:       "#2effffff"
    readonly property color watched:       "#52b54b"   // jellyfin green (played check)
    readonly property color rating:        "#f9b300"   // community-rating star
    readonly property color scrimTop:      "#b3000000"
    readonly property color scrimBottom:   "#e6000000"
    readonly property color scrimSoft:     "#33000000" // light top scrim over backdrops
    readonly property color overlayStrong: "#cc000000" // play buttons / row arrows
    readonly property color overlayMedium: "#80000000" // progress track behind a bar
    readonly property color tickMark:      "#ccffffff" // chapter ticks on the scrubber
    readonly property color statsBg:       "#e6202124" // playback-info overlay panel
    readonly property color error:         "#ff5252"   // login / form errors
    readonly property color transparent:   "#00000000"

    // --- metrics ---
    readonly property int radius:        6
    readonly property int radiusLarge:   10
    readonly property int spacingTiny:   4
    readonly property int spacingSmall:  8
    readonly property int spacing:       12
    readonly property int spacingLarge:  20
    readonly property int controlHeight: 40
    readonly property int iconButton:    44
    readonly property int appBarHeight:  56
    readonly property int drawerWidth:   260
    readonly property int pagePad:       32   // page left/right padding

    // card geometry (poster = 2:3, thumb = 16:9)
    readonly property int cardPosterWidth:  148
    readonly property int cardPosterHeight: 222
    readonly property int cardThumbWidth:   272
    readonly property int cardThumbHeight:  153

    // --- animation (faster = the display/fastAnimations pref, set from Main) ---
    property bool fastAnimations: false
    readonly property int animFast:   fastAnimations ? 60 : 130   // card hover zoom
    readonly property int animMedium: fastAnimations ? 110 : 220  // row / carousel scroll

    // --- typography ---
    readonly property string fontFamily: "Noto Sans" // jellyfin-web face; falls back to system sans
    readonly property int fontTiny:   11
    readonly property int fontSmall:  13
    readonly property int fontNormal: 15
    readonly property int fontMedium: 18
    readonly property int fontLarge:  22
    readonly property int fontTitle:  30
    readonly property int fontHero:   42
}
