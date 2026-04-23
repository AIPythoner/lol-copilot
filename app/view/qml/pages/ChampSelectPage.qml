import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    launchMode: FluPageType.SingleInstance
    title: qsTr("选人分析")

    Component.onCompleted: if (Lcu.connected) Lcu.refreshChampSelect()

    function preGroupColor(puuid) {
        var groups = (Lcu.champSelect && Lcu.champSelect.preGroups) || []
        for (var i = 0; i < groups.length; i++) {
            if ((groups[i].puuids || []).indexOf(puuid) !== -1) return groups[i].color
        }
        return ""
    }

    ColumnLayout {
        width: parent.width
        spacing: 14

        // ===== status header =====
        RowLayout {
            Layout.fillWidth: true
            FluText {
                text: Lcu.phase === "ChampSelect"
                    ? qsTr("选人中")
                      + (Lcu.champSelect.phase ? "  ·  " + Lcu.champSelect.phase : "")
                    : qsTr("当前不在选人阶段：") + (Lcu.phase || "-")
                font: FluTextStyle.Subtitle
            }
            Item { Layout.fillWidth: true }
            FluText {
                visible: Lcu.champSelect.preGroups && Lcu.champSelect.preGroups.length > 0
                text: qsTr("检测到 ") + ((Lcu.champSelect.preGroups||[]).length) + qsTr(" 个开黑组")
                color: "#d4a04a"
                font.pixelSize: 12
            }
            FluButton {
                text: qsTr("刷新")
                onClicked: Lcu.refreshChampSelect()
                enabled: Lcu.connected
            }
        }

        // ===== bans =====
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 68
            paddings: 10
            visible: Lcu.champSelect.bans !== undefined

            RowLayout {
                anchors.fill: parent
                spacing: 16

                FluText { text: qsTr("禁用"); color: FluColors.Grey120 }

                RowLayout {
                    spacing: 6
                    Repeater {
                        model: ((Lcu.champSelect.bans||{}).myTeamBans) || []
                        delegate: BannedChampionIcon { championId: modelData; color: "#4684d4" }
                    }
                }

                Item { Layout.preferredWidth: 16 }

                RowLayout {
                    spacing: 6
                    Repeater {
                        model: ((Lcu.champSelect.bans||{}).theirTeamBans) || []
                        delegate: BannedChampionIcon { championId: modelData; color: "#c64343" }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // ===== teams side by side =====
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 8
                FluText {
                    text: qsTr("我方")
                    font: FluTextStyle.Subtitle
                    color: "#4684d4"
                }
                Repeater {
                    model: (Lcu.champSelect.myTeam || [])
                    delegate: PlayerCard { player: modelData }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 8
                FluText {
                    text: qsTr("敌方")
                    font: FluTextStyle.Subtitle
                    color: "#c64343"
                }
                Repeater {
                    model: (Lcu.champSelect.theirTeam || [])
                    delegate: PlayerCard { player: modelData }
                }
            }
        }

        FluText {
            visible: (!Lcu.champSelect.myTeam || Lcu.champSelect.myTeam.length === 0)
            text: Lcu.connected
                ? qsTr("等待选人会话…")
                : qsTr("请先连接客户端")
            Layout.alignment: Qt.AlignHCenter
            color: FluColors.Grey120
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

    component PlayerCard: FluArea {
        id: card
        property var player: ({})
        Layout.fillWidth: true
        Layout.preferredHeight: 96
        paddings: 0

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
                        color: (player.recent_win_rate||0) >= 0.55 ? "#3ea04a"
                             : (player.recent_win_rate||0) >= 0.45 ? FluColors.Grey120 : "#c64343"
                        font.pixelSize: 11
                    }
                    FluText {
                        text: "  KDA " + (player.avg_kda || 0)
                        color: FluColors.Grey120
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
