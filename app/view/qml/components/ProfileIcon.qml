import QtQuick
import FluentUI

Rectangle {
    id: root
    property int iconId: 0
    property int size: 56
    property int level: 0

    implicitWidth: size
    implicitHeight: size
    radius: 6
    color: FluTheme.dark ? "#1f1f1f" : "#e9e9ef"
    clip: true

    Image {
        anchors.fill: parent
        anchors.margins: 2
        smooth: true
        cache: true
        asynchronous: true
        source: root.iconId > 0 ? Lcu.profileIcon(root.iconId) : ""
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        fillMode: Image.PreserveAspectCrop
    }

    Rectangle {
        visible: root.level > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -6
        width: levelLabel.implicitWidth + 10
        height: levelLabel.implicitHeight + 3
        radius: height / 2
        color: "#1a1a1a"
        border.color: "#d4a04a"
        border.width: 1

        FluText {
            id: levelLabel
            anchors.centerIn: parent
            text: root.level
            font.bold: true
            font.pixelSize: 10
            color: "#d4a04a"
        }
    }
}
