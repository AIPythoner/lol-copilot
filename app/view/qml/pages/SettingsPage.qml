import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    launchMode: FluPageType.SingleTask
    title: qsTr("设置")

    property var tierModel: ["platinum_plus", "emerald_plus", "diamond_plus", "master_plus"]
    property var regionModel: ["global", "kr", "cn"]

    // champion picker state
    property string editingField: ""
    property var editingIds: []
    property string pickerFilter: ""

    function indexOf(arr, v) {
        for (var i = 0; i < arr.length; i++) if (arr[i] === v) return i
        return 0
    }

    function openPicker(field) {
        editingField = field
        editingIds = ((Lcu.settings.auto_actions[field]) || []).slice()
        pickerFilter = ""
        pickerDialog.open()
    }

    function commitPicker() {
        var patch = {}
        patch[editingField] = editingIds
        Lcu.updateAutoActions(patch)
    }

    function togglePick(id) {
        var i = editingIds.indexOf(id)
        var next = editingIds.slice()
        if (i >= 0) next.splice(i, 1)
        else next.push(id)
        editingIds = next
    }

    ColumnLayout {
        width: parent.width
        spacing: 14

        // ----- theme -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            paddings: 14
            RowLayout {
                anchors.fill: parent
                FluText { text: qsTr("深色模式") }
                Item { Layout.fillWidth: true }
                FluToggleSwitch {
                    checked: FluTheme.dark
                    onClicked: {
                        FluTheme.darkMode = checked ? FluThemeType.Dark : FluThemeType.Light
                        Lcu.setDarkMode(checked ? "dark" : "light")
                    }
                }
            }
        }

        // ----- auto actions -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: autoCol.implicitHeight + 32
            paddings: 14
            ColumnLayout {
                id: autoCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 14

                FluText { text: qsTr("自动动作"); font: FluTextStyle.Subtitle }

                RowLayout {
                    Layout.fillWidth: true
                    FluText { text: qsTr("自动接受对局") }
                    Item { Layout.fillWidth: true }
                    FluToggleSwitch {
                        checked: Lcu.settings.auto_actions.auto_accept
                        onClicked: Lcu.updateAutoActions({"auto_accept": checked})
                    }
                }

                // ban row
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        FluText { text: qsTr("自动禁用") }
                        Item { Layout.fillWidth: true }
                        FluToggleSwitch {
                            checked: Lcu.settings.auto_actions.auto_ban
                            onClicked: Lcu.updateAutoActions({"auto_ban": checked})
                        }
                    }
                    ChampionChipRow {
                        Layout.fillWidth: true
                        label: qsTr("禁用优先级")
                        ids: Lcu.settings.auto_actions.ban_priority || []
                        onEdit: openPicker("ban_priority")
                    }
                }

                // pick row
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        FluText { text: qsTr("自动选择") }
                        Item { Layout.fillWidth: true }
                        FluToggleSwitch {
                            checked: Lcu.settings.auto_actions.auto_pick
                            onClicked: Lcu.updateAutoActions({"auto_pick": checked})
                        }
                    }
                    ChampionChipRow {
                        Layout.fillWidth: true
                        label: qsTr("选择优先级")
                        ids: Lcu.settings.auto_actions.pick_priority || []
                        onEdit: openPicker("pick_priority")
                    }
                }
            }
        }

        // ----- OP.GG prefs -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: opggCol.implicitHeight + 32
            paddings: 14
            ColumnLayout {
                id: opggCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 10

                FluText { text: qsTr("OP.GG 偏好"); font: FluTextStyle.Subtitle }

                RowLayout {
                    Layout.fillWidth: true
                    FluText { text: qsTr("段位过滤") }
                    Item { Layout.fillWidth: true }
                    FluComboBox {
                        Layout.preferredWidth: 180
                        model: tierModel
                        currentIndex: indexOf(tierModel, Lcu.settings.opgg.tier)
                        onActivated: Lcu.updateOpggPrefs({"tier": tierModel[currentIndex]})
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    FluText { text: qsTr("地区") }
                    Item { Layout.fillWidth: true }
                    FluComboBox {
                        Layout.preferredWidth: 140
                        model: regionModel
                        currentIndex: indexOf(regionModel, Lcu.settings.opgg.region)
                        onActivated: Lcu.updateOpggPrefs({"region": regionModel[currentIndex]})
                    }
                }
            }
        }

        // ----- client customization -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: custCol.implicitHeight + 32
            paddings: 14
            ColumnLayout {
                id: custCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 10

                FluText { text: qsTr("客户端自定义"); font: FluTextStyle.Subtitle }

                RowLayout {
                    Layout.fillWidth: true
                    FluTextBox {
                        id: tbStatus
                        Layout.fillWidth: true
                        placeholderText: qsTr("自定义状态消息（显示给好友）")
                    }
                    FluFilledButton {
                        text: qsTr("应用")
                        enabled: Lcu.connected && tbStatus.text.length > 0
                        onClicked: Lcu.setStatusMessage(tbStatus.text)
                    }
                }
            }
        }
    }

    // ===== champion chip row =====
    component ChampionChipRow: RowLayout {
        property string label: ""
        property var ids: []
        signal edit()
        spacing: 8

        FluText {
            Layout.preferredWidth: 90
            text: label
            color: FluColors.Grey120
            font.pixelSize: 12
        }

        Flow {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: ids || []
                delegate: ChampionIcon {
                    championId: modelData
                    size: 32
                }
            }
            FluText {
                visible: !ids || ids.length === 0
                text: qsTr("未选择任何英雄")
                color: FluColors.Grey120
                font.pixelSize: 12
            }
        }

        FluButton {
            text: qsTr("编辑")
            onClicked: parent.edit()
        }
    }

    // ===== picker dialog =====
    FluContentDialog {
        id: pickerDialog
        title: qsTr("选择英雄") + (editingField === "ban_priority" ? qsTr("（禁用）") : qsTr("（选择）"))
        buttonFlags: FluContentDialogType.PositiveButton | FluContentDialogType.NeutralButton
        positiveText: qsTr("保存")
        neutralText: qsTr("取消")
        onPositiveClicked: commitPicker()

        contentDelegate: Component {
            ColumnLayout {
                width: 680
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    FluTextBox {
                        Layout.fillWidth: true
                        placeholderText: qsTr("搜索英雄")
                        text: pickerFilter
                        onTextChanged: pickerFilter = text
                    }
                    FluText {
                        text: qsTr("已选 ") + (editingIds || []).length + qsTr(" 个")
                        color: FluColors.Grey120
                        font.pixelSize: 11
                    }
                }

                // selected preview
                Flow {
                    Layout.fillWidth: true
                    visible: (editingIds || []).length > 0
                    spacing: 4
                    Repeater {
                        model: editingIds || []
                        delegate: ChampionIcon {
                            championId: modelData
                            size: 28
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: togglePick(modelData)
                            }
                        }
                    }
                }

                FluDivider { Layout.fillWidth: true; visible: (editingIds || []).length > 0 }

                // grid of all champions
                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 360
                    clip: true
                    contentHeight: pickerFlow.implicitHeight

                    Flow {
                        id: pickerFlow
                        width: parent.width - 12
                        spacing: 6

                        Repeater {
                            model: {
                                var filter = (pickerFilter || "").toLowerCase()
                                var list = (Lcu.champions || []).filter(function(c) {
                                    if (!filter) return true
                                    var n = (c.name || "").toLowerCase()
                                    var a = (c.alias || "").toLowerCase()
                                    return n.indexOf(filter) >= 0 || a.indexOf(filter) >= 0
                                })
                                return list
                            }
                            delegate: Rectangle {
                                width: 54; height: 54
                                radius: 6
                                color: "transparent"
                                border.width: editingIds && editingIds.indexOf(modelData.id) >= 0 ? 2 : 0
                                border.color: "#3ea04a"

                                ChampionIcon {
                                    anchors.centerIn: parent
                                    championId: modelData.id
                                    size: 46
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: togglePick(modelData.id)
                                }
                            }
                        }
                    }
                }

                FluText {
                    visible: !Lcu.champions || Lcu.champions.length === 0
                    text: qsTr("英雄列表未加载，请先连接客户端")
                    color: FluColors.Grey120
                }
            }
        }
    }
}
