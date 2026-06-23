import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI

GlassCard {
    id: root
    Layout.fillWidth: true
    Layout.preferredHeight: autoCol.implicitHeight + 32
    paddings: 14
    radius: AppTheme.radiusLg

    property string editingField: ""
    property var editingIds: []
    property string pickerFilter: ""

    // [PERF] Cache the settings.auto_actions sub-dict and the champion list
    // once per signal. The toggles + chip rows below read Lcu.settings 6
    // times — each one marshals the entire settings dict from Python.
    readonly property var autoActions: (Lcu.settings && Lcu.settings.auto_actions) || ({})
    readonly property var champions: Lcu.champions || []

    function openPicker(field) {
        editingField = field
        editingIds = ((autoActions[field]) || []).slice()
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

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: autoAcceptToggle.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                FluText { text: qsTr("自动接受对局") }
            }
            Toggle {
                id: autoAcceptToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.autoActions.auto_accept
                onToggled: function(value) { Lcu.updateAutoActions({"auto_accept": value}) }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: teamWinrateToggle.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                FluText { text: qsTr("选人时发送队友胜率") }
                FluText {
                    text: qsTr("进入选人后，把队友最近 20 场胜率发送到冠军选择聊天框")
                    color: AppTheme.textSecondary
                    font.pixelSize: 11
                }
            }
            Toggle {
                id: teamWinrateToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.autoActions.send_team_winrate
                onToggled: function(value) { Lcu.updateAutoActions({"send_team_winrate": value}) }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: autoBanToggle.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    FluText { text: qsTr("自动禁用") }
                }
                Toggle {
                    id: autoBanToggle
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.autoActions.auto_ban
                    onToggled: function(value) { Lcu.updateAutoActions({"auto_ban": value}) }
                }
            }
            ChampionChipRow {
                Layout.fillWidth: true
                label: qsTr("禁用优先级")
                ids: root.autoActions.ban_priority || []
                onEdit: root.openPicker("ban_priority")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: autoPickToggle.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    FluText { text: qsTr("自动选择") }
                }
                Toggle {
                    id: autoPickToggle
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.autoActions.auto_pick
                    onToggled: function(value) { Lcu.updateAutoActions({"auto_pick": value}) }
                }
            }
            ChampionChipRow {
                Layout.fillWidth: true
                label: qsTr("选择优先级")
                ids: root.autoActions.pick_priority || []
                onEdit: root.openPicker("pick_priority")
            }
        }
    }

    component ChampionChipRow: Item {
        property string label: ""
        property var ids: []
        signal edit()
        Layout.preferredHeight: Math.max(32, editButton.implicitHeight)

        FluText {
            id: chipLabel
            width: 90
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: label
            color: AppTheme.textSecondary
            font.pixelSize: 12
        }

        Flow {
            anchors.left: chipLabel.right
            anchors.leftMargin: 8
            anchors.right: editButton.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
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
                color: AppTheme.textSecondary
                font.pixelSize: 12
            }
        }

        FluButton {
            id: editButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("编辑")
            onClicked: edit()
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
                        color: AppTheme.textSecondary
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
                                var list = root.champions.filter(function(c) {
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
                    visible: root.champions.length === 0
                    text: qsTr("英雄列表未加载，请先连接客户端")
                    color: AppTheme.textSecondary
                }
            }
        }
    }
}
