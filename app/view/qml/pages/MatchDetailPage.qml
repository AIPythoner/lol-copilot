import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"
import "../js/fmt.js" as Fmt

FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleTask
    title: qsTr("对局详情")

    // Keep a single detail page in the navigation stack. Repeated Standard
    // pushes retain old QML pages, and every retained page still reacts to
    // matchDetailChanged, re-running row/icon loaders in the background.
    property double myGameId: -1
    property var detail: ({})
    property bool isLoading: detail.loading === true || (myGameId > 0 && !detail.participants && !detail.error)
    property bool hasError: !!detail.error
    property var participants: detail.participants || []
    property var teams: detail.teamStats || []
    property var blueTeam: participants.filter(function(p){ return p.teamId === 100 })
    property var redTeam:  participants.filter(function(p){ return p.teamId === 200 })
    property var blueStat: teams.find(function(t){ return t.teamId === 100 }) || {}
    property var redStat:  teams.find(function(t){ return t.teamId === 200 }) || {}
    property int visibleRows: 0
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

    Component.onCompleted: _captureInitial()
    onParticipantsChanged: {
        visibleRows = 0
        if (participants.length > 0) rowRevealTimer.restart()
    }

    Timer {
        id: rowRevealTimer
        interval: 18
        repeat: true
        onTriggered: {
            visibleRows = Math.min(participants.length, visibleRows + 2)
            if (visibleRows >= participants.length) stop()
        }
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

    // ===== loading / error overlays =====
    Item {
        visible: isLoading || hasError
        width: parent.width
        height: Math.max(380, page.height - 96)

        ElegantLoader {
            visible: isLoading
            anchors.fill: parent
            text: qsTr("加载对局详情…")
            accent: "#d4a04a"
            ringSize: 34
        }

        FluText {
            visible: hasError
            anchors.centerIn: parent
            text: qsTr("加载失败：") + (detail.error || "")
            color: "#c64343"
        }
    }

    ColumnLayout {
        visible: !isLoading && !hasError && participants.length > 0
        width: parent.width
        spacing: 14

        // ===== header =====
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
                    color: blueStat.win ? "#4684d4" : "#c64343"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        spacing: 10
                        QueueBadge { queueId: detail.queueId || 0 }
                        FluText {
                            text: Fmt.absoluteTime(detail.gameCreation)
                            color: FluColors.Grey120
                            font.pixelSize: 12
                        }
                        FluText {
                            text: Fmt.relativeTime(detail.gameCreation)
                            color: FluColors.Grey120
                            font.pixelSize: 12
                        }
                    }
                    FluText {
                        text: qsTr("时长 ") + Fmt.duration(detail.gameDuration || 0)
                        color: FluColors.Grey120
                        font.pixelSize: 12
                    }
                }

                Item { Layout.fillWidth: true }

                FluFilledButton {
                    text: qsTr("AI 复盘")
                    enabled: page.myGameId > 0
                    visible: !isLoading && !hasError
                    onClicked: aiDialog.openOverview()
                }

                FluButton {
                    text: qsTr("重看回放")
                    enabled: Lcu.connected && page.myGameId > 0
                    visible: !isLoading && !hasError
                    onClicked: Lcu.watchReplay(page.myGameId)
                }

                FluText {
                    text: blueStat.win ? qsTr("蓝方胜利") : qsTr("蓝方失败")
                    font: FluTextStyle.Title
                    color: blueStat.win ? "#4684d4" : "#c64343"
                }
            }
        }

        // ===== blue team header =====
        TeamHeader {
            teamId: 100
            teamStat: blueStat
        }

        Repeater {
            model: blueTeam
            delegate: Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: active ? page.participantRowHeight : 0
                active: index < visibleRows
                property var rowParticipant: modelData
                property int rowOrder: index
                sourceComponent: ParticipantRow {
                    participant: rowParticipant
                    revealOrder: rowOrder
                    onClicked: rowParticipant.puuid
                        ? Lcu.openSummonerProfileByPuuid(rowParticipant.puuid)
                        : Lcu.openSummonerProfile(rowParticipant.summonerName)
                }
            }
        }

        // ===== red team header =====
        TeamHeader {
            teamId: 200
            teamStat: redStat
        }

        Repeater {
            model: redTeam
            delegate: Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: active ? page.participantRowHeight : 0
                active: blueTeam.length + index < visibleRows
                property var rowParticipant: modelData
                property int rowOrder: blueTeam.length + index
                sourceComponent: ParticipantRow {
                    participant: rowParticipant
                    revealOrder: rowOrder
                    onClicked: rowParticipant.puuid
                        ? Lcu.openSummonerProfileByPuuid(rowParticipant.puuid)
                        : Lcu.openSummonerProfile(rowParticipant.summonerName)
                }
            }
        }

    }

    // ===== inline components =====
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
        property int revealOrder: 0
        property bool iconsReady: false
        signal clicked()

        Layout.preferredHeight: page.participantRowHeight
        paddings: 10
        clip: true

        Component.onCompleted: iconDelay.start()

        Timer {
            id: iconDelay
            interval: 12 + row.revealOrder * 8
            repeat: false
            onTriggered: row.iconsReady = true
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.clicked()
        }

        RowLayout {
            anchors.fill: parent
            spacing: page.rowGap

            // icon block
            Item {
                Layout.preferredWidth: page.loadoutColWidth
                Layout.minimumWidth: page.loadoutColWidth
                Layout.maximumWidth: page.loadoutColWidth
                Layout.preferredHeight: page.compactRows ? 50 : 52
                Layout.alignment: Qt.AlignVCenter
                clip: true

                Rectangle {
                    anchors.fill: parent
                    visible: !row.iconsReady
                    radius: 8
                    color: FluTheme.dark ? "#242424" : "#ececf2"
                    opacity: 0.45
                }

                Loader {
                    anchors.fill: parent
                    active: row.iconsReady
                    sourceComponent: RowLayout {
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        ChampionIcon {
                            championId: participant.championId || 0
                            size: page.champIconSize
                            Layout.alignment: Qt.AlignVCenter
                        }
                        SpellPair {
                            spell1: participant.spell1Id || 0
                            spell2: participant.spell2Id || 0
                            size: page.spellIconSize
                            Layout.alignment: Qt.AlignVCenter
                        }
                        // Arena / Hexakill modes show augments instead of runes
                        GridLayout {
                            visible: detail.usesAugments === true
                            columns: 3
                            columnSpacing: 2
                            rowSpacing: 2
                            Layout.preferredWidth: 3 * page.augmentIconSize + 4
                            Layout.preferredHeight: 2 * page.augmentIconSize + 2
                            Layout.alignment: Qt.AlignVCenter
                            Repeater {
                                model: (participant.augments || []).filter(function(a){ return a > 0 }).slice(0, 6)
                                delegate: AugmentIcon {
                                    augmentId: modelData
                                    size: page.augmentIconSize
                                }
                            }
                        }
                        Item {
                            visible: !detail.usesAugments
                            Layout.preferredWidth: page.compactRows ? 42 : 46
                            Layout.preferredHeight: page.compactRows ? 42 : 46
                            Layout.alignment: Qt.AlignVCenter

                            RuneBadge {
                                anchors.centerIn: parent
                                keystoneId: (participant.perks && participant.perks[0]) || 0
                                subStyleId: participant.subStyleId || 0
                                size: page.compactRows ? 36 : 40
                            }
                        }
                    }
                }
            }

            // name + rank
            ColumnLayout {
                Layout.preferredWidth: page.nameColWidth
                Layout.minimumWidth: page.nameColWidth
                Layout.maximumWidth: page.nameColWidth
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                clip: true
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

            // kda
            ColumnLayout {
                Layout.preferredWidth: page.kdaColWidth
                Layout.minimumWidth: page.kdaColWidth
                Layout.maximumWidth: page.kdaColWidth
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                clip: true
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

            // cs + gold
            ColumnLayout {
                Layout.preferredWidth: page.csColWidth
                Layout.minimumWidth: page.csColWidth
                Layout.maximumWidth: page.csColWidth
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                clip: true
                FluText { text: "CS " + (participant.cs || 0); font.pixelSize: 12 }
                FluText { text: Fmt.bigNum(participant.gold || 0); color: FluColors.Grey120; font.pixelSize: 11 }
            }

            // damage bar
            DamageBar {
                Layout.preferredWidth: page.damageColWidth
                Layout.minimumWidth: page.damageColWidth
                Layout.maximumWidth: page.damageColWidth
                Layout.alignment: Qt.AlignVCenter
                damage: participant.damage || 0
                share: participant.damageShare || 0
                teamId: participant.teamId || 100
            }

            // items
            Item {
                Layout.preferredWidth: page.itemsColWidth
                Layout.minimumWidth: page.itemsColWidth
                Layout.maximumWidth: page.itemsColWidth
                Layout.preferredHeight: page.itemSize
                Layout.alignment: Qt.AlignVCenter
                clip: true
                Rectangle {
                    anchors.fill: parent
                    visible: !row.iconsReady
                    radius: 4
                    color: FluTheme.dark ? "#242424" : "#ececf2"
                    opacity: 0.35
                }
                Loader {
                    anchors.fill: parent
                    active: row.iconsReady
                    sourceComponent: ItemRow {
                        items: participant.items || []
                        slotSize: page.itemSize
                    }
                }
            }

            // score
            Item {
                Layout.preferredWidth: page.scoreColWidth
                Layout.minimumWidth: page.scoreColWidth
                Layout.maximumWidth: page.scoreColWidth
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 28
                clip: true

                ScoreBadge {
                    anchors.centerIn: parent
                    score: participant.score || 0
                    tags: participant.tags || []
                }
            }
        }
    }

    // ===== AI analysis dialog =====
    // Streamed markdown from the bridge's OpenAI-compatible client.
    // Cancelling on close prevents a request that completes after the user
    // dismissed the dialog from stealing cache-slot for a game they didn't
    // want analyzed.
    FluPopup {
        id: aiDialog
        width: Math.min(780, page.width - 60)
        height: Math.min(680, page.height)
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
            Lcu.analyzeMatch(page.myGameId, "overview", "")
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
            function onAiAnalysisStarted(gid, mode) {
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
                // Auto-scroll to bottom while streaming so the user sees
                // the latest chunk without having to drag.
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
                    enabled: !aiDialog.aiLoading && page.myGameId > 0
                    onClicked: {
                        aiDialog.aiContent = ""
                        aiDialog.errorText = ""
                        aiDialog.aiLoading = true
                        // Bypass cache by clearing on the Python side is not
                        // exposed — instead re-fire the request; hitting
                        // cache gives instant redisplay, which is the
                        // usual desired semantics.
                        Lcu.analyzeMatch(page.myGameId, aiDialog.aiMode, "")
                    }
                }
            }
        }
    }
}
