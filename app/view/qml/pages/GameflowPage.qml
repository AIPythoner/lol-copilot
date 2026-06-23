import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    launchMode: FluPageType.SingleTask
    title: qsTr("对局")

    // [PERF] Cache Lcu.inGame once per change. It was previously read 6
    // times per inGameChanged signal, each time deep-copying the whole
    // dict (10 players × nested ranks/recent arrays).
    readonly property var game: Lcu.inGame || ({})
    readonly property var myTeam: game.myTeam || []
    readonly property var theirTeam: game.theirTeam || []

    ColumnLayout {
        width: parent.width
        spacing: AppTheme.sp4

        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            paddings: AppTheme.sp4
            radius: AppTheme.radiusLg
            ColumnLayout {
                anchors.fill: parent
                spacing: AppTheme.sp1
                FluText { text: qsTr("当前阶段"); font: FluTextStyle.Subtitle }
                FluText {
                    text: Lcu.phaseLabel
                    font: FluTextStyle.Title
                }
            }
        }

        FluText {
            text: qsTr("进行中的对局（以选人结算结果为准）")
            font: FluTextStyle.Subtitle
            visible: myTeam.length > 0
        }

        Repeater {
            model: myTeam
            delegate: PlayerRow {
                player: modelData
                accent: "#4684d4"
                Layout.fillWidth: true
            }
        }

        FluDivider {
            Layout.fillWidth: true
            visible: theirTeam.length > 0
        }

        Repeater {
            model: theirTeam
            delegate: PlayerRow {
                player: modelData
                accent: "#c64343"
                Layout.fillWidth: true
            }
        }

        FluText {
            visible: myTeam.length === 0
            text: qsTr("未在对局中。进入对局后此处会保留选人时的阵容信息。")
            color: AppTheme.textSecondary
            Layout.alignment: Qt.AlignHCenter
        }
    }

    component PlayerRow: GlassCard {
        property var player: ({})
        property string accent: "#4684d4"
        property bool hidden: (player.display_name || "?") === "???"
        Layout.preferredHeight: 72
        paddings: AppTheme.sp3
        opacity: hidden ? 0.55 : 1.0
        hoverable: !!player.puuid

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: !!player.puuid ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: !!player.puuid
            onClicked: Lcu.openSummonerProfileByPuuid(player.puuid)
        }

        RowLayout {
            anchors.fill: parent
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 4
                Layout.fillHeight: true
                radius: 2
                color: accent
            }

            ChampionIcon {
                championId: player.champion_id || 0
                size: 48
            }

            ColumnLayout {
                Layout.preferredWidth: 180
                spacing: 2
                FluText {
                    text: player.display_name || "?"
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                FluText {
                    visible: (player.summoner_level || 0) > 0
                    text: qsTr("等级 ") + (player.summoner_level || 0)
                    color: AppTheme.textSecondary
                    font.pixelSize: 11
                }
            }

            TierBadge {
                Layout.preferredWidth: 170
                tier: (player.ranks && player.ranks.length > 0) ? (player.ranks[0].tier || "UNRANKED") : "UNRANKED"
                division: (player.ranks && player.ranks.length > 0) ? (player.ranks[0].division || "") : ""
                leaguePoints: (player.ranks && player.ranks.length > 0) ? (player.ranks[0].leaguePoints || 0) : 0
                emblemSize: 36
            }

            ColumnLayout {
                Layout.preferredWidth: 130
                spacing: 2
                FluText {
                    text: qsTr("近 ") + ((player.recent || []).length) + qsTr(" 场胜率")
                    color: AppTheme.textSecondary
                    font.pixelSize: 11
                }
                FluText {
                    text: Math.round((player.recent_win_rate || 0) * 100) + "%"
                    font.bold: true
                    color: _winrateColor(player.recent_win_rate || 0)
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    function _winrateColor(r) {
        if (!r) return AppTheme.textSecondary
        if (r >= 0.6) return AppTheme.win
        if (r >= 0.5) return AppTheme.accent
        return AppTheme.loss
    }
}
