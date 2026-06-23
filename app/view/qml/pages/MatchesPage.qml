import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"
import "../js/fmt.js" as Fmt

FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleTask
    title: qsTr("最近战绩")

    Component.onCompleted: _refreshIfNeeded()

    Connections {
        target: Lcu
        function onConnectedChanged() {
            if (Lcu.connected) _refreshIfNeeded()
        }
        function onMatchesChanged() {
            // Drive the pending-page state-machine forward whenever new raw
            // matches land. Under a queue filter we may need several rounds
            // of loadMoreMatches before filteredMatches has enough rows.
            page._tryAdvancePending()
            if (page.pageIndex > 0 && page.pageIndex >= page.pageCount()) {
                page.pageIndex = Math.max(0, page.pageCount() - 1)
            }
        }
    }

    property int requestedCount: pageSize
    property int pageSize: 20
    property int pageIndex: 0
    property int pendingPageIndex: -1
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
    // [PERF] Read Lcu.matches once per change. Every access marshals the
    // full match list across the Py↔QML boundary — bindings in this file
    // touched it 5+ times, multiplying that cost on every matchesChanged.
    readonly property var allMatches: Lcu.matches || []
    property var filteredMatches: {
        var ids = filterOptions[filterIndex].ids
        if (!ids || ids.length === 0) return allMatches
        return allMatches.filter(function(m){ return ids.indexOf(m.queueId) >= 0 })
    }
    property var pagedMatches: filteredMatches.slice(pageIndex * pageSize, (pageIndex + 1) * pageSize)

    onFilterIndexChanged: { pageIndex = 0; pendingPageIndex = -1 }

    ColumnLayout {
        width: parent.width
        spacing: AppTheme.sp3

        RowLayout {
            Layout.fillWidth: true
            spacing: AppTheme.sp2
            FluFilledButton {
                text: qsTr("刷新")
                onClicked: _refresh(pageSize)
                enabled: Lcu.connected && !Lcu.matchesLoading
            }
            FluButton {
                text: qsTr("上一页")
                onClicked: _prevPage()
                enabled: pageIndex > 0 && !Lcu.matchesLoading
            }
            FluButton {
                text: qsTr("下一页")
                onClicked: _nextPage()
                enabled: Lcu.connected && !Lcu.matchesLoading
            }
            FluButton {
                text: qsTr("重置")
                onClicked: _refresh(pageSize)
                enabled: Lcu.connected && !Lcu.matchesLoading && allMatches.length > 0
            }
            Rectangle { width: 1; height: 24; color: AppTheme.textSecondary; opacity: 0.3 }
            FluText { text: qsTr("按模式筛选"); color: AppTheme.textSecondary; font.pixelSize: 12 }
            FluComboBox {
                Layout.preferredWidth: 140
                model: filterOptions.map(function(o){ return o.label })
                currentIndex: filterIndex
                onActivated: filterIndex = currentIndex
            }
            Item { Layout.fillWidth: true }
            FluText {
                text: _summary()
                color: AppTheme.textSecondary
                font.pixelSize: 12
            }
        }

        Repeater {
            model: pagedMatches
            delegate: MatchCard {
                match: modelData
                Layout.fillWidth: true
                onClicked: Lcu.openMatchDetail(modelData.gameId)
            }
        }

        ElegantLoader {
            visible: Lcu.matchesLoading && pagedMatches.length === 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(360, page.height - 150)
            text: qsTr("加载最近战绩…")
            accent: AppTheme.accent
            ringSize: 34
        }

        FluText {
            visible: !Lcu.matchesLoading && pagedMatches.length === 0
            text: {
                if (!Lcu.connected) return qsTr("请先连接客户端")
                if (allMatches.length === 0) return qsTr("暂无数据")
                return qsTr("当前筛选无匹配对局，切换到「全部模式」查看完整列表")
            }
            Layout.alignment: Qt.AlignHCenter
            color: AppTheme.textSecondary
        }
    }

    function _refresh(count) {
        requestedCount = count
        pageIndex = 0
        pendingPageIndex = -1
        if (Lcu.connected) Lcu.refreshMatches(count)
    }

    function _refreshIfNeeded() {
        if (Lcu.connected && !Lcu.matchesLoading && allMatches.length === 0) {
            Lcu.refreshMatches(requestedCount)
        }
    }

    function _summary() {
        var visible = filteredMatches
        var all = allMatches.length
        if (visible.length === 0) return ""
        var w = 0
        for (var i = 0; i < visible.length; i++) if (visible[i].win) w++
        var base = visible.length + qsTr(" 场  ") + w + qsTr(" 胜 ") + (visible.length - w) + qsTr(" 负  ")
                 + Math.round(w * 100 / visible.length) + "%"
        if (filterIndex > 0 && all > visible.length) {
            base = base + "  (" + qsTr("过滤自 ") + all + qsTr(" 场") + ")"
        }
        base = base + "  ·  " + qsTr("第 ") + (pageIndex + 1) + " / " + pageCount() + qsTr(" 页")
        return base
    }

    function pageCount() {
        return Math.max(1, Math.ceil(filteredMatches.length / pageSize))
    }

    function _prevPage() {
        if (pageIndex > 0) pageIndex--
    }

    function _nextPage() {
        var next = pageIndex + 1
        if (filteredMatches.length > next * pageSize) {
            pageIndex = next
            return
        }
        if (pendingPageIndex >= 0) return // already chasing more data
        if (Lcu.matchesHasMore) {
            pendingPageIndex = next
            _tryAdvancePending()
        }
    }

    // Pull more raw matches until filteredMatches has enough rows for the
    // target page. LCU's match-history endpoint doesn't support queue-side
    // filtering, so for non-"全部模式" we may need to fetch several batches
    // before the queue we want appears.
    function _tryAdvancePending() {
        if (pendingPageIndex < 0) return
        var target = pendingPageIndex
        if (filteredMatches.length > target * pageSize) {
            pageIndex = target
            pendingPageIndex = -1
            return
        }
        if (!Lcu.matchesHasMore) {
            // backend has nothing more — clamp to whatever we managed to load
            var maxIdx = Math.max(0, pageCount() - 1)
            if (target <= maxIdx && filteredMatches.length > target * pageSize) {
                pageIndex = target
            } else {
                pageIndex = maxIdx
            }
            pendingPageIndex = -1
            return
        }
        if (!Lcu.matchesLoading) {
            Lcu.loadMoreMatches()
        }
    }

    component MatchCard: GlassCard {
        id: card
        property var match: ({})
        Layout.preferredHeight: 88
        paddings: 0
        hoverable: true
        interactive: true

        // [PERF] Per-row KDA was being computed THREE times — once for the
        // text, twice inside the color expression (kdaRatio()+parseFloat).
        // Cache the formatted string and the parsed number once per row.
        readonly property string kdaText: Fmt.kdaRatio(match.kills||0, match.deaths||0, match.assists||0)
        readonly property real kdaValue: parseFloat(card.kdaText)

        Rectangle {
            id: sideBar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 5
            color: match.win ? AppTheme.win : AppTheme.loss
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
                        color: match.win ? AppTheme.win : AppTheme.loss
                        font.bold: true
                    }
                    FluText {
                        text: Fmt.duration(match.gameDuration || 0)
                        color: AppTheme.textSecondary
                        font.pixelSize: 11
                    }
                }
                FluText {
                    text: Fmt.relativeTime(match.gameCreation)
                    color: AppTheme.textSecondary
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
                    text: card.kdaText + " KDA"
                    color: Fmt.kdaColor(card.kdaValue)
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
                    color: AppTheme.textSecondary
                    font.pixelSize: 11
                }
                FluText {
                    text: Fmt.bigNum(match.gold||0) + qsTr(" 金币")
                    color: AppTheme.textSecondary
                    font.pixelSize: 11
                }
            }

            Item { Layout.fillWidth: true }

            // action hint
            FluText {
                text: qsTr("查看详情 →")
                color: AppTheme.textSecondary
                font.pixelSize: 11
            }
        }
    }
}
