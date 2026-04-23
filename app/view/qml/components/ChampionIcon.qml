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
        // Lazy lookup: only call the name slot when actually hovered. Binding
        // against Lcu.championsById triggers a full dict marshall into QML on
        // every eval — prohibitive when 100+ icons exist on a match detail page.
        text: showTooltip && mouse.containsMouse && root.championId > 0
            ? Lcu.championName(root.championId)
            : ""
        visible: text.length > 0
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: showTooltip
    }
}
