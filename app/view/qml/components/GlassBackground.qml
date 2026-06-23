import QtQuick
import Qt5Compat.GraphicalEffects
import FluentUI

// ─────────────────────────────────────────────────────────────────────────
// GlassBackground — the frosted window canvas.
//
// A single smooth DIAGONAL gradient (clearly one gradient, not regional colour
// blobs) + one very soft highlight + a fine noise dither that both kills 8-bit
// gradient banding and gives the surface a frosted texture. Translucent
// GlassCards sit on top and let it glow through → the 毛玻璃 effect. Static, so
// it never costs frames while idle.
// ─────────────────────────────────────────────────────────────────────────
Rectangle {
    id: bg
    color: AppTheme.bgMid   // solid fallback under the gradient
    opacity: AppTheme.canvasOpacity   // subtle window translucency (frosted float)

    // Smooth diagonal base gradient — top-left → bottom-right.
    LinearGradient {
        anchors.fill: parent
        start: Qt.point(0, 0)
        end: Qt.point(bg.width, bg.height)
        gradient: Gradient {
            GradientStop { position: 0.0;  color: AppTheme.bgTop }
            GradientStop { position: 0.55; color: AppTheme.bgMid }
            GradientStop { position: 1.0;  color: AppTheme.bgBottom }
        }
    }

    // One large, very soft highlight toward the upper-right — adds depth/life
    // without any hard edge or colour zone (radius spans the whole window).
    RadialGradient {
        anchors.fill: parent
        horizontalOffset: bg.width * 0.26
        verticalOffset: -bg.height * 0.34
        horizontalRadius: bg.width * 1.1
        verticalRadius: bg.height * 1.1
        gradient: Gradient {
            GradientStop { position: 0.0; color: AppTheme.glowAccent }
            GradientStop { position: 0.6; color: "transparent" }
        }
    }

    // Fine noise dither — breaks up gradient banding and adds frosted grain.
    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("../../assets/noise.png")
        fillMode: Image.Tile
        opacity: AppTheme.dark ? 0.04 : 0.025
        smooth: false
    }
}
