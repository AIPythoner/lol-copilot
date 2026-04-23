import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI

FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleTask
    title: qsTr("对局详情")

    property double myGameId: -1
    property var detail: ({})
    property bool isLoading: detail.loading === true || (myGameId > 0 && !detail.participants && !detail.error)
    property bool hasError: !!detail.error
    readonly property bool showLoadingState: isLoading && !hasError
    readonly property bool showContent: !isLoading && !hasError && !!detail.participants && detail.participants.length > 0
    property real loadingPulse: 0.62

    Component.onCompleted: _captureInitial()

    SequentialAnimation on loadingPulse {
        running: page.showLoadingState
        loops: Animation.Infinite
        NumberAnimation { to: 0.96; duration: 720; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.62; duration: 720; easing.type: Easing.InOutSine }
    }

    function _captureInitial() {
        var md = Lcu.matchDetail || {}
        var gid = Number(md.gameId || -1)
        if (gid > 0) {
            myGameId = gid
            detail = md
        }
    }

    Connections {
        target: Lcu
        function onMatchDetailChanged() {
            var md = Lcu.matchDetail || {}
            var gid = Number(md.gameId || -1)
            if (gid > 0) {
                myGameId = gid
                detail = md
            }
        }
    }

    Item {
        id: statePanel
        width: parent ? parent.width : 0
        height: (page.showLoadingState || page.hasError) ? Math.max(420, page.height - 96) : 0
        visible: page.showLoadingState || page.hasError

        Rectangle {
            anchors.fill: parent
            visible: page.showLoadingState
            color: FluTheme.dark ? "#0f1116" : "#f7f8fb"
            opacity: 0.92
        }

        ColumnLayout {
            visible: page.showLoadingState
            anchors.fill: parent
            anchors.margins: 12
            spacing: 14

            Repeater {
                model: 2
                delegate: FluArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: index === 0 ? 90 : 52
                    paddings: 16
                    color: FluTheme.dark ? "#171a22" : "#ffffff"
                    opacity: 0.74 + page.loadingPulse * 0.14

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8
                        Rectangle {
                            width: index === 0 ? 220 : 120
                            height: index === 0 ? 14 : 12
                            radius: height / 2
                            color: FluTheme.dark ? "#2a2f3b" : "#e4e8f0"
                        }
                        Rectangle {
                            visible: index === 0
                            width: 160
                            height: 11
                            radius: height / 2
                            color: FluTheme.dark ? "#2a2f3b" : "#e4e8f0"
                        }
                    }
                }
            }

            Repeater {
                model: 10
                delegate: FluArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    paddings: 12
                    color: FluTheme.dark ? "#171a22" : "#ffffff"
                    opacity: 0.70 + page.loadingPulse * 0.16

                    RowLayout {
                        anchors.fill: parent
                        spacing: 10

                        Rectangle {
                            width: 48
                            height: 48
                            radius: 24
                            color: FluTheme.dark ? "#252b36" : "#dfe5ef"
                        }
                        Rectangle {
                            width: 88
                            height: 12
                            radius: 6
                            color: FluTheme.dark ? "#2a2f3b" : "#e4e8f0"
                        }
                        Rectangle {
                            width: 72
                            height: 12
                            radius: 6
                            color: FluTheme.dark ? "#2a2f3b" : "#e4e8f0"
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: FluTheme.dark ? "#2a2f3b" : "#e4e8f0"
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            FluText {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("正在加载战绩详情...")
                color: FluColors.Grey120
                font.pixelSize: 13
                opacity: 0.72 + page.loadingPulse * 0.14
            }
        }

        FluText {
            visible: page.hasError
            anchors.centerIn: parent
            text: qsTr("加载失败：") + (detail.error || "")
            color: "#c64343"
        }
    }

    Loader {
        id: contentLoader
        active: page.showContent
        width: parent ? parent.width : 0
        height: item ? item.implicitHeight : 0
        visible: opacity > 0.01 || page.showContent
        enabled: page.showContent
        opacity: page.showContent ? 1 : 0
        y: page.showContent ? 0 : 14

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        sourceComponent: Component {
            MatchDetailContent {
                width: page.width
                detail: page.detail
                myGameId: page.myGameId
            }
        }
    }
}
