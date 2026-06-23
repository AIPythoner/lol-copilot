import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleTask
    title: qsTr("选人分析")

    Component.onCompleted: if (Lcu.connected) Lcu.refreshChampSelect()

    // [PERF] Cache Lcu.champSelect once. Originally referenced 12+ times
    // (status text, bans, preGroups counter, both teams, empty state) —
    // each access marshalled the whole champSelect dict including bans,
    // both 5-player rosters, and pregroup data. Caching cuts that to one
    // marshal per champSelectChanged signal.
    readonly property var sel: Lcu.champSelect || ({})
    readonly property var preGroups: sel.preGroups || []
    readonly property var bansData: sel.bans
    readonly property var myTeamBans: (bansData && bansData.myTeamBans) || []
    readonly property var theirTeamBans: (bansData && bansData.theirTeamBans) || []
    readonly property var myTeam: sel.myTeam || []
    readonly property var theirTeam: sel.theirTeam || []

    function preGroupColor(puuid) {
        var groups = page.preGroups
        for (var i = 0; i < groups.length; i++) {
            if ((groups[i].puuids || []).indexOf(puuid) !== -1) return groups[i].color
        }
        return ""
    }

    ColumnLayout {
        width: parent.width
        spacing: AppTheme.sp4

        // ===== status header =====
        RowLayout {
            Layout.fillWidth: true
            FluText {
                text: Lcu.phase === "ChampSelect"
                    ? qsTr("选人中")
                      + (sel.phase ? "  ·  " + sel.phase : "")
                    : qsTr("当前不在选人阶段（") + Lcu.phaseLabel + "）"
                font: FluTextStyle.Subtitle
            }
            Item { Layout.fillWidth: true }
            FluText {
                visible: preGroups.length > 0
                text: qsTr("检测到 ") + preGroups.length + qsTr(" 个开黑组")
                color: AppTheme.accent
                font.pixelSize: 12
            }
            FluButton {
                text: qsTr("刷新")
                onClicked: Lcu.refreshChampSelect()
                enabled: Lcu.connected
            }
        }

        // ===== bans =====
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: 68
            paddings: AppTheme.sp3
            visible: bansData !== undefined

            RowLayout {
                anchors.fill: parent
                spacing: AppTheme.sp4

                FluText { text: qsTr("禁用"); color: AppTheme.textSecondary }

                RowLayout {
                    spacing: 6
                    Repeater {
                        model: myTeamBans
                        delegate: BannedChampionIcon { championId: modelData; color: "#4684d4" }
                    }
                }

                Item { Layout.preferredWidth: 16 }

                RowLayout {
                    spacing: 6
                    Repeater {
                        model: theirTeamBans
                        delegate: BannedChampionIcon { championId: modelData; color: "#c64343" }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // ===== teams side by side =====
        RowLayout {
            Layout.fillWidth: true
            spacing: AppTheme.sp4

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: AppTheme.sp2
                FluText {
                    text: qsTr("我方")
                    font: FluTextStyle.Subtitle
                    color: "#4684d4"
                }
                Repeater {
                    model: myTeam
                    delegate: PlayerCard { player: modelData }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: AppTheme.sp2
                FluText {
                    text: qsTr("敌方")
                    font: FluTextStyle.Subtitle
                    color: "#c64343"
                }
                Repeater {
                    model: theirTeam
                    delegate: PlayerCard { player: modelData }
                }
            }
        }

        FluText {
            visible: myTeam.length === 0
            text: Lcu.connected
                ? qsTr("等待选人会话…")
                : qsTr("请先连接客户端")
            Layout.alignment: Qt.AlignHCenter
            color: AppTheme.textSecondary
        }
    }

    component BannedChampionIcon: Item {
        property int championId: 0
        property color color: "#c64343"
        implicitWidth: 36
        implicitHeight: 36

        ChampionIcon {
            anchors.fill: parent
            championId: parent.championId
            opacity: 0.5
            circular: true
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: parent.color
            border.width: 2
            opacity: 0.7
        }

        // X mark
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.9
            height: 2
            color: parent.color
            rotation: 45
        }
    }

    component PlayerCard: GlassCard {
        id: card
        property var player: ({})
        Layout.fillWidth: true
        Layout.preferredHeight: 96
        paddings: 0
        hoverable: !!player.puuid

        // pregroup accent
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 5
            color: {
                var g = preGroupColor(player.puuid || "")
                if (g) return g
                return player.is_me ? "#d4a04a" : "transparent"
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: !!player.puuid ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: !!player.puuid
            onClicked: Lcu.openSummonerProfileByPuuid(player.puuid)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 12

            // champion + position overlay
            Item {
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
                ChampionIcon {
                    anchors.fill: parent
                    championId: player.champion_id || 0
                    size: 56
                }
                PositionIcon {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    position: player.assigned_position || ""
                    size: 22
                    visible: position.length > 0
                }
            }

            // name + tier
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                FluText {
                    text: (player.display_name || "???")
                        + (player.is_me ? qsTr("  (我)") : "")
                    font: FluTextStyle.Body
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                TierBadge {
                    tier: player.ranks && player.ranks.length > 0 ? player.ranks[0].tier : "UNRANKED"
                    division: player.ranks && player.ranks.length > 0 ? player.ranks[0].division : ""
                    leaguePoints: player.ranks && player.ranks.length > 0 ? player.ranks[0].league_points : 0
                    emblemSize: 20
                    showText: true
                }
                RowLayout {
                    spacing: 6
                    FluText {
                        text: qsTr("胜率 ") + Math.round((player.recent_win_rate||0)*100) + "%"
                        color: (player.recent_win_rate||0) >= 0.55 ? AppTheme.win
                             : (player.recent_win_rate||0) >= 0.45 ? AppTheme.textSecondary : AppTheme.loss
                        font.pixelSize: 11
                    }
                    FluText {
                        text: "  KDA " + (player.avg_kda || 0)
                        color: AppTheme.textSecondary
                        font.pixelSize: 11
                    }
                }
                WinLossDots {
                    matches: player.recent || []
                    dotSize: 6
                    maxCount: 10
                }
            }
        }
    }
}
