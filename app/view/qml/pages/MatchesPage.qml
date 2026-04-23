import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"
import "../js/fmt.js" as Fmt

FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleInstance
    title: qsTr("最近战绩")

    Component.onCompleted: _refreshIfNeeded()
    onVisibleChanged: if (visible) _refreshIfNeeded()

    Connections {
        target: Lcu
        enabled: page.visible
        function onConnectedChanged() {
            if (Lcu.connected) _refreshIfNeeded()
        }
    }

    property int requestedCount: 20
    property var filterOptions: [
        { label: qsTr("全部模式"), ids: [] },
        { label: qsTr("单双排"), ids: [420] },
        { label: qsTr("灵活组排"), ids: [440] },
        { label: qsTr("匹配"), ids: [430, 490] },
        { label: qsTr("大乱斗"), ids: [450] },
        { label: qsTr("斗魂竞技场"), ids: [1700, 2400] },
        { label: qsTr("人机"), ids: [830, 840, 850, 870, 880, 890] },
        { label: qsTr("自定义"), ids: [0, 3100, 3110, 3120, 3130, 3140, 3160, 3161, 3200, 3210, 3220, 3230] },
    ]
    property int filterIndex: 0
    property var filteredMatches: {
        var all = Lcu.matches || []
        var ids = filterOptions[filterIndex].ids
        if (!ids || ids.length === 0) return all
        return all.filter(function(m){ return ids.indexOf(m.queueId) >= 0 })
    }

    ColumnLayout {
        width: parent.width
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            FluFilledButton {
                text: qsTr("刷新 20 场")
                onClicked: _refresh(20)
                enabled: Lcu.connected && !Lcu.matchesLoading
            }
            FluButton {
                text: qsTr("加载 50 场")
                onClicked: _refresh(50)
                enabled: Lcu.connected && !Lcu.matchesLoading
            }
            FluButton {
                text: qsTr("加载 100 场")
                onClicked: _refresh(100)
                enabled: Lcu.connected && !Lcu.matchesLoading
            }
            Rectangle { width: 1; height: 24; color: FluColors.Grey120; opacity: 0.3 }
            FluText { text: qsTr("按模式筛选"); color: FluColors.Grey120; font.pixelSize: 12 }
            FluComboBox {
                Layout.preferredWidth: 140
                model: filterOptions.map(function(o){ return o.label })
                currentIndex: filterIndex
                onActivated: filterIndex = currentIndex
            }
            Item { Layout.fillWidth: true }
            FluText {
                text: _summary()
                color: FluColors.Grey120
                font.pixelSize: 12
            }
        }

        Repeater {
            model: filteredMatches
            delegate: MatchCard {
                match: modelData
                Layout.fillWidth: true
                onClicked: Lcu.openMatchDetail(modelData.gameId)
            }
        }

        ElegantLoader {
            visible: Lcu.matchesLoading && filteredMatches.length === 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(360, page.height - 150)
            text: qsTr("加载最近战绩…")
            accent: "#d4a04a"
            ringSize: 34
        }

        FluText {
            visible: !Lcu.matchesLoading && filteredMatches.length === 0
            text: {
                if (!Lcu.connected) return qsTr("请先连接客户端")
                if ((Lcu.matches || []).length === 0) return qsTr("暂无数据")
                return qsTr("当前筛选无匹配对局，切换到「全部模式」查看完整列表")
            }
            Layout.alignment: Qt.AlignHCenter
            color: FluColors.Grey120
        }
    }

    function _refresh(count) {
        requestedCount = count
        if (Lcu.connected) Lcu.refreshMatches(count)
    }

    function _refreshIfNeeded() {
        if (Lcu.connected && !Lcu.matchesLoading && (Lcu.matches || []).length === 0) {
            Lcu.refreshMatches(requestedCount)
        }
    }

    function _summary() {
        var visible = filteredMatches
        var all = (Lcu.matches || []).length
        if (visible.length === 0) return ""
        var w = 0
        for (var i = 0; i < visible.length; i++) if (visible[i].win) w++
        var base = visible.length + qsTr(" 场  ") + w + qsTr(" 胜 ") + (visible.length - w) + qsTr(" 负  ")
                 + Math.round(w * 100 / visible.length) + "%"
        if (filterIndex > 0 && all > visible.length) {
            base = base + "  (" + qsTr("过滤自 ") + all + qsTr(" 场") + ")"
        }
        return base
    }

    component MatchCard: FluArea {
        id: card
        property var match: ({})
        signal clicked()
        Layout.preferredHeight: 88
        paddings: 0

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.clicked()
        }

        Rectangle {
            id: sideBar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 5
            color: match.win ? "#3ea04a" : "#c64343"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: sideBar.width + 12
            anchors.rightMargin: 14
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 14

            // champion + spells + rune
            RowLayout {
                spacing: 4
                ChampionIcon { championId: match.championId || 0; size: 56 }
            }

            // queue badge + result
            ColumnLayout {
                Layout.preferredWidth: 110
                spacing: 4
                QueueBadge { queueId: match.queueId || 0 }
                RowLayout {
                    spacing: 4
                    FluText {
                        text: match.win ? qsTr("胜利") : qsTr("失败")
                        color: match.win ? "#3ea04a" : "#c64343"
                        font.bold: true
                    }
                    FluText {
                        text: Fmt.duration(match.gameDuration || 0)
                        color: FluColors.Grey120
                        font.pixelSize: 11
                    }
                }
                FluText {
                    text: Fmt.relativeTime(match.gameCreation)
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
            }

            // kda
            ColumnLayout {
                Layout.preferredWidth: 120
                spacing: 2
                FluText {
                    text: (match.kills||0) + " / "
                        + "<span style=\"color:#c64343\">" + (match.deaths||0) + "</span> / "
                        + (match.assists||0)
                    textFormat: Text.RichText
                    font.bold: true
                    font.pixelSize: 16
                }
                FluText {
                    text: Fmt.kdaRatio(match.kills||0, match.deaths||0, match.assists||0) + " KDA"
                    color: Fmt.kdaColor(parseFloat(Fmt.kdaRatio(match.kills||0, match.deaths||0, match.assists||0)))
                    font.pixelSize: 11
                }
            }

            // cs + gold
            ColumnLayout {
                Layout.preferredWidth: 90
                spacing: 2
                FluText { text: "CS " + (match.cs||0); font.pixelSize: 12 }
                FluText {
                    text: Math.round((match.cs || 0) / Math.max(1, (match.gameDuration||1)/60)) + " / 分钟"
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
                FluText {
                    text: Fmt.bigNum(match.gold||0) + qsTr(" 金币")
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
            }

            Item { Layout.fillWidth: true }

            // action hint
            FluText {
                text: qsTr("查看详情 →")
                color: FluColors.Grey120
                font.pixelSize: 11
            }
        }
    }
}
