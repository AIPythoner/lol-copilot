import QtQuick
import FluentUI

Item {
    id: root
    property int spellId: 0
    property int size: 20
    property bool showTooltip: true

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: FluTheme.dark ? "#222" : "#dfdfe8"
        clip: true

        Image {
            id: img
            anchors.fill: parent
            anchors.margins: 1
            smooth: true
            cache: true
            asynchronous: true
            source: (Lcu.connected || !Lcu.connected) && root.spellId > 0
                ? Lcu.spellIcon(root.spellId)
                : ""
            sourceSize.width: root.size * 2
            sourceSize.height: root.size * 2
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
        }
    }

    FluTooltip {
        text: Lcu.spellsById[String(root.spellId)]
            ? Lcu.spellsById[String(root.spellId)].name
            : ""
        visible: showTooltip && mouse.containsMouse && text.length > 0
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: showTooltip
    }
}
