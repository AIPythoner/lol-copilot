import QtQuick
import FluentUI

Item {
    id: root
    property int itemId: 0
    property int size: 28
    property bool showTooltip: true

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: FluTheme.dark ? "#1a1a1a" : "#e9e9ef"
        border.color: FluTheme.dark ? "#2a2a2a" : "#d0d0d8"
        border.width: 1
        clip: true

        Image {
            id: img
            anchors.fill: parent
            anchors.margins: 1
            smooth: true
            cache: true
            asynchronous: true
            // reference Lcu.connected/gameData so binding re-evals on state changes
            source: (Lcu.connected || !Lcu.connected) && root.itemId > 0
                ? Lcu.itemIcon(root.itemId)
                : ""
            sourceSize.width: root.size * 2
            sourceSize.height: root.size * 2
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
        }
    }

    FluTooltip {
        text: Lcu.itemsById[String(root.itemId)]
            ? Lcu.itemsById[String(root.itemId)].name
            : ""
        visible: showTooltip && mouse.containsMouse && text.length > 0
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: showTooltip
    }
}
