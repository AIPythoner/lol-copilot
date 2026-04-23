import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI

FluScrollablePage {
    launchMode: FluPageType.SingleInstance
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
            delegate: FluArea {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                paddings: 12
                RowLayout {
                    anchors.fill: parent
                    Rectangle {
                        Layout.preferredWidth: 4
                        Layout.fillHeight: true
                        color: "#4684d4"
                    }
                    FluText { Layout.preferredWidth: 200; text: modelData.display_name || "?" }
                    FluText {
                        Layout.preferredWidth: 160
                        text: modelData.ranks && modelData.ranks.length > 0
                            ? modelData.ranks[0].tier + " " + modelData.ranks[0].division
                            : "Unranked"
                    }
                    FluText {
                        Layout.preferredWidth: 120
                        text: qsTr("胜率 ") + Math.round((modelData.recent_win_rate||0)*100) + "%"
                        color: FluColors.Grey120
                    }
                    FluText {
                        text: qsTr("英雄 #") + (modelData.champion_id || "-")
                        color: FluColors.Grey120
                    }
                }
            }
        }

        FluDivider {
            Layout.fillWidth: true
            visible: Lcu.inGame && (Lcu.inGame.theirTeam || []).length > 0
        }

        Repeater {
            model: (Lcu.inGame && Lcu.inGame.theirTeam) || []
            delegate: FluArea {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                paddings: 12
                RowLayout {
                    anchors.fill: parent
                    Rectangle {
                        Layout.preferredWidth: 4
                        Layout.fillHeight: true
                        color: "#c64343"
                    }
                    FluText { Layout.preferredWidth: 200; text: modelData.display_name || "?" }
                    FluText {
                        Layout.preferredWidth: 160
                        text: modelData.ranks && modelData.ranks.length > 0
                            ? modelData.ranks[0].tier + " " + modelData.ranks[0].division
                            : "Unranked"
                    }
                    FluText {
                        Layout.preferredWidth: 120
                        text: qsTr("胜率 ") + Math.round((modelData.recent_win_rate||0)*100) + "%"
                        color: FluColors.Grey120
                    }
                    FluText {
                        text: qsTr("英雄 #") + (modelData.champion_id || "-")
                        color: FluColors.Grey120
                    }
                }
            }
        }

        FluText {
            visible: !Lcu.inGame || !Lcu.inGame.myTeam || Lcu.inGame.myTeam.length === 0
            text: qsTr("未在对局中。进入对局后此处会保留选人时的阵容信息。")
            color: FluColors.Grey120
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
