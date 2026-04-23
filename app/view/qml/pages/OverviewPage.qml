import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleTask
    title: qsTr("我的生涯")

    ColumnLayout {
        width: parent.width
        spacing: 16

        // ===== profile banner =====
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 130
            paddings: 16

            RowLayout {
                anchors.fill: parent
                spacing: 18

                ProfileIcon {
                    iconId: (Lcu.summoner && Lcu.summoner.profileIconId) || 0
                    level: (Lcu.summoner && Lcu.summoner.summonerLevel) || 0
                    size: 84
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6

                    RowLayout {
                        spacing: 10
                        Rectangle {
                            width: 12; height: 12; radius: 6
                            color: Lcu.connected ? "#3ea04a" : "#c64343"
                        }
                        FluText {
                            text: Lcu.summoner && (Lcu.summoner.gameName || Lcu.summoner.displayName)
                                ? (Lcu.summoner.gameName || Lcu.summoner.displayName)
                                  + (Lcu.summoner.tagLine ? "#" + Lcu.summoner.tagLine : "")
                                : qsTr("未连接")
                            font: FluTextStyle.Title
                        }
                        FluText {
                            visible: Lcu.connected
                            text: qsTr("阶段：") + (Lcu.phase || "None")
                            color: FluColors.Grey120
                        }
                    }

                    FluText {
                        visible: Lcu.connected
                        text: qsTr("等级 ") + ((Lcu.summoner && Lcu.summoner.summonerLevel) || 0)
                        color: FluColors.Grey120
                    }
                }

                ColumnLayout {
                    spacing: 6
                    Layout.alignment: Qt.AlignVCenter
                    FluFilledButton {
                        text: qsTr("刷新")
                        onClicked: Lcu.refresh()
                    }
                    FluButton {
                        text: qsTr("加载 100 场英雄池")
                        enabled: Lcu.connected
                        onClicked: Lcu.loadChampionPool(100)
                    }
                }
            }
        }

        // ===== ranked cards =====
        FluText {
            text: qsTr("段位")
            font: FluTextStyle.Subtitle
            visible: Lcu.connected
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            rowSpacing: 10
            columnSpacing: 10
            visible: Lcu.connected

            Repeater {
                model: Lcu.ranked && Lcu.ranked.queues ? Lcu.ranked.queues : []
                delegate: FluArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 112
                    paddings: 14

                    RowLayout {
                        anchors.fill: parent
                        spacing: 12

                        Image {
                            Layout.preferredWidth: 60
                            Layout.preferredHeight: 60
                            Layout.alignment: Qt.AlignVCenter
                            smooth: true
                            fillMode: Image.PreserveAspectFit
                            source: Lcu.tierEmblem(modelData.tier || "UNRANKED")
                            sourceSize.width: 120
                            sourceSize.height: 120
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            FluText {
                                text: _queueLabel(modelData.queueType)
                                color: FluColors.Grey120
                                font.pixelSize: 11
                            }
                            FluText {
                                text: (modelData.tier || "UNRANKED") + " " + (modelData.division || "")
                                font: FluTextStyle.Subtitle
                            }
                            FluText {
                                text: (modelData.leaguePoints || 0) + " LP"
                                color: FluColors.Grey120
                                font.pixelSize: 12
                            }
                            FluText {
                                text: (modelData.wins||0) + qsTr("胜 ") + (modelData.losses||0) + qsTr("负  ")
                                    + ((modelData.wins||0)+(modelData.losses||0) > 0
                                        ? Math.round(100 * modelData.wins / (modelData.wins+modelData.losses))
                                        : 0) + "%"
                                color: FluColors.Grey120
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            FluArea {
                visible: !Lcu.ranked || !Lcu.ranked.queues || Lcu.ranked.queues.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                paddings: 14
                FluText {
                    anchors.centerIn: parent
                    text: qsTr("暂无段位数据")
                    color: FluColors.Grey120
                }
            }
        }

        // ===== recent games strip =====
        FluText {
            text: qsTr("最近 20 场")
            font: FluTextStyle.Subtitle
            visible: Lcu.connected
        }

        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 96
            paddings: 14
            visible: Lcu.connected

            RowLayout {
                anchors.fill: parent
                spacing: 4

                Repeater {
                    model: (Lcu.matches || []).slice(0, 20)
                    delegate: ColumnLayout {
                        spacing: 4
                        ChampionIcon {
                            championId: modelData.championId || 0
                            size: 40
                            showTooltip: true
                        }
                        Rectangle {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 4
                            radius: 2
                            color: modelData.win ? "#3ea04a" : "#c64343"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Lcu.openMatchDetail(modelData.gameId)
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // ===== quick actions =====
        FluText {
            text: qsTr("快速操作")
            font: FluTextStyle.Subtitle
            visible: Lcu.connected
        }

        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            paddings: 14
            visible: Lcu.connected

            RowLayout {
                anchors.fill: parent
                spacing: 10

                FluButton {
                    text: qsTr("接受对局")
                    enabled: Lcu.phase === "ReadyCheck"
                    onClicked: Lcu.acceptReady()
                }
                FluButton {
                    text: qsTr("拒绝对局")
                    enabled: Lcu.phase === "ReadyCheck"
                    onClicked: Lcu.declineReady()
                }
                FluButton {
                    text: qsTr("解散房间")
                    onClicked: Lcu.dodgeLobby()
                }
                Item { Layout.fillWidth: true }
                FluText {
                    text: qsTr("更多自动动作见左下设置")
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
            }
        }

        FluText {
            visible: !Lcu.connected
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("请启动英雄联盟客户端后自动连接")
            color: FluColors.Grey120
        }
    }

    function _queueLabel(q) {
        switch (q) {
            case "RANKED_SOLO_5x5": return qsTr("单双排")
            case "RANKED_FLEX_SR":  return qsTr("灵活组排")
            case "RANKED_TFT": return qsTr("云顶之弈排位")
            case "RANKED_TFT_DOUBLE_UP": return qsTr("云顶双人")
            case "CHERRY": return qsTr("斗魂竞技场")
            default: return q || ""
        }
    }

}
