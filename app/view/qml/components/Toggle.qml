import QtQuick
import QtQuick.Layouts
import FluentUI

// Standalone toggle switch. FluToggleSwitch's `clickListener`/`onClicked`
// override semantics are inconsistent on Qt 6.7+ in this project (clicks
// either fire twice or not at all). This is a bare-bones replacement that
// fires a single `toggled(value)` signal per click and exposes only what we need.
//
// Notes:
// - Rectangle root with explicit width/height + Layout.preferredWidth/Height so
//   QtQuick.Layouts can size it predictably; relying on implicitWidth alone was
//   intermittently giving 0-sized hit boxes inside a Flickable.
// - preventStealing on the MouseArea keeps the parent FluScrollablePage's
//   Flickable from grabbing the press as a drag start.
Rectangle {
    id: root
    property bool checked: false
    property bool disabled: false
    signal toggled(bool value)

    width: 40
    height: 20
    implicitWidth: width
    implicitHeight: height
    Layout.preferredWidth: width
    Layout.preferredHeight: height
    Layout.minimumWidth: width
    Layout.minimumHeight: height
    Layout.alignment: Qt.AlignVCenter

    radius: height / 2
    color: {
        if (root.disabled) return FluTheme.dark ? "#525252" : "#e9e9e9"
        if (root.checked) return FluTheme.primaryColor
        return FluTheme.dark ? "#323232" : "#fdfdfd"
    }
    border.width: 1
    border.color: {
        if (root.disabled) return FluTheme.dark ? "#323232" : "#c8c8c8"
        if (root.checked) return FluTheme.primaryColor
        return FluTheme.dark ? "#a1a1a1" : "#8d8d8d"
    }

    Rectangle {
        id: thumb
        width: parent.height - 8
        height: width
        radius: width / 2
        y: 4
        x: root.checked ? root.width - width - 4 : 4
        color: {
            if (root.disabled) return FluTheme.dark ? "#323232" : "#969696"
            if (root.checked) return FluTheme.dark ? "#000000" : "#ffffff"
            return FluTheme.dark ? "#d0d0d0" : "#5d5d5d"
        }
        Behavior on x {
            enabled: FluTheme.enableAnimation
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.disabled
        cursorShape: root.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        preventStealing: true
        onClicked: {
            console.log("Toggle clicked, current=", root.checked, "-> new=", !root.checked)
            root.toggled(!root.checked)
        }
    }
}
