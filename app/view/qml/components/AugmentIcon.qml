import QtQuick
import FluentUI

Item {
    id: root
    property int augmentId: 0
    property int size: 28
    property bool showTooltip: true

    implicitWidth: size
    implicitHeight: size
    visible: augmentId > 0

    // rarity outline colors mirror rank-analysis's augment display
    property string rarity: Lcu.augmentRarity(augmentId)
    property color borderColor: {
        switch (rarity) {
            case "prismatic": return "#b964e0"
            case "gold": return "#d4a04a"
            case "silver": return "#c0c0c0"
            case "bronze": return "#cd7f32"
            default: return FluTheme.dark ? "#3a3a3a" : "#d0d0d8"
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: FluTheme.dark ? "#1a1a1a" : "#e9e9ef"
        border.color: root.borderColor
        border.width: 2
        clip: true

        Image {
            anchors.fill: parent
            anchors.margins: 2
            smooth: true
            cache: true
            asynchronous: true
            source: (Lcu.connected || !Lcu.connected) && root.augmentId > 0
                ? Lcu.augmentIcon(root.augmentId)
                : ""
            sourceSize.width: root.size * 2
            sourceSize.height: root.size * 2
            fillMode: Image.PreserveAspectFit
        }
    }

    FluTooltip {
        text: {
            var n = Lcu.augmentName(root.augmentId)
            return n ? n : ("海克斯 #" + root.augmentId)
        }
        visible: showTooltip && mouse.containsMouse
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: showTooltip
    }
}
