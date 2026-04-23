import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"
import "../js/fmt.js" as Fmt

Item {
    id: root
    property double myGameId: -1
    property var detail: ({})
    property var participants: detail.participants || []
    property var teams: detail.teamStats || []
    property var blueTeam: participants.filter(function(p){ return p.teamId === 100 })
    property var redTeam:  participants.filter(function(p){ return p.teamId === 200 })
    property var blueStat: teams.find(function(t){ return t.teamId === 100 }) || {}
    property var redStat:  teams.find(function(t){ return t.teamId === 200 }) || {}
    property bool compactRows: width < 980
    property int rowGap: compactRows ? 6 : 8
    property int participantRowHeight: compactRows ? 72 : 76
    property int loadoutColWidth: detail.usesAugments === true
        ? (compactRows ? 146 : 160)
        : (compactRows ? 116 : 124)
    property int nameColWidth: compactRows ? 128 : 170
    property int kdaColWidth: compactRows ? 78 : 96
    property int csColWidth: compactRows ? 60 : 72
    property int damageColWidth: compactRows ? 82 : 110
    property int itemSize: compactRows ? 22 : 25
    property int itemsColWidth: 7 * itemSize + 7 * 3 + 6
    property int scoreColWidth: compactRows ? 60 : 66
    property int champIconSize: compactRows ? 44 : 48
    property int spellIconSize: compactRows ? 20 : 22
    property int augmentIconSize: compactRows ? 22 : 24

    implicitWidth: width
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout
        width: root.width
        spacing: 14

        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 90
            paddings: 16

            RowLayout {
                anchors.fill: parent
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 6
                    Layout.fillHeight: true
                    radius: 3
                    color: root.blueStat.win ? "#4684d4" : "#c64343"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        spacing: 10
                        QueueBadge { queueId: root.detail.queueId || 0 }
                        FluText {
                            text: Fmt.absoluteTime(root.detail.gameCreation)
                            color: FluColors.Grey120
                            font.pixelSize: 12
                        }
                        FluText {
                            text: Fmt.relativeTime(root.detail.gameCreation)
                            color: FluColors.Grey120
                            font.pixelSize: 12
                        }
                    }
                    FluText {
                        text: qsTr("时长 ") + Fmt.duration(root.detail.gameDuration || 0)
                        color: FluColors.Grey120
                        font.pixelSize: 12
                    }
                }

                Item { Layout.fillWidth: true }

                FluFilledButton {
                    text: qsTr("AI 复盘")
                    enabled: root.myGameId > 0
                    onClicked: aiDialog.openOverview()
                }

                FluButton {
                    text: qsTr("重看回放")
                    enabled: Lcu.connected && root.myGameId > 0
                    onClicked: Lcu.watchReplay(root.myGameId)
                }

                FluText {
                    text: root.blueStat.win ? qsTr("蓝方胜利") : qsTr("蓝方失败")
                    font: FluTextStyle.Title
                    color: root.blueStat.win ? "#4684d4" : "#c64343"
                }
            }
        }

        TeamHeader {
            teamId: 100
            teamStat: root.blueStat
        }

        Repeater {
            model: root.blueTeam
            delegate: ParticipantRow {
                participant: modelData
                onClicked: participant.puuid
                    ? Lcu.openSummonerProfileByPuuid(participant.puuid)
                    : Lcu.openSummonerProfile(participant.summonerName)
            }
        }

        TeamHeader {
            teamId: 200
            teamStat: root.redStat
        }

        Repeater {
            model: root.redTeam
            delegate: ParticipantRow {
                participant: modelData
                onClicked: participant.puuid
                    ? Lcu.openSummonerProfileByPuuid(participant.puuid)
                    : Lcu.openSummonerProfile(participant.summonerName)
            }
        }
    }

    component TeamHeader: FluArea {
        property int teamId: 100
        property var teamStat: ({})
        Layout.fillWidth: true
        Layout.preferredHeight: 52
        paddings: 12
        color: teamId === 100
            ? (FluTheme.dark ? "#1a2638" : "#e3ecf8")
            : (FluTheme.dark ? "#38191a" : "#f8e3e3")
        border.color: "transparent"

        RowLayout {
            anchors.fill: parent
            spacing: 18
            FluText {
                text: teamId === 100 ? qsTr("蓝方") : qsTr("红方")
                font: FluTextStyle.Subtitle
                color: teamId === 100 ? "#4684d4" : "#c64343"
            }
            FluText {
                text: teamStat.win ? qsTr("胜") : qsTr("败")
                color: teamStat.win ? "#3ea04a" : "#c64343"
                font.bold: true
            }
            Rectangle { width: 1; height: 20; color: FluColors.Grey120; opacity: 0.3 }
            StatChip { icon: "⚔"; text: (teamStat.kills || 0) + qsTr(" 击杀") }
            StatChip { icon: "💰"; text: Fmt.bigNum(teamStat.gold || 0) }
            StatChip { icon: "🏰"; text: (teamStat.towerKills || 0) + qsTr(" 塔") }
            StatChip { icon: "🐉"; text: (teamStat.dragonKills || 0) + qsTr(" 龙") }
            StatChip { icon: "👑"; text: (teamStat.baronKills || 0) + qsTr(" 男爵") }
            Item { Layout.fillWidth: true }
        }
    }

    component StatChip: RowLayout {
        property string icon: ""
        property string text: ""
        spacing: 4
        FluText { text: icon; font.pixelSize: 14 }
        FluText { text: parent.text; color: FluColors.Grey120; font.pixelSize: 12 }
    }

    component ParticipantRow: FluArea {
        id: row
        property var participant: ({})
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: root.participantRowHeight
        paddings: 10
        clip: true

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.clicked()
        }

        RowLayout {
            anchors.fill: parent
            spacing: root.rowGap

            Item {
                Layout.preferredWidth: root.loadoutColWidth
                Layout.minimumWidth: root.loadoutColWidth
                Layout.maximumWidth: root.loadoutColWidth
                Layout.preferredHeight: root.compactRows ? 50 : 52
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    ChampionIcon {
                        championId: participant.championId || 0
                        size: root.champIconSize
                        Layout.alignment: Qt.AlignVCenter
                    }

                    SpellPair {
                        spell1: participant.spell1Id || 0
                        spell2: participant.spell2Id || 0
                        size: root.spellIconSize
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Only one of the two cells is ever instantiated — avoids
                    // building 6 AugmentIcons per row in non-arena modes (and
                    // vice versa) just to hide them.
                    Loader {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: root.detail.usesAugments === true
                            ? (3 * root.augmentIconSize + 4)
                            : (root.compactRows ? 42 : 46)
                        Layout.preferredHeight: root.detail.usesAugments === true
                            ? (2 * root.augmentIconSize + 2)
                            : (root.compactRows ? 42 : 46)
                        sourceComponent: root.detail.usesAugments === true
                            ? augmentsCell
                            : runesCell
                    }
                    Component {
                        id: augmentsCell
                        GridLayout {
                            columns: 3
                            columnSpacing: 2
                            rowSpacing: 2
                            Repeater {
                                model: (participant.augments || []).filter(function(a){ return a > 0 }).slice(0, 6)
                                delegate: AugmentIcon {
                                    augmentId: modelData
                                    size: root.augmentIconSize
                                }
                            }
                        }
                    }
                    Component {
                        id: runesCell
                        Item {
                            RuneBadge {
                                anchors.centerIn: parent
                                keystoneId: (participant.perks && participant.perks[0]) || 0
                                subStyleId: participant.subStyleId || 0
                                size: root.compactRows ? 36 : 40
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: root.nameColWidth
                Layout.minimumWidth: root.nameColWidth
                Layout.maximumWidth: root.nameColWidth
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    FluText {
                        text: {
                            var nm = participant.summonerName || "?"
                            var tg = participant.tagLine || ""
                            return tg.length > 0 ? nm + " #" + tg : nm
                        }
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    FluIconButton {
                        iconSource: FluentIcons.Copy
                        iconSize: 11
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        visible: (participant.summonerName || "").length > 0
                        onClicked: {
                            var nm = participant.summonerName || ""
                            var tg = participant.tagLine || ""
                            Lcu.copyToClipboard(tg.length > 0 ? nm + "#" + tg : nm)
                        }
                    }
                }

                FluText {
                    text: qsTr("分数 ") + Math.round(participant.score || 0)
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
            }

            ColumnLayout {
                Layout.preferredWidth: root.kdaColWidth
                Layout.minimumWidth: root.kdaColWidth
                Layout.maximumWidth: root.kdaColWidth
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                FluText {
                    text: (participant.kills || 0) + " / "
                        + "<span style=\"color:#c64343\">" + (participant.deaths || 0) + "</span> / "
                        + (participant.assists || 0)
                    textFormat: Text.RichText
                    font.bold: true
                }
                FluText {
                    text: Fmt.kdaRatio(participant.kills||0, participant.deaths||0, participant.assists||0) + " KDA"
                    color: Fmt.kdaColor(parseFloat(Fmt.kdaRatio(participant.kills||0, participant.deaths||0, participant.assists||0)))
                    font.pixelSize: 11
                }
            }

            ColumnLayout {
                Layout.preferredWidth: root.csColWidth
                Layout.minimumWidth: root.csColWidth
                Layout.maximumWidth: root.csColWidth
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                FluText { text: "CS " + (participant.cs || 0); font.pixelSize: 12 }
                FluText { text: Fmt.bigNum(participant.gold || 0); color: FluColors.Grey120; font.pixelSize: 11 }
            }

            DamageBar {
                Layout.preferredWidth: root.damageColWidth
                Layout.minimumWidth: root.damageColWidth
                Layout.maximumWidth: root.damageColWidth
                Layout.alignment: Qt.AlignVCenter
                damage: participant.damage || 0
                share: participant.damageShare || 0
                teamId: participant.teamId || 100
            }

            Item {
                Layout.preferredWidth: root.itemsColWidth
                Layout.minimumWidth: root.itemsColWidth
                Layout.maximumWidth: root.itemsColWidth
                Layout.preferredHeight: root.itemSize
                Layout.alignment: Qt.AlignVCenter

                ItemRow {
                    anchors.fill: parent
                    items: participant.items || []
                    slotSize: root.itemSize
                }
            }

            Item {
                Layout.preferredWidth: root.scoreColWidth
                Layout.minimumWidth: root.scoreColWidth
                Layout.maximumWidth: root.scoreColWidth
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 28

                ScoreBadge {
                    anchors.centerIn: parent
                    score: participant.score || 0
                    tags: participant.tags || []
                }
            }
        }
    }

    FluPopup {
        id: aiDialog
        width: Math.min(780, root.width - 60)
        height: 680
        closePolicy: Popup.CloseOnEscape

        property string aiContent: ""
        property string errorText: ""
        property bool aiLoading: false
        property string aiMode: "overview"

        function openOverview() {
            aiMode = "overview"
            aiContent = ""
            errorText = ""
            aiLoading = true
            open()
            Lcu.analyzeMatch(root.myGameId, "overview", "")
        }

        onClosed: {
            Lcu.cancelAnalysis()
            aiContent = ""
            errorText = ""
            aiLoading = false
        }

        Connections {
            target: Lcu
            enabled: aiDialog.opened

            function onAiAnalysisStarted() {
                aiDialog.aiContent = ""
                aiDialog.errorText = ""
                aiDialog.aiLoading = true
            }
            function onAiAnalysisChunk(chunk) {
                aiDialog.aiContent += chunk
            }
            function onAiAnalysisDone() {
                aiDialog.aiLoading = false
            }
            function onAiAnalysisError(msg) {
                aiDialog.aiLoading = false
                aiDialog.errorText = msg
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                FluText { text: qsTr("AI 复盘"); font: FluTextStyle.Title }
                FluText {
                    text: aiDialog.aiLoading ? qsTr("分析中…") : (aiDialog.errorText.length > 0 ? qsTr("失败") : qsTr("完成"))
                    color: aiDialog.errorText.length > 0 ? "#c64343" : FluColors.Grey120
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true }
                FluIconButton {
                    iconSource: FluentIcons.ChromeClose
                    iconSize: 12
                    onClicked: aiDialog.close()
                }
            }

            FluText {
                visible: aiDialog.errorText.length > 0
                text: aiDialog.errorText
                color: "#c64343"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Flickable {
                id: aiFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: aiText.implicitHeight + 8
                contentWidth: width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: FluScrollBar {}
                onContentHeightChanged: if (aiDialog.aiLoading) contentY = Math.max(0, contentHeight - height)

                FluText {
                    id: aiText
                    width: parent.width - 8
                    text: aiDialog.aiContent.length > 0
                        ? aiDialog.aiContent
                        : (aiDialog.aiLoading ? qsTr("正在等待 AI 回复…") : "")
                    textFormat: Text.MarkdownText
                    wrapMode: Text.WordWrap
                    color: aiDialog.aiContent.length > 0 ? undefined : FluColors.Grey120
                }
            }

            RowLayout {
                Layout.fillWidth: true
                FluText {
                    text: qsTr("数据仅来自本场战绩，不会发送你的账号信息")
                    color: FluColors.Grey120
                    font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                FluButton {
                    text: qsTr("重新生成")
                    enabled: !aiDialog.aiLoading && root.myGameId > 0
                    onClicked: {
                        aiDialog.aiContent = ""
                        aiDialog.errorText = ""
                        aiDialog.aiLoading = true
                        Lcu.analyzeMatch(root.myGameId, aiDialog.aiMode, "")
                    }
                }
            }
        }
    }
}
