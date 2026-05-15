import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    launchMode: FluPageType.SingleTask
    title: qsTr("对局")

    ColumnLayout {
        width: parent.width
        spacing: 14

        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            paddings: 16
            ColumnLayout {
                anchors.fill: parent
                spacing: 4
                FluText { text: qsTr("当前阶段"); font: FluTextStyle.Subtitle }
                FluText {
                    text: Lcu.phase || "-"
                    font: FluTextStyle.Title
                }
            }
        }

        FluText {
            text: qsTr("进行中的对局（以选人结算结果为准）")
            font: FluTextStyle.Subtitle
            visible: Lcu.inGame && (Lcu.inGame.myTeam || []).length > 0
        }

        Repeater {
            model: (Lcu.inGame && Lcu.inGame.myTeam) || []
            delegate: PlayerRow {
                player: modelData
                accent: "#4684d4"
                Layout.fillWidth: true
            }
        }

        FluDivider {
            Layout.fillWidth: true
            visible: Lcu.inGame && (Lcu.inGame.theirTeam || []).length > 0
        }

        Repeater {
            model: (Lcu.inGame && Lcu.inGame.theirTeam) || []
            delegate: PlayerRow {
                player: modelData
                accent: "#c64343"
                Layout.fillWidth: true
            }
        }

        FluText {
            visible: !Lcu.inGame || !Lcu.inGame.myTeam || Lcu.inGame.myTeam.length === 0
            text: qsTr("未在对局中。进入对局后此处会保留选人时的阵容信息。")
            color: FluColors.Grey120
            Layout.alignment: Qt.AlignHCenter
        }
    }

    component PlayerRow: FluArea {
        property var player: ({})
        property string accent: "#4684d4"
        property bool hidden: (player.display_name || "?") === "???"
        Layout.preferredHeight: 72
        paddings: 10
        opacity: hidden ? 0.55 : 1.0

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
                    color: FluColors.Grey120
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
                    color: FluColors.Grey120
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
        if (!r) return FluColors.Grey120
        if (r >= 0.6) return "#3ea04a"
        if (r >= 0.5) return "#d4a04a"
        return "#c64343"
    }
}
