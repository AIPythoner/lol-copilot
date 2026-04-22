import QtQuick
import FluentUI

Rectangle {
    id: root
    property real score: 0
    property var tags: []       // ["MVP"] | ["ACE"] | []

    property int horizontalPadding: 8
    property int verticalPadding: 4

    implicitHeight: label.implicitHeight + verticalPadding * 2
    implicitWidth: label.implicitWidth + horizontalPadding * 2
    radius: 10
    color: _bgColor()

    function _bgColor() {
        if (tags && tags.indexOf("MVP") >= 0) return "#d4a04a"
        if (tags && tags.indexOf("ACE") >= 0) return "#b964e0"
        if (score >= 75) return "#3ea04a"
        if (score >= 60) return "#4684d4"
        if (score >= 45) return FluTheme.dark ? "#3a3a3a" : "#d0d0d8"
        return "#c64343"
    }

    function _fgColor() {
        return "white"
    }

    FluText {
        id: label
        anchors.centerIn: parent
        text: {
            if (tags && tags.length > 0) return tags.join("/") + "  " + Math.round(root.score)
            return Math.round(root.score)
        }
        font.bold: true
        color: _fgColor()
    }
}
