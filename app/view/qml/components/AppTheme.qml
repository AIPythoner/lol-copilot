pragma Singleton
import QtQuick
import FluentUI

// ─────────────────────────────────────────────────────────────────────────
// Central design-token singleton for the "Hextech glass" look.
//
// Everything visual (glass surface colours, accents, radii, spacing, motion
// timings) is funnelled through here so the whole app retunes from one file
// and stays consistent. All colour tokens are theme-aware (track FluTheme.dark)
// so light/dark both look intentional.
//
// Available everywhere `import "../components"` is already present — no extra
// import needed in pages/components.
// ─────────────────────────────────────────────────────────────────────────
QtObject {
    id: t
    readonly property bool dark: FluTheme.dark

    // ── Accent palette (League / Hextech) ──────────────────────────────
    readonly property color accent:       "#E6B450"   // hextech gold — primary
    readonly property color accentBright:  "#F4CC68"
    readonly property color accentDeep:    "#C0902F"
    readonly property color teal:          "#43C7B4"   // hextech energy
    readonly property color cyan:          "#4FB6E6"
    readonly property color info:          "#5790E0"
    readonly property color positive:      "#46B25A"   // win
    readonly property color negative:      "#E05A4E"   // loss
    readonly property color violet:        "#9A6CE0"

    // Convenience: win/loss tints used all over match views
    readonly property color win:  positive
    readonly property color loss: negative

    // ── Corner radii ───────────────────────────────────────────────────
    readonly property int radiusSm: 8
    readonly property int radiusMd: 12
    readonly property int radiusLg: 16
    readonly property int radiusXl: 22
    readonly property int radiusPill: 999

    // ── Spacing scale (4-pt grid) ──────────────────────────────────────
    readonly property int sp1: 4
    readonly property int sp2: 8
    readonly property int sp3: 12
    readonly property int sp4: 16
    readonly property int sp5: 20
    readonly property int sp6: 24
    readonly property int sp8: 32

    // ── Motion ─────────────────────────────────────────────────────────
    readonly property int durFast: 120
    readonly property int durBase: 180
    readonly property int durSlow: 280
    readonly property int easeStd:  Easing.OutCubic
    readonly property int easeEmph: Easing.OutQuint

    // ── Glass surfaces (frosted, theme-aware) ──────────────────────────
    // Cards are translucent so the frosted canvas glows through them; the
    // soft window gradient behind is what sells the "毛玻璃" effect without
    // per-card blur (cheap + scroll-friendly).
    readonly property color glassFill:       dark ? Qt.rgba(1, 1, 1, 0.050) : Qt.rgba(1, 1, 1, 0.62)
    readonly property color glassFillHover:  dark ? Qt.rgba(1, 1, 1, 0.085) : Qt.rgba(1, 1, 1, 0.80)
    readonly property color glassFillStrong: dark ? Qt.rgba(1, 1, 1, 0.095) : Qt.rgba(1, 1, 1, 0.86)
    readonly property color glassFillSunken: dark ? Qt.rgba(0, 0, 0, 0.180) : Qt.rgba(1, 1, 1, 0.42)

    readonly property color glassBorder:    dark ? Qt.rgba(1, 1, 1, 0.090) : Qt.rgba(0.10, 0.14, 0.24, 0.10)
    readonly property color glassBorderHi:  dark ? Qt.rgba(1, 1, 1, 0.140) : Qt.rgba(0.10, 0.14, 0.24, 0.16)
    readonly property color glassHighlight: dark ? Qt.rgba(1, 1, 1, 0.140) : Qt.rgba(1, 1, 1, 0.95)
    readonly property color hairline:       dark ? Qt.rgba(1, 1, 1, 0.070) : Qt.rgba(0.10, 0.14, 0.24, 0.08)

    // Accent-tinted glass (selected / highlighted cards)
    readonly property color accentGlass:       Qt.rgba(230/255, 180/255, 80/255, dark ? 0.12 : 0.18)
    readonly property color accentGlassBorder:  Qt.rgba(230/255, 180/255, 80/255, dark ? 0.55 : 0.70)

    // Skeleton-loading placeholders — soft + theme-aware so they read as gentle
    // shimmer on the frosted glass instead of harsh flat-grey blocks.
    readonly property color skeleton:       dark ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(0.30, 0.38, 0.52, 0.12)
    readonly property color skeletonStrong: dark ? Qt.rgba(1, 1, 1, 0.110) : Qt.rgba(0.30, 0.38, 0.52, 0.18)

    // ── Window canvas (frosted background) ─────────────────────────────
    // Single smooth diagonal gradient. Dark mode stays in ONE airy teal-blue
    // family the whole way down (no sink to near-black) so the canvas reads as
    // 通透 / translucent rather than heavy.
    readonly property color bgTop:    dark ? "#123246" : "#F4F7FD"
    readonly property color bgMid:    dark ? "#0D2535" : "#E7EEF9"
    readonly property color bgBottom: dark ? "#0A1B28" : "#D9E2F2"

    // One soft highlight glow in the same family — adds gentle luminance toward
    // the top (teal-cyan in dark), never a competing colour zone.
    readonly property color glowAccent: dark ? Qt.rgba(0.28, 0.58, 0.72, 0.30) : Qt.rgba(0.52, 0.66, 0.98, 0.18)

    // Whole-canvas opacity. Slightly < 1 lets the desktop subtly show through
    // the window for a floating frosted-glass feel; content/text stay opaque.
    readonly property real canvasOpacity: 0.90

    // ── Text helpers ───────────────────────────────────────────────────
    readonly property color textPrimary:   dark ? FluColors.White : FluColors.Grey220
    readonly property color textSecondary: FluColors.Grey120
    readonly property color textTertiary:   dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.42)

    // ── Tier colours (single source of truth for rank tints) ───────────
    function tierColor(tier) {
        switch ((tier || "").toUpperCase()) {
            case "IRON":        return "#8A7A6B"
            case "BRONZE":      return "#B07A4E"
            case "SILVER":      return "#A8B6C6"
            case "GOLD":        return "#E6B450"
            case "PLATINUM":    return "#56CFBC"
            case "EMERALD":     return "#3FB964"
            case "DIAMOND":     return "#5A93E0"
            case "MASTER":      return "#C06FE6"
            case "GRANDMASTER": return "#E06C75"
            case "CHALLENGER":  return "#F4D35E"
            default:            return textSecondary
        }
    }
}
