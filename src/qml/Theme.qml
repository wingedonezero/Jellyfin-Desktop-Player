pragma Singleton
import QtQuick

// ----------------------------------------------------------------------------
// Theme — the single source of truth for the skin. Every color/metric/font the
// UI uses comes from here, so re-skinning is swapping these values (later: load
// them from a JSON theme file). The default skin replicates the jellyfin-web
// "Dark" look. Nothing else in the app should hard-code a color or size.
// ----------------------------------------------------------------------------
QtObject {
    // --- palette ---
    readonly property color background:    "#101010" // app background
    readonly property color backgroundAlt: "#181818"
    readonly property color surface:       "#202124" // menus, cards, popovers
    readonly property color surfaceHover:  "#34353a"
    readonly property color elevated:      "#2a2b2f"
    readonly property color accent:        "#00a4dc" // Jellyfin blue
    readonly property color accentHover:   "#33b5e5"
    readonly property color accentText:    "#ffffff" // foreground on accent (avoid "on*" names: QML reads them as signal handlers)
    readonly property color textPrimary:   "#ffffff"
    readonly property color textSecondary: "#b6b6b6"
    readonly property color textDisabled:  "#6a6a6a"
    readonly property color divider:       "#33ffffff"
    readonly property color scrimTop:      "#b3000000" // top OSD gradient (70%)
    readonly property color scrimBottom:   "#e6000000" // bottom OSD gradient (90%)
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

    // --- typography ---
    readonly property string fontFamily: "Noto Sans" // jellyfin-web's face; falls back to system sans
    readonly property int fontSmall:  13
    readonly property int fontNormal: 15
    readonly property int fontMedium: 18
    readonly property int fontLarge:  22
    readonly property int fontTitle:  30
}
