import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleTask
    title: qsTr("我的生涯")

    // [PERF] Hoist QVariant properties so bindings don't re-marshal big
    // dicts on every read. The banner alone touched Lcu.summoner 7 times,
    // each access deep-copying the whole summoner dict.
    readonly property var summoner: Lcu.summoner || ({})
    readonly property var ranked: Lcu.ranked || ({})
    readonly property var rankedQueues: ranked.queues || []
    readonly property var recentMatches: (Lcu.matches || []).slice(0, 20)

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
                    iconId: summoner.profileIconId || 0
                    level: summoner.summonerLevel || 0
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
                            text: (summoner.gameName || summoner.displayName)
                                ? ((summoner.gameName || summoner.displayName)
                                   + (summoner.tagLine ? "#" + summoner.tagLine : ""))
                                : qsTr("未连接")
                            font: FluTextStyle.Title
                        }
                    }

                    FluText {
                        visible: Lcu.connected
                        text: qsTr("等级 ") + (summoner.summonerLevel || 0)
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
                model: rankedQueues
                delegate: FluArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 160
                    paddings: 12

                    RowLayout {
                        anchors.fill: parent
                        spacing: 10
                        clip: false

                        // Layout slot stays moderate so the right-hand text
                        // column gets enough width; the Image overflows the
                        // slot vertically/horizontally so the crest visual
                        // grows without bloating the card too much. CDragon
                        // emblem PNGs bake in heavy transparent padding
                        // around the crest, so the source size must be much
                        // larger than the desired visible size.
                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 130
                            Layout.preferredHeight: 130
                            Layout.minimumWidth: 130
                            Layout.minimumHeight: 130
                            Image {
                                anchors.centerIn: parent
                                width: 280
                                height: 280
                                smooth: true
                                cache: true
                                fillMode: Image.PreserveAspectFit
                                source: Lcu.tierEmblem(modelData.tier || "UNRANKED")
                                sourceSize.width: 560
                                sourceSize.height: 560
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            FluText {
                                text: _queueLabel(modelData.queueType)
                                color: FluColors.Grey120
                                font.pixelSize: 11
                            }
                            FluText {
                                text: _tierLabel(modelData.tier, modelData.division)
                                font: FluTextStyle.Subtitle
                                color: _tierColor(modelData.tier)
                            }
                            FluText {
                                text: (modelData.leaguePoints || 0) + qsTr(" 胜点")
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
                visible: rankedQueues.length === 0
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
                    model: recentMatches
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
            case "RANKED_TFT_TURBO": return qsTr("云顶超玩")
            case "CHERRY": return qsTr("斗魂竞技场")
            default: return q || ""
        }
    }

    function _tierLabel(tier, division) {
        var t = (tier || "").toUpperCase()
        var names = {
            "IRON": "黑铁",
            "BRONZE": "青铜",
            "SILVER": "白银",
            "GOLD": "黄金",
            "PLATINUM": "白金",
            "EMERALD": "翡翠",
            "DIAMOND": "钻石",
            "MASTER": "大师",
            "GRANDMASTER": "宗师",
            "CHALLENGER": "王者",
        }
        if (!t || t === "UNRANKED" || t === "NONE") return qsTr("未定级")
        var label = names[t] || t
        return division ? label + " " + division : label
    }

    function _tierColor(tier) {
        switch ((tier || "").toUpperCase()) {
            case "IRON": return "#7d6c5e"
            case "BRONZE": return "#a07048"
            case "SILVER": return "#9faebd"
            case "GOLD": return "#d4a04a"
            case "PLATINUM": return "#5ac8b5"
            case "EMERALD": return "#3ea04a"
            case "DIAMOND": return "#4684d4"
            case "MASTER": return "#b964e0"
            case "GRANDMASTER": return "#e06c75"
            case "CHALLENGER": return "#f8d458"
            default: return FluColors.Grey120
        }
    }
}
