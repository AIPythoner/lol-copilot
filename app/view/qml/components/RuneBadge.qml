import QtQuick
import FluentUI

Item {
    id: root
    property int keystoneId: 0
    property int subStyleId: 0
    property int size: 36

    implicitWidth: size
    implicitHeight: size
    // Some game modes (斗魂竞技场 / URF / 自定义等) don't persist runes,
    // so the keystone id is 0 — skip the whole badge in that case.
    visible: keystoneId > 0

    // Primary keystone, full-size
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        // Dark bg only when we actually have a rune to show.
        color: root.keystoneId > 0
            ? "#1c1c1c"
            : (FluTheme.dark ? "#2a2a2a" : "#e0e0e4")

        Image {
            anchors.fill: parent
            anchors.margins: 2
            smooth: true
            cache: true
            asynchronous: true
            source: (Lcu.connected || !Lcu.connected) && root.keystoneId > 0
                ? Lcu.perkIcon(root.keystoneId)
                : ""
            sourceSize.width: root.size * 2
            sourceSize.height: root.size * 2
            fillMode: Image.PreserveAspectFit
        }
    }

    // Sub-style, bottom-right corner overlay
    Rectangle {
        width: parent.width * 0.44
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        color: FluTheme.dark ? "#000" : "#fff"
        border.color: FluTheme.dark ? "#3a3a3a" : "#d0d0d8"
        border.width: 1
        visible: root.subStyleId > 0

        Image {
            anchors.fill: parent
            anchors.margins: 1
            smooth: true
            cache: true
            asynchronous: true
            source: (Lcu.connected || !Lcu.connected) && root.subStyleId > 0
                ? Lcu.perkStyleIcon(root.subStyleId)
                : ""
            sourceSize.width: root.size
            sourceSize.height: root.size
            fillMode: Image.PreserveAspectFit
        }
    }
}
