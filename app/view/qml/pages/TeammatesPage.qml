import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    launchMode: FluPageType.SingleTask
    title: qsTr("最近队友")

    property int maxGames: {
        var m = 0
        var list = Lcu.teammates || []
        for (var i = 0; i < list.length; i++)
            if (list[i].gamesTogether > m) m = list[i].gamesTogether
        return Math.max(1, m)
    }

    ColumnLayout {
        width: parent.width
        spacing: 12

        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            paddings: 14
            ColumnLayout {
                anchors.fill: parent
                spacing: 6
                FluText {
                    text: qsTr("从最近对局抽取并统计同队出现次数。分析较慢，最多 50 场需要 10-20 秒。")
                    color: FluColors.Grey120
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                RowLayout {
                    spacing: 10
                    FluFilledButton {
                        text: qsTr("分析 30 场")
                        enabled: Lcu.connected
                        onClicked: Lcu.loadTeammates(30)
                    }
                    FluButton {
                        text: qsTr("50 场")
                        enabled: Lcu.connected
                        onClicked: Lcu.loadTeammates(50)
                    }
                    Item { Layout.fillWidth: true }
                    FluText {
                        text: qsTr("共 ") + ((Lcu.teammates || []).length) + qsTr(" 位队友")
                        color: FluColors.Grey120
                        font.pixelSize: 12
                    }
                }
            }
        }

        Repeater {
            model: Lcu.teammates || []
            delegate: TeammateCard { entry: modelData; Layout.fillWidth: true }
        }

        FluText {
            visible: !Lcu.teammates || Lcu.teammates.length === 0
            text: Lcu.connected ? qsTr("请点击按钮开始分析") : qsTr("请先连接客户端")
            Layout.alignment: Qt.AlignHCenter
            color: FluColors.Grey120
        }
    }

    component TeammateCard: FluArea {
        id: card
        property var entry: ({})
        Layout.preferredHeight: 76
        paddings: 10

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: if (entry.puuid) Lcu.openSummonerProfileByPuuid(entry.puuid)
        }

        RowLayout {
            anchors.fill: parent
            spacing: 12

            ProfileIcon {
                iconId: 29   // default icon — LCU match history doesn't include it
                size: 48
            }

            ColumnLayout {
                Layout.preferredWidth: 220
                spacing: 3
                FluText {
                    text: entry.displayName || "?"
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                RowLayout {
                    spacing: 6
                    FluText {
                        text: qsTr("同队 ") + entry.gamesTogether + qsTr(" 次")
                        font.pixelSize: 12
                    }
                    FluText {
                        text: qsTr("胜率 ") + Math.round((entry.winRate || 0) * 100) + "%"
                        color: (entry.winRate || 0) >= 0.55 ? "#3ea04a"
                             : (entry.winRate || 0) >= 0.45 ? FluColors.Grey120 : "#c64343"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }

            // progress bar (relative to top teammate)
            ColumnLayout {
                Layout.preferredWidth: 220
                spacing: 4
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: FluTheme.dark ? "#2a2a2a" : "#e4e4ea"
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * (entry.gamesTogether / maxGames)
                        radius: 4
                        color: "#4684d4"
                    }
                }
                FluText {
                    text: entry.winsTogether + qsTr(" 胜  /  ") + (entry.gamesTogether - entry.winsTogether) + qsTr(" 负")
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
            }

            Item { Layout.fillWidth: true }

            // recent champion icons
            RowLayout {
                spacing: 4
                Repeater {
                    model: (entry.championIdsSeen || []).slice(0, 5)
                    delegate: ChampionIcon {
                        championId: modelData
                        size: 32
                    }
                }
            }
        }
    }
}
