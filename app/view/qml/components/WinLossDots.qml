import QtQuick
import QtQuick.Layouts
import FluentUI

RowLayout {
    id: root
    property var matches: []    // expects {win: bool}[]
    property int dotSize: 10
    property int maxCount: 10
    spacing: 3

    Repeater {
        model: root.matches ? Math.min(root.maxCount, root.matches.length) : 0
        delegate: Rectangle {
            width: root.dotSize
            height: root.dotSize
            radius: root.dotSize / 2
            color: root.matches[index] && root.matches[index].win ? "#3ea04a" : "#c64343"
        }
    }

    Item {
        visible: !root.matches || root.matches.length === 0
        Layout.preferredHeight: root.dotSize
        FluText {
            text: qsTr("无数据")
            font.pixelSize: 11
            color: FluColors.Grey120
        }
    }
}
