import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleTask
    title: qsTr("工具")

    property string lobbyName: ""
    property string lobbyPassword: ""
    property int profileIconInput: 0
    property string statusMessageDraft: ""

    // [PERF] Read Lcu.summoner once per signal — the profile preview row
    // below touched it 6 times (icon id, level, name, displayed icon id).
    readonly property var summoner: Lcu.summoner || ({})
    readonly property var presence: Lcu.presence || ({})
    readonly property string currentStatusMessage: presence.statusMessage || ""

    Component.onCompleted: {
        if (Lcu.connected) {
            Lcu.refreshHextech()
            Lcu.refreshPresence()
        }
        statusMessageDraft = currentStatusMessage
    }
    Connections {
        target: Lcu
        function onConnectedChanged() {
            if (Lcu.connected) {
                Lcu.refreshHextech()
                Lcu.refreshPresence()
            }
        }
        function onPresenceChanged() {
            // Live-sync the editor with the actual client state when the user
            // hasn't started editing; otherwise we'd clobber their in-progress
            // typing on every presence echo.
            if (!page.statusMessageBox || !page.statusMessageBox.activeFocus) {
                page.statusMessageDraft = page.currentStatusMessage
            }
        }
    }

    property var statusMessageBox: null

    ColumnLayout {
        width: parent.width
        spacing: 14

        // ===== auto actions (most-used → keep at top) =====
        AutoActionsPanel {
            Layout.fillWidth: true
        }

        // ===== custom lobbies =====
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: lobbyCol.implicitHeight + 32
            paddings: 14
            radius: AppTheme.radiusLg
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
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: profileCol.implicitHeight + 32
            paddings: 14
            radius: AppTheme.radiusLg
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
                        iconId: page.summoner.profileIconId || 0
                        level: page.summoner.summonerLevel || 0
                        size: 56
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        FluText {
                            text: (page.summoner.gameName || page.summoner.displayName) || "-"
                            font.bold: true
                        }
                        FluText {
                            text: qsTr("当前头像 ID: ") + (page.summoner.profileIconId || "-")
                            color: AppTheme.textSecondary
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
                    spacing: 8
                    FluButton {
                        text: qsTr("移除荣耀水晶框")
                        enabled: Lcu.connected
                        onClicked: Lcu.removePrestigeCrest()
                    }
                    FluButton {
                        text: qsTr("自定义生涯背景")
                        enabled: Lcu.connected
                        onClicked: bgPicker.open()
                    }
                }

                FluDivider { Layout.fillWidth: true }

                // ===== custom signature (国服雪藏的"自定义签名"功能) =====
                RowLayout {
                    Layout.fillWidth: true
                    FluText { text: qsTr("个性签名"); font: FluTextStyle.Body }
                    Item { Layout.fillWidth: true }
                    FluText {
                        text: qsTr("好友可见")
                        color: AppTheme.textSecondary
                        font.pixelSize: 11
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    FluTextBox {
                        id: statusBox
                        Layout.fillWidth: true
                        placeholderText: qsTr("点击编辑签名,好友列表上会显示")
                        text: page.statusMessageDraft
                        onTextChanged: page.statusMessageDraft = text
                        Component.onCompleted: page.statusMessageBox = statusBox
                    }
                    FluFilledButton {
                        text: qsTr("保存")
                        enabled: Lcu.connected && page.statusMessageDraft !== page.currentStatusMessage
                        onClicked: Lcu.setStatusMessage(page.statusMessageDraft)
                    }
                    FluButton {
                        text: qsTr("清空")
                        enabled: Lcu.connected && page.currentStatusMessage.length > 0
                        onClicked: {
                            page.statusMessageDraft = ""
                            Lcu.setStatusMessage("")
                        }
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
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: hexCol.implicitHeight + 32
            paddings: 14
            radius: AppTheme.radiusLg
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
                // [PERF] All four derived properties now read `hex`, not
                // `Lcu.hextech`, so hextechChanged triggers a single marshal
                // instead of four.
                readonly property var hex: Lcu.hextech || ({})
                readonly property var wallet: hex.wallet || ({})
                readonly property int redundantBe: hex.redundantBe || 0
                readonly property int redundantCount: (hex.redundantShards && hex.redundantShards.length) || 0

                // Wallet row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    FluText {
                        text: qsTr("蓝色精粹 ") + (hexCol.wallet.blue || 0).toLocaleString(Qt.locale(), "f", 0)
                        font.pixelSize: 12
                    }
                    Rectangle { width: 1; height: 16; color: AppTheme.textSecondary; opacity: 0.3 }
                    FluText {
                        text: qsTr("橙色精粹 ") + (hexCol.wallet.orange || 0).toLocaleString(Qt.locale(), "f", 0)
                        font.pixelSize: 12
                    }
                    Rectangle { width: 1; height: 16; color: AppTheme.textSecondary; opacity: 0.3 }
                    FluText {
                        text: qsTr("钥匙 ") + (hexCol.wallet.keys || 0) + "  ·  " + qsTr("碎片 ") + (hexCol.wallet.keyFragments || 0)
                        font.pixelSize: 12
                        color: AppTheme.textSecondary
                    }
                }

                FluDivider { Layout.fillWidth: true }

                // Inventory summary row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20

                    ColumnLayout {
                        spacing: 1
                        FluText { text: qsTr("宝箱"); color: AppTheme.textSecondary; font.pixelSize: 11 }
                        FluText {
                            text: (hexCol.hex.totalChests || 0) + ""
                            font: FluTextStyle.Subtitle
                        }
                    }
                    ColumnLayout {
                        spacing: 1
                        FluText { text: qsTr("碎片总数"); color: AppTheme.textSecondary; font.pixelSize: 11 }
                        FluText {
                            text: (hexCol.hex.totalShards || 0) + ""
                            font: FluTextStyle.Subtitle
                        }
                    }
                    ColumnLayout {
                        spacing: 1
                        FluText { text: qsTr("重复碎片"); color: AppTheme.textSecondary; font.pixelSize: 11 }
                        FluText {
                            text: hexCol.redundantCount + ""
                            font: FluTextStyle.Subtitle
                            color: hexCol.redundantBe > 0 ? AppTheme.accent : undefined
                        }
                    }
                    ColumnLayout {
                        spacing: 1
                        FluText { text: qsTr("预计可得 BE"); color: AppTheme.textSecondary; font.pixelSize: 11 }
                        FluText {
                            text: hexCol.redundantBe > 0
                                ? "+" + hexCol.redundantBe.toLocaleString(Qt.locale(), "f", 0)
                                : "0"
                            font: FluTextStyle.Subtitle
                            color: hexCol.redundantBe > 0 ? AppTheme.win : AppTheme.textSecondary
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
                        color: AppTheme.textSecondary
                        font.pixelSize: 10
                    }
                }
            }
        }

        // ===== chat broadcasts =====
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: chatCol.implicitHeight + 32
            paddings: 14
            radius: AppTheme.radiusLg
            ColumnLayout {
                id: chatCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 10

                FluText { text: qsTr("聊天广播"); font: FluTextStyle.Subtitle }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    FluText {
                        anchors.left: parent.left
                        anchors.right: sendWinratesButton.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("把双方近期战绩胜率发到选人聊天")
                        color: AppTheme.textSecondary
                        font.pixelSize: 11
                    }
                    FluFilledButton {
                        id: sendWinratesButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("一键发送所有人胜率")
                        enabled: Lcu.connected
                        onClicked: Lcu.sendAllWinrates()
                    }
                }
            }
        }

    }

    BackgroundSkinPicker {
        id: bgPicker
    }
}
