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
    // dataReady = connected AND summoner payload actually populated. We can't
    // rely on Lcu.connected alone: the LCU REST surface comes up before login
    // finishes, and a single transient 5xx during startup used to leave the
    // page with connected=true but empty summoner forever.
    readonly property bool dataReady: Lcu.connected && !!(summoner.gameName || summoner.displayName || summoner.puuid)

    ColumnLayout {
        width: parent.width
        spacing: AppTheme.sp4

        // ===== profile banner =====
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: 138
            paddings: AppTheme.sp5
            radius: AppTheme.radiusLg

            RowLayout {
                anchors.fill: parent
                spacing: AppTheme.sp5

                ProfileIcon {
                    iconId: summoner.profileIconId || 0
                    level: summoner.summonerLevel || 0
                    size: 92
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: AppTheme.sp2

                    RowLayout {
                        spacing: AppTheme.sp3
                        // status dot with soft halo
                        Item {
                            width: 14; height: 14
                            Layout.alignment: Qt.AlignVCenter
                            Rectangle {
                                anchors.centerIn: parent
                                width: 14; height: 14; radius: 7
                                color: "transparent"
                                border.width: 4
                                border.color: Lcu.connected ? AppTheme.positive : AppTheme.negative
                                opacity: 0.22
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 9; height: 9; radius: 4.5
                                color: Lcu.connected ? AppTheme.positive : AppTheme.negative
                            }
                        }
                        FluText {
                            text: (summoner.gameName || summoner.displayName)
                                ? ((summoner.gameName || summoner.displayName)
                                   + (summoner.tagLine ? "#" + summoner.tagLine : ""))
                                : (Lcu.connected
                                    ? qsTr("正在加载客户端数据…")
                                    : qsTr("未连接"))
                            font: FluTextStyle.Title
                        }
                    }

                    RowLayout {
                        spacing: AppTheme.sp2
                        visible: page.dataReady
                        // level pill
                        Rectangle {
                            radius: AppTheme.radiusPill
                            color: AppTheme.accentGlass
                            border.width: 1
                            border.color: AppTheme.accentGlassBorder
                            implicitWidth: lvlText.implicitWidth + 20
                            implicitHeight: lvlText.implicitHeight + 8
                            FluText {
                                id: lvlText
                                anchors.centerIn: parent
                                text: qsTr("等级 ") + (summoner.summonerLevel || 0)
                                color: AppTheme.accentBright
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                    }
                }

                FluFilledButton {
                    text: qsTr("刷新")
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: Lcu.refresh()
                }
            }
        }

        // ===== ranked cards =====
        FluText {
            text: qsTr("段位")
            font: FluTextStyle.Subtitle
            visible: page.dataReady
            Layout.topMargin: AppTheme.sp1
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            rowSpacing: AppTheme.sp3
            columnSpacing: AppTheme.sp3
            visible: page.dataReady

            Repeater {
                model: rankedQueues
                delegate: GlassCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 130
                    paddings: AppTheme.sp3
                    hoverable: true

                    RowLayout {
                        anchors.fill: parent
                        spacing: AppTheme.sp2
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
                            Layout.preferredWidth: 100
                            Layout.preferredHeight: 100
                            Layout.minimumWidth: 100
                            Layout.minimumHeight: 100
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
                            Layout.fillHeight: false
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 3
                            FluText {
                                text: _queueLabel(modelData.queueType)
                                color: AppTheme.textSecondary
                                font.pixelSize: 11
                            }
                            FluText {
                                text: _tierLabel(modelData.tier, modelData.division)
                                font: FluTextStyle.Subtitle
                                color: AppTheme.tierColor(modelData.tier)
                            }
                            FluText {
                                text: (modelData.leaguePoints || 0) + qsTr(" 胜点")
                                color: AppTheme.textSecondary
                                font.pixelSize: 12
                            }
                            FluText {
                                text: (modelData.wins||0) + qsTr("胜 ") + (modelData.losses||0) + qsTr("负  ")
                                    + ((modelData.wins||0)+(modelData.losses||0) > 0
                                        ? Math.round(100 * modelData.wins / (modelData.wins+modelData.losses))
                                        : 0) + "%"
                                color: AppTheme.textSecondary
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            GlassCard {
                visible: rankedQueues.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                paddings: AppTheme.sp4
                FluText {
                    anchors.centerIn: parent
                    text: qsTr("暂无段位数据")
                    color: AppTheme.textSecondary
                }
            }
        }

        // ===== recent games strip =====
        FluText {
            text: qsTr("最近 20 场")
            font: FluTextStyle.Subtitle
            visible: page.dataReady
            Layout.topMargin: AppTheme.sp1
        }

        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            paddings: AppTheme.sp4
            visible: page.dataReady

            RowLayout {
                anchors.fill: parent
                spacing: AppTheme.sp1

                Repeater {
                    model: recentMatches
                    delegate: Item {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 60
                        scale: tileHover.containsMouse ? 1.08 : 1.0
                        Behavior on scale { NumberAnimation { duration: AppTheme.durFast; easing.type: AppTheme.easeStd } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: AppTheme.sp1
                            ChampionIcon {
                                championId: modelData.championId || 0
                                size: 40
                                showTooltip: true
                            }
                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 4
                                radius: 2
                                color: modelData.win ? AppTheme.win : AppTheme.loss
                            }
                        }

                        MouseArea {
                            id: tileHover
                            anchors.fill: parent
                            hoverEnabled: true
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
            visible: page.dataReady
            Layout.topMargin: AppTheme.sp1
        }

        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: 74
            paddings: AppTheme.sp4
            visible: page.dataReady

            RowLayout {
                anchors.fill: parent
                spacing: AppTheme.sp3

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
                    color: AppTheme.textSecondary
                    font.pixelSize: 11
                }
            }
        }

        GlassCard {
            visible: !page.dataReady
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            paddings: AppTheme.sp5

            ColumnLayout {
                anchors.centerIn: parent
                spacing: AppTheme.sp1
                FluText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Lcu.connected
                        ? qsTr("已连上客户端，正在等待召唤师数据返回…")
                        : qsTr("尚未检测到英雄联盟客户端，请先启动游戏客户端")
                    font: FluTextStyle.Subtitle
                }
            }
        }

        // Tick refresh while either disconnected OR connected-but-empty.
        // Connected-but-empty happens when LCU's REST surface answers before
        // login completes, or returns a transient 5xx on the first fetch.
        Timer {
            id: autoReconnectTimer
            interval: 30000
            repeat: true
            running: !page.dataReady && page.visible
            triggeredOnStart: false
            onTriggered: Lcu.refresh()
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
}
