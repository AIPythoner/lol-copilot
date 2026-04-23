import QtQuick
import FluentUI

Item {
    id: root
    property int damage: 0
    property real share: 0.0   // 0..1, relative to team max
    property int teamId: 100    // 100 = blue, 200 = red
    property int barHeight: 6
    implicitHeight: txt.implicitHeight + barHeight + 2

    FluText {
        id: txt
        anchors.top: parent.top
        text: root.damage.toLocaleString(Qt.locale(), 'f', 0)
        font.pixelSize: 11
        color: FluColors.Grey120
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: root.barHeight
        radius: 3
        color: FluTheme.dark ? "#2a2a2a" : "#e4e4ea"

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * Math.max(0, Math.min(1, root.share))
            radius: 3
            color: root.teamId === 100 ? "#4684d4" : "#c64343"
        }
    }
}
