import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    launchMode: FluPageType.SingleTask
    title: qsTr("工具")

    property string lobbyName: ""
    property string lobbyPassword: ""
    property int profileIconInput: 0

    ColumnLayout {
        width: parent.width
        spacing: 14

        // ===== custom lobbies =====
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: lobbyCol.implicitHeight + 32
            paddings: 14
            ColumnLayout {
                id: lobbyCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 10

                FluText { text: qsTr("创建房间"); font: FluTextStyle.Subtitle }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    FluTextBox {
                        Layout.fillWidth: true
                        placeholderText: qsTr("房间名称")
                        text: lobbyName
                        onTextChanged: lobbyName = text
                    }
                    FluTextBox {
                        Layout.preferredWidth: 200
                        placeholderText: qsTr("房间密码（可空）")
                        text: lobbyPassword
                        onTextChanged: lobbyPassword = text
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    FluFilledButton {
                        text: qsTr("5v5 训练模式")
                        enabled: Lcu.connected
                        onClicked: Lcu.createPracticeLobby(lobbyName, lobbyPassword)
                    }
                    FluButton {
                        text: qsTr("5v5 自定义")
                        enabled: Lcu.connected
                        onClicked: Lcu.createCustom5v5(lobbyName, lobbyPassword)
                    }
                    FluButton {
                        text: qsTr("大乱斗自定义")
                        enabled: Lcu.connected
                        onClicked: Lcu.createCustomAram(lobbyName, lobbyPassword)
                    }
                }

                FluDivider { Layout.fillWidth: true }

                FluText { text: qsTr("快速进入匹配队列"); font: FluTextStyle.Body }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    FluButton {
                        text: qsTr("单双排 420")
                        enabled: Lcu.connected
                        onClicked: Lcu.createQueueLobby(420)
                    }
                    FluButton {
                        text: qsTr("灵活组排 440")
                        enabled: Lcu.connected
                        onClicked: Lcu.createQueueLobby(440)
                    }
                    FluButton {
                        text: qsTr("匹配 430")
                        enabled: Lcu.connected
                        onClicked: Lcu.createQueueLobby(430)
                    }
                    FluButton {
                        text: qsTr("大乱斗 450")
                        enabled: Lcu.connected
                        onClicked: Lcu.createQueueLobby(450)
                    }
                    FluButton {
                        text: qsTr("斗魂竞技场 1700")
                        enabled: Lcu.connected
                        onClicked: Lcu.createQueueLobby(1700)
                    }
                }
            }
        }

        // ===== profile tools =====
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: profileCol.implicitHeight + 32
            paddings: 14
            ColumnLayout {
                id: profileCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 10

                FluText { text: qsTr("个人资料"); font: FluTextStyle.Subtitle }

                // current profile preview
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    ProfileIcon {
                        iconId: (Lcu.summoner && Lcu.summoner.profileIconId) || 0
                        level: (Lcu.summoner && Lcu.summoner.summonerLevel) || 0
                        size: 56
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        FluText {
                            text: (Lcu.summoner && (Lcu.summoner.gameName || Lcu.summoner.displayName)) || "-"
                            font.bold: true
                        }
                        FluText {
                            text: qsTr("当前头像 ID: ") + ((Lcu.summoner && Lcu.summoner.profileIconId) || "-")
                            color: FluColors.Grey120
                            font.pixelSize: 11
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    FluTextBox {
                        Layout.preferredWidth: 180
                        placeholderText: qsTr("头像 ID (0-5000+)")
                        onTextChanged: profileIconInput = parseInt(text) || 0
                    }
                    FluFilledButton {
                        text: qsTr("应用头像")
                        enabled: Lcu.connected && profileIconInput > 0
                        onClicked: Lcu.applyProfileIcon(profileIconInput)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    FluButton {
                        text: qsTr("移除荣耀水晶框")
                        enabled: Lcu.connected
                        onClicked: Lcu.removePrestigeCrest()
                    }
                }

                FluDivider { Layout.fillWidth: true }

                FluText { text: qsTr("在线状态"); font: FluTextStyle.Body }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    FluButton {
                        text: qsTr("在线")
                        enabled: Lcu.connected
                        onClicked: Lcu.applyAvailability("chat")
                    }
                    FluButton {
                        text: qsTr("离开")
                        enabled: Lcu.connected
                        onClicked: Lcu.applyAvailability("away")
                    }
                    FluButton {
                        text: qsTr("移动端")
                        enabled: Lcu.connected
                        onClicked: Lcu.applyAvailability("mobile")
                    }
                    FluButton {
                        text: qsTr("请勿打扰")
                        enabled: Lcu.connected
                        onClicked: Lcu.applyAvailability("dnd")
                    }
                }
            }
        }
    }
}
