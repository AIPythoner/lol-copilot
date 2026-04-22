import QtQuick
import FluentUI

Item {
    id: root
    property int championId: 0
    property int size: 40
    property bool circular: true
    property bool showTooltip: true

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: circular ? width / 2 : 6
        color: FluTheme.dark ? "#333" : "#ddd"
        clip: true

        Image {
            id: img
            anchors.fill: parent
            smooth: true
            cache: true
            asynchronous: true
            // championIcon() returns image://lcu when connected (fast localhost)
            // or a direct CDragon URL otherwise. The Lcu.connected reference
            // keeps the binding tracking connection-state changes.
            source: (Lcu.connected || !Lcu.connected) && root.championId > 0
                ? Lcu.championIcon(root.championId)
                : ""
            sourceSize.width: root.size * 2
            sourceSize.height: root.size * 2
            fillMode: Image.PreserveAspectCrop
        }
    }

    FluTooltip {
        text: Lcu.championsById[String(root.championId)]
            ? Lcu.championsById[String(root.championId)].name
            : ""
        visible: showTooltip && mouse.containsMouse && text.length > 0
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: showTooltip
    }
}
