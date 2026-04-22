import QtQuick
import QtQuick.Layouts
import FluentUI

Item {
    id: root
    property string text: qsTr("加载中…")
    property color accent: "#d4a04a"
    property int ringSize: 34
    property int minHeight: 360

    implicitHeight: minHeight

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.ringSize
            Layout.preferredHeight: root.ringSize

            Rectangle {
                id: pulse
                anchors.centerIn: parent
                width: parent.width + 10
                height: width
                radius: width / 2
                color: "transparent"
                border.color: root.accent
                border.width: 2
                opacity: 0.18
                scale: 0.82

                SequentialAnimation on scale {
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.08; duration: 760; easing.type: Easing.OutCubic }
                    NumberAnimation { to: 0.82; duration: 760; easing.type: Easing.InCubic }
                }
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.04; duration: 760; easing.type: Easing.OutCubic }
                    NumberAnimation { to: 0.18; duration: 760; easing.type: Easing.InCubic }
                }
            }

            Canvas {
                anchors.fill: parent
                opacity: FluTheme.dark ? 0.34 : 0.24
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.lineWidth = 2
                    ctx.strokeStyle = FluTheme.dark ? "#ffffff" : "#1f2937"
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, Math.min(width, height) / 2 - 3, 0, Math.PI * 2)
                    ctx.stroke()
                }
            }

            Item {
                id: spinner
                anchors.fill: parent

                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 920
                    loops: Animation.Infinite
                    easing.type: Easing.Linear
                }

                Canvas {
                    id: arc
                    anchors.fill: parent
                    property real sweep: 1.55
                    onSweepChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        var r = Math.min(width, height) / 2 - 4
                        ctx.reset()
                        ctx.lineCap = "round"

                        ctx.lineWidth = 6
                        ctx.globalAlpha = 0.2
                        ctx.strokeStyle = root.accent
                        ctx.beginPath()
                        ctx.arc(width / 2, height / 2, r, -Math.PI * 0.5, -Math.PI * 0.5 + sweep)
                        ctx.stroke()

                        ctx.globalAlpha = 1
                        ctx.lineWidth = 3.6
                        ctx.strokeStyle = root.accent
                        ctx.beginPath()
                        ctx.arc(width / 2, height / 2, r, -Math.PI * 0.5, -Math.PI * 0.5 + sweep)
                        ctx.stroke()
                    }

                    SequentialAnimation on sweep {
                        loops: Animation.Infinite
                        NumberAnimation { to: 4.35; duration: 620; easing.type: Easing.OutCubic }
                        NumberAnimation { to: 1.55; duration: 620; easing.type: Easing.InCubic }
                    }
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: root.accent
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    opacity: 0.95
                }
            }
        }

        FluText {
            Layout.alignment: Qt.AlignHCenter
            text: root.text
            color: FluColors.Grey120
            font.pixelSize: 13
            opacity: 0.78

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { to: 0.46; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.86; duration: 900; easing.type: Easing.InOutSine }
            }
        }
    }
}
