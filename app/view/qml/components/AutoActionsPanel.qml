import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI

FluArea {
    id: root
    Layout.fillWidth: true
    Layout.preferredHeight: autoCol.implicitHeight + 32
    paddings: 14

    property string editingField: ""
    property var editingIds: []
    property string pickerFilter: ""

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

        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                FluText { text: qsTr("选人时发送队友胜率") }
                FluText {
                    text: qsTr("进入选人后，把队友最近 20 场胜率发送到冠军选择聊天框")
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
            }
            FluToggleSwitch {
                checked: Lcu.settings.auto_actions.send_team_winrate
                onClicked: Lcu.updateAutoActions({"send_team_winrate": checked})
            }
        }

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
                onEdit: root.openPicker("ban_priority")
            }
        }

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
                onEdit: root.openPicker("pick_priority")
            }
        }
    }

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

    FluContentDialog {
        id: pickerDialog
        title: qsTr("选择英雄") + (editingField === "ban_priority" ? qsTr("（禁用）") : qsTr("（选择）"))
        buttonFlags: FluContentDialogType.PositiveButton | FluContentDialogType.NeutralButton
        positiveText: qsTr("保存")
        neutralText: qsTr("取消")
        onPositiveClicked: root.commitPicker()

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
                        text: root.pickerFilter
                        onTextChanged: root.pickerFilter = text
                    }
                    FluText {
                        text: qsTr("已选 ") + (root.editingIds || []).length + qsTr(" 个")
                        color: FluColors.Grey120
                        font.pixelSize: 11
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    visible: (root.editingIds || []).length > 0
                    spacing: 4
                    Repeater {
                        model: root.editingIds || []
                        delegate: ChampionIcon {
                            championId: modelData
                            size: 28
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.togglePick(modelData)
                            }
                        }
                    }
                }

                FluDivider { Layout.fillWidth: true; visible: (root.editingIds || []).length > 0 }

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
                                var filter = (root.pickerFilter || "").toLowerCase()
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
                                border.width: root.editingIds && root.editingIds.indexOf(modelData.id) >= 0 ? 2 : 0
                                border.color: "#3ea04a"

                                ChampionIcon {
                                    anchors.centerIn: parent
                                    championId: modelData.id
                                    size: 46
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.togglePick(modelData.id)
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
