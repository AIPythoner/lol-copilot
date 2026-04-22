import QtQuick
import FluentUI

Item {
    id: root
    property string position: ""
    property int size: 18

    implicitWidth: size
    implicitHeight: size
    visible: position.length > 0

    Image {
        anchors.fill: parent
        smooth: true
        cache: true
        asynchronous: true
        source: root.position ? Lcu.positionIcon(root.position) : ""
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        fillMode: Image.PreserveAspectFit
    }

    FluTooltip {
        text: root.position
        visible: mouse.containsMouse && root.position.length > 0
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
    }
}
