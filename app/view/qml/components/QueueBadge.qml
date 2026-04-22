import QtQuick
import FluentUI

Rectangle {
    id: root
    property int queueId: 0
    property int horizontalPadding: 8
    property int verticalPadding: 4

    implicitHeight: label.implicitHeight + verticalPadding * 2
    implicitWidth: label.implicitWidth + horizontalPadding * 2
    radius: 4
    color: _bgColor()
    border.width: 1
    border.color: FluTheme.dark ? "#3a3a3a" : "#d0d0d8"

    function _bgColor() {
        switch (root.queueId) {
            case 420: return "#d4a04a40"    // 单双排
            case 440: return "#4684d440"    // 灵活组排
            case 450: return "#b964e040"    // ARAM
            case 430: return "#3e3e3e40"    // 匹配
            case 1700: return "#e06c7540"   // 斗魂竞技场
            default: return FluTheme.dark ? "#2a2a2a" : "#eaeaef"
        }
    }

    FluText {
        id: label
        anchors.centerIn: parent
        text: Lcu.queueName(root.queueId)
        font.pixelSize: 11
    }
}
