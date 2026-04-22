import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    launchMode: FluPageType.SingleTask
    title: qsTr("ARAM 增益 / 减益")

    Component.onCompleted: Lcu.loadAramBuffs()

    property int filterMode: 0  // 0=全部, 1=被加强(伤害>100%), 2=被削弱(伤害<100%)

    property var filtered: {
        var all = Lcu.aramBuffs || []
        if (filterMode === 1) return all.filter(function(b){ return (b.damageDealt||1) > 1.01 })
        if (filterMode === 2) return all.filter(function(b){ return (b.damageDealt||1) < 0.99 })
        return all
    }

    ColumnLayout {
        width: parent.width
        spacing: 12

        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            paddings: 12
            RowLayout {
                anchors.fill: parent
                spacing: 10
                FluText {
                    text: qsTr("来源：Community Dragon（随游戏版本自动更新）")
                    color: FluColors.Grey120
                    font.pixelSize: 12
                }
                Item { Layout.fillWidth: true }
                FluToggleButton {
                    text: qsTr("全部")
                    checked: filterMode === 0
                    onClicked: filterMode = 0
                }
                FluToggleButton {
                    text: qsTr("加强")
                    checked: filterMode === 1
                    onClicked: filterMode = 1
                }
                FluToggleButton {
                    text: qsTr("削弱")
                    checked: filterMode === 2
                    onClicked: filterMode = 2
                }
                FluIconButton {
                    iconSource: FluentIcons.Refresh
                    onClicked: Lcu.loadAramBuffs()
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(4, Math.floor(width / 170))
            columnSpacing: 10
            rowSpacing: 10

            Repeater {
                model: filtered
                delegate: BuffCard { buff: modelData }
            }
        }

        FluText {
            visible: filtered.length === 0
            text: qsTr("加载中或无数据…")
            Layout.alignment: Qt.AlignHCenter
            color: FluColors.Grey120
        }
    }

    component BuffCard: FluArea {
        id: card
        property var buff: ({})
        Layout.preferredHeight: 106
        Layout.fillWidth: true
        paddings: 10

        RowLayout {
            anchors.fill: parent
            spacing: 10

            ChampionIcon {
                championId: buff.championId || 0
                size: 48
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                FluText {
                    text: Lcu.championName(buff.championId || 0) || ("#" + buff.championId)
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    font.pixelSize: 12
                }

                StatRow { label: qsTr("伤害"); value: buff.damageDealt || 1; positiveGood: true }
                StatRow { label: qsTr("承伤"); value: buff.damageReceived || 1; positiveGood: false }
                StatRow { label: qsTr("治疗"); value: buff.healingReceived || 1; positiveGood: true }
            }
        }
    }

    component StatRow: RowLayout {
        property string label: ""
        property real value: 1
        property bool positiveGood: true
        spacing: 4

        FluText {
            Layout.preferredWidth: 40
            text: label
            color: FluColors.Grey120
            font.pixelSize: 10
        }

        Rectangle {
            Layout.fillWidth: true
            height: 6
            radius: 3
            color: FluTheme.dark ? "#2a2a2a" : "#e4e4ea"

            // center divider at 100%
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                width: 1
                height: 10
                color: FluColors.Grey120
                opacity: 0.4
            }

            // delta bar from center
            Rectangle {
                property real delta: value - 1
                anchors.verticalCenter: parent.verticalCenter
                x: delta >= 0 ? parent.width/2 : parent.width/2 + (parent.width/2 * Math.max(-0.4, delta * 2))
                width: Math.min(parent.width/2, Math.abs(delta) * parent.width)
                height: parent.height
                radius: parent.radius
                color: (delta >= 0) === positiveGood ? "#3ea04a" : "#c64343"
            }
        }

        FluText {
            Layout.preferredWidth: 44
            text: Math.round(value * 100) + "%"
            color: Math.abs(value - 1) < 0.01 ? FluColors.Grey120
                 : ((value > 1) === positiveGood ? "#3ea04a" : "#c64343")
            font.pixelSize: 11
            font.bold: Math.abs(value - 1) > 0.01
            horizontalAlignment: Text.AlignRight
        }
    }
}
