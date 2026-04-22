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

    Component.onCompleted: if (Lcu.connected) Lcu.refreshHextech()
    Connections {
        target: Lcu
        function onConnectedChanged() { if (Lcu.connected) Lcu.refreshHextech() }
    }

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

        // ===== Hextech loot =====
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: hexCol.implicitHeight + 32
            paddings: 14
            ColumnLayout {
                id: hexCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    FluText { text: qsTr("赫克斯科技工坊"); font: FluTextStyle.Subtitle }
                    Item { Layout.fillWidth: true }
                    FluIconButton {
                        iconSource: FluentIcons.Refresh
                        iconSize: 14
                        enabled: Lcu.connected
                        onClicked: Lcu.refreshHextech()
                    }
                }

                // Shortcut object — we reference hex.wallet, hex.totalChests
                // etc. instead of chaining through `Lcu.hextech &&` every time.
                property var hex: Lcu.hextech || {}
                property var wallet: (Lcu.hextech && Lcu.hextech.wallet) || {}
                property int redundantBe: (Lcu.hextech && Lcu.hextech.redundantBe) || 0
                property int redundantCount: (Lcu.hextech && Lcu.hextech.redundantShards && Lcu.hextech.redundantShards.length) || 0

                // Wallet row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    FluText {
                        text: qsTr("蓝色精粹 ") + (hexCol.wallet.blue || 0).toLocaleString(Qt.locale(), "f", 0)
                        font.pixelSize: 12
                    }
                    Rectangle { width: 1; height: 16; color: FluColors.Grey120; opacity: 0.3 }
                    FluText {
                        text: qsTr("橙色精粹 ") + (hexCol.wallet.orange || 0).toLocaleString(Qt.locale(), "f", 0)
                        font.pixelSize: 12
                    }
                    Rectangle { width: 1; height: 16; color: FluColors.Grey120; opacity: 0.3 }
                    FluText {
                        text: qsTr("钥匙 ") + (hexCol.wallet.keys || 0) + "  ·  " + qsTr("碎片 ") + (hexCol.wallet.keyFragments || 0)
                        font.pixelSize: 12
                        color: FluColors.Grey120
                    }
                }

                FluDivider { Layout.fillWidth: true }

                // Inventory summary row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20

                    ColumnLayout {
                        spacing: 1
                        FluText { text: qsTr("宝箱"); color: FluColors.Grey120; font.pixelSize: 11 }
                        FluText {
                            text: (hexCol.hex.totalChests || 0) + ""
                            font: FluTextStyle.Subtitle
                        }
                    }
                    ColumnLayout {
                        spacing: 1
                        FluText { text: qsTr("碎片总数"); color: FluColors.Grey120; font.pixelSize: 11 }
                        FluText {
                            text: (hexCol.hex.totalShards || 0) + ""
                            font: FluTextStyle.Subtitle
                        }
                    }
                    ColumnLayout {
                        spacing: 1
                        FluText { text: qsTr("重复碎片"); color: FluColors.Grey120; font.pixelSize: 11 }
                        FluText {
                            text: hexCol.redundantCount + ""
                            font: FluTextStyle.Subtitle
                            color: hexCol.redundantBe > 0 ? "#d4a04a" : undefined
                        }
                    }
                    ColumnLayout {
                        spacing: 1
                        FluText { text: qsTr("预计可得 BE"); color: FluColors.Grey120; font.pixelSize: 11 }
                        FluText {
                            text: hexCol.redundantBe > 0
                                ? "+" + hexCol.redundantBe.toLocaleString(Qt.locale(), "f", 0)
                                : "0"
                            font: FluTextStyle.Subtitle
                            color: hexCol.redundantBe > 0 ? "#3ea04a" : FluColors.Grey120
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    FluFilledButton {
                        text: qsTr("一键整理")
                        enabled: Lcu.connected
                        onClicked: Lcu.tidyHextech()
                    }
                    FluButton {
                        text: qsTr("只开宝箱")
                        enabled: Lcu.connected && (hexCol.hex.totalChests || 0) > 0
                        onClicked: Lcu.openAllChests()
                    }
                    FluButton {
                        text: qsTr("只分解重复")
                        enabled: Lcu.connected && hexCol.redundantCount > 0
                        onClicked: Lcu.disenchantRedundantShards()
                    }
                    Item { Layout.fillWidth: true }
                    FluText {
                        text: qsTr("仅开自动型宝箱与重复碎片，不会动你的代币与非重复皮肤")
                        color: FluColors.Grey120
                        font.pixelSize: 10
                    }
                }
            }
        }

        AutoActionsPanel {
            Layout.fillWidth: true
        }
    }
}
