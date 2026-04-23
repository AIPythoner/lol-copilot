import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleTask
    title: qsTr("最近队友")
    property int requestedCount: 30

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
                    Layout.fillWidth: true
                    spacing: 10
                    FluToggleButton {
                        text: qsTr("分析 30 场")
                        checked: page.requestedCount === 30
                        enabled: Lcu.connected
                        clickListener: function() {
                            page.requestedCount = 30
                            Lcu.loadTeammates(30)
                        }
                    }
                    FluToggleButton {
                        text: qsTr("分析 50 场")
                        checked: page.requestedCount === 50
                        enabled: Lcu.connected
                        clickListener: function() {
                            page.requestedCount = 50
                            Lcu.loadTeammates(50)
                        }
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
        Layout.preferredHeight: 92
        paddings: 12

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: if (entry.puuid) Lcu.openSummonerProfileByPuuid(entry.puuid)
        }

        RowLayout {
            anchors.fill: parent
            spacing: 14

            ProfileIcon {
                iconId: entry.profileIconId || 29
                size: 52
                level: entry.summonerLevel || 0
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    FluText {
                        text: entry.displayName || "?"
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    FluText {
                        Layout.preferredWidth: 86
                        horizontalAlignment: Text.AlignRight
                        text: qsTr("同队 ") + entry.gamesTogether + qsTr(" 次")
                        color: FluColors.Grey120
                        font.pixelSize: 12
                    }

                    FluText {
                        Layout.preferredWidth: 78
                        horizontalAlignment: Text.AlignRight
                        text: entry.winsTogether + qsTr(" 胜 / ")
                            + (entry.gamesTogether - entry.winsTogether) + qsTr(" 负")
                        color: FluColors.Grey120
                        font.pixelSize: 12
                    }

                    FluText {
                        Layout.preferredWidth: 54
                        horizontalAlignment: Text.AlignRight
                        text: Math.round((entry.winRate || 0) * 100) + "%"
                        color: (entry.winRate || 0) >= 0.55 ? "#3ea04a"
                             : (entry.winRate || 0) >= 0.45 ? FluColors.Grey120 : "#c64343"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        radius: 4
                        color: FluTheme.dark ? "#2a2a2a" : "#e4e4ea"

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * (entry.gamesTogether / maxGames)
                            radius: parent.radius
                            color: "#4684d4"
                        }
                    }

                    FluText {
                        Layout.preferredWidth: 118
                        horizontalAlignment: Text.AlignRight
                        text: qsTr("最高 ") + entry.gamesTogether + qsTr(" 场同队")
                        color: FluColors.Grey120
                        font.pixelSize: 11
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 176
                Layout.minimumWidth: 176
                Layout.maximumWidth: 176
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Repeater {
                        model: (entry.championIdsSeen || []).slice(0, 5)
                        delegate: ChampionIcon {
                            championId: modelData
                            size: 28
                        }
                    }
                }

                FluText {
                    Layout.alignment: Qt.AlignRight
                    text: qsTr("点击查看召唤师主页")
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
            }
        }
    }
}
