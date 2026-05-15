import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"
import "../js/fmt.js" as Fmt

FluScrollablePage {
    id: page
    launchMode: FluPageType.Standard
    title: qsTr("召唤师主页")

    // Snapshot on mount — avoid re-binding when the user navigates to other
    // profiles from within the nav stack (which would make every previous
    // ProfilePage reload its match-card icons and freeze the UI).
    property string myPuuid: ""
    property var result: ({})
    property bool isLoading: result.loading === true || (myPuuid.length > 0 && !result.puuid && !result.error)
    property bool notFound: !!result.error
    property var ranked: (result._ranked && result._ranked.queues) || []
    property var matches: result._matches || []

    Component.onCompleted: {
        var r = Lcu.searchResult || {}
        if (r.puuid) { myPuuid = r.puuid; result = r }
        else if (r.loading && r.puuid) { myPuuid = r.puuid }
        else if (r.loading) { result = r }
    }

    Connections {
        target: Lcu
        function onSearchResultChanged() {
            var r = Lcu.searchResult || {}
            if (myPuuid.length === 0 && r.puuid) myPuuid = r.puuid
            if (myPuuid.length === 0 || r.puuid === myPuuid || r.error) {
                result = r
            }
        }
    }

    // ===== loading / error =====
    ColumnLayout {
        visible: isLoading || notFound
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        FluProgressRing {
            visible: isLoading
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
        }
        FluText {
            visible: isLoading
            text: qsTr("加载召唤师资料…") + (result.query ? ("  " + result.query) : "")
            color: FluColors.Grey120
            font: FluTextStyle.Subtitle
            Layout.alignment: Qt.AlignHCenter
        }
        FluText {
            visible: notFound
            text: qsTr("未找到：") + (result.error || "")
            color: "#c64343"
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // ===== main content =====
    ColumnLayout {
        visible: !isLoading && !notFound && !!result.puuid
        width: parent.width
        spacing: 14

        // ----- banner -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            paddings: 16

            RowLayout {
                anchors.fill: parent
                spacing: 18

                ProfileIcon {
                    iconId: result.profileIconId || 0
                    level: result.summonerLevel || 0
                    size: 76
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    FluText {
                        text: (result.gameName || result.displayName || "?")
                            + (result.tagLine ? "#" + result.tagLine : "")
                        font: FluTextStyle.Title
                    }
                    FluText {
                        text: qsTr("等级 ") + (result.summonerLevel || 0)
                            + "   PUUID " + ((result.puuid || "").slice(0, 8) + "…")
                        color: FluColors.Grey120
                        font.pixelSize: 11
                    }
                }
            }
        }

        // ----- ranked strip -----
        FluText {
            visible: ranked.length > 0
            text: qsTr("段位")
            font: FluTextStyle.Subtitle
        }

        GridLayout {
            visible: ranked.length > 0
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 10
            rowSpacing: 10

            Repeater {
                model: ranked
                delegate: FluArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 112
                    paddings: 14

                    RowLayout {
                        anchors.fill: parent
                        spacing: 14
                        Item {
                            // Reserve a fixed slot so the layout can't shrink
                            // the emblem to its (much smaller) implicit size.
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 84
                            Layout.preferredHeight: 84
                            Layout.minimumWidth: 84
                            Layout.minimumHeight: 84
                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                cache: true
                                source: Lcu.tierEmblem(modelData.tier || "UNRANKED")
                                sourceSize.width: 168
                                sourceSize.height: 168
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
                                font.bold: true
                                color: _tierColor(modelData.tier)
                            }
                            FluText {
                                text: (modelData.leaguePoints || 0) + qsTr(" 胜点  ")
                                    + (modelData.wins || 0) + qsTr("胜 ")
                                    + (modelData.losses || 0) + qsTr("负")
                                color: FluColors.Grey120
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }

        // ----- recent games -----
        FluText {
            text: qsTr("最近 ") + matches.length + qsTr(" 场")
            font: FluTextStyle.Subtitle
            visible: matches.length > 0
        }

        Repeater {
            model: matches
            delegate: MatchCard {
                match: modelData
                Layout.fillWidth: true
                onClicked: Lcu.openMatchDetail(modelData.gameId)
            }
        }

        FluText {
            visible: !isLoading && !notFound && !!result.puuid && matches.length === 0
            text: qsTr("无最近战绩")
            color: FluColors.Grey120
            Layout.alignment: Qt.AlignHCenter
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

    // MatchCard copied from MatchesPage — keep the layout consistent.
    component MatchCard: FluArea {
        id: card
        property var match: ({})
        signal clicked()
        Layout.preferredHeight: 80
        paddings: 0

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.clicked()
        }

        Rectangle {
            id: bar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 5
            color: match.win ? "#3ea04a" : "#c64343"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: bar.width + 12
            anchors.rightMargin: 14
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 14

            ChampionIcon { championId: match.championId || 0; size: 48 }

            ColumnLayout {
                Layout.preferredWidth: 110
                spacing: 3
                QueueBadge { queueId: match.queueId || 0 }
                FluText {
                    text: match.win ? qsTr("胜") : qsTr("败")
                    color: match.win ? "#3ea04a" : "#c64343"
                    font.bold: true
                }
                FluText {
                    text: Fmt.relativeTime(match.gameCreation)
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 100
                spacing: 2
                FluText {
                    text: (match.kills||0) + "/" + (match.deaths||0) + "/" + (match.assists||0)
                    font.bold: true
                    font.pixelSize: 14
                }
                FluText {
                    text: Fmt.kdaRatio(match.kills||0, match.deaths||0, match.assists||0) + " KDA"
                    color: Fmt.kdaColor(parseFloat(Fmt.kdaRatio(match.kills||0, match.deaths||0, match.assists||0)))
                    font.pixelSize: 11
                }
            }

            ColumnLayout {
                spacing: 2
                FluText { text: "CS " + (match.cs||0); font.pixelSize: 12 }
                FluText {
                    text: Fmt.duration(match.gameDuration||0)
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
            }

            Item { Layout.fillWidth: true }

            FluText {
                text: qsTr("详情 →")
                color: FluColors.Grey120
                font.pixelSize: 11
            }
        }
    }
}
