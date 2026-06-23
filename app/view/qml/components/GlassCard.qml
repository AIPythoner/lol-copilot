import QtQuick
import QtQuick.Controls
import QtQuick.Window
import FluentUI

// ─────────────────────────────────────────────────────────────────────────
// GlassCard — frosted translucent surface, drop-in replacement for FluArea.
//
// Keeps FluArea's API (default `content` alias + `paddings` / per-side padding)
// so migration is mostly a rename. Adds:
//   • translucent theme-aware fill so the frosted canvas glows through
//   • a hairline border + top "sheen" highlight that reads as glass
//   • optional hover lift + brighten (`hoverable`)
//   • optional whole-card click target with pointer cursor (`interactive`)
//
// Hover/press use HoverHandler + TapHandler (pointer handlers), NOT a covering
// MouseArea — so a card can be `interactive` AND still let its children show
// their own hover tooltips (item/spell tooltips in match rows keep working).
// ─────────────────────────────────────────────────────────────────────────
Rectangle {
    id: control

    default property alias content: container.data

    property int paddings: 0
    property int leftPadding: 0
    property int rightPadding: 0
    property int topPadding: 0
    property int bottomPadding: 0

    // interaction
    property bool hoverable: false
    property bool interactive: false
    property bool selected: false
    readonly property alias hovered: hoverHandler.hovered
    signal clicked()

    // styling knobs
    property color baseColor: selected ? AppTheme.accentGlass : AppTheme.glassFill
    property color hoverColor: AppTheme.glassFillHover
    property color baseBorder: selected ? AppTheme.accentGlassBorder : AppTheme.glassBorder
    property bool sheen: true
    property bool lift: true

    radius: AppTheme.radiusMd
    antialiasing: true
    implicitHeight: height
    implicitWidth: width

    readonly property bool _hot: hoverable && hoverHandler.hovered

    color: _hot ? hoverColor : baseColor
    Behavior on color { ColorAnimation { duration: AppTheme.durFast; easing.type: AppTheme.easeStd } }

    border.width: 1
    border.color: _hot ? AppTheme.glassBorderHi : baseBorder
    Behavior on border.color { ColorAnimation { duration: AppTheme.durFast } }

    // Subtle hover lift — transform doesn't disturb layout of neighbours.
    transform: Translate {
        y: (control.lift && control._hot) ? -2 : 0
        Behavior on y { NumberAnimation { duration: AppTheme.durBase; easing.type: AppTheme.easeStd } }
    }

    // Pointer handlers — coexist with child hover/click so inner tooltips live.
    HoverHandler {
        id: hoverHandler
        enabled: control.hoverable || control.interactive
        cursorShape: control.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        enabled: control.interactive
        acceptedButtons: Qt.LeftButton
        onTapped: control.clicked()
    }

    // Glass sheen — bright fade along the top edge. Shares the card radius so
    // its top corners follow the rounding; it's transparent before the bottom.
    Rectangle {
        visible: control.sheen
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            leftMargin: 1; rightMargin: 1; topMargin: 1
        }
        height: Math.min((parent.height - 2) * 0.55, 56)
        radius: control.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: AppTheme.glassHighlight }
            GradientStop { position: 1.0; color: "transparent" }
        }
        opacity: AppTheme.dark ? 0.55 : 0.85
    }

    Item {
        id: container
        anchors.fill: parent
        anchors.leftMargin: Math.max(paddings, leftPadding)
        anchors.rightMargin: Math.max(paddings, rightPadding)
        anchors.topMargin: Math.max(paddings, topPadding)
        anchors.bottomMargin: Math.max(paddings, bottomPadding)
    }
}
