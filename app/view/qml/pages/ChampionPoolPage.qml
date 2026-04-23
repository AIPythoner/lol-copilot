import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleTask
    title: qsTr("英雄池")

    Component.onCompleted: if (Lcu.connected) Lcu.loadChampionPool(100)

    property int requestedCount: 100
    property int sortMode: 0   // 0 = games, 1 = winRate, 2 = kda

    property var sortedPool: {
        var p = (Lcu.championPool || []).slice()
        if (sortMode === 1) {
            p.sort(function(a,b){ return b.winRate - a.winRate || b.games - a.games })
        } else if (sortMode === 2) {
            p.sort(function(a,b){ return b.kda - a.kda || b.games - a.games })
        } else {
            p.sort(function(a,b){ return b.games - a.games || b.wins - a.wins })
        }
        return p
    }

    ColumnLayout {
        width: parent.width
        spacing: 12

        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 68
            paddings: 12

            RowLayout {
                anchors.fill: parent
                spacing: 10

                FluToggleButton {
                    text: qsTr("分析 100 场")
                    checked: page.requestedCount === 100
                    enabled: Lcu.connected
                    clickListener: function() {
                        page.requestedCount = 100
                        Lcu.loadChampionPool(100)
                    }
                }
                FluToggleButton {
                    text: qsTr("分析 200 场")
                    checked: page.requestedCount === 200
                    enabled: Lcu.connected
                    clickListener: function() {
                        page.requestedCount = 200
                        Lcu.loadChampionPool(200)
                    }
                }

                Rectangle { width: 1; height: 24; color: FluColors.Grey120; opacity: 0.3 }

                FluText { text: qsTr("排序"); color: FluColors.Grey120; font.pixelSize: 12 }
                FluToggleButton {
                    text: qsTr("场次")
                    checked: sortMode === 0
                    clickListener: function() { sortMode = 0 }
                }
                FluToggleButton {
                    text: qsTr("胜率")
                    checked: sortMode === 1
                    clickListener: function() { sortMode = 1 }
                }
                FluToggleButton {
                    text: "KDA"
                    checked: sortMode === 2
                    clickListener: function() { sortMode = 2 }
                }

                Item { Layout.fillWidth: true }
                FluText {
                    text: qsTr("共 ") + sortedPool.length + qsTr(" 个英雄")
                    color: FluColors.Grey120
                    font.pixelSize: 12
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(4, Math.floor(width / 140))
            columnSpacing: 10
            rowSpacing: 10

            Repeater {
                model: sortedPool
                delegate: ChampCard { stat: modelData }
            }
        }

        FluText {
            visible: sortedPool.length === 0
            text: Lcu.connected ? qsTr("请点击按钮开始分析") : qsTr("请先连接客户端")
            Layout.alignment: Qt.AlignHCenter
            color: FluColors.Grey120
        }
    }

    component ChampCard: FluArea {
        id: card
        property var stat: ({})
        Layout.preferredHeight: 150
        Layout.fillWidth: true
        paddings: 10

        ColumnLayout {
            anchors.fill: parent
            spacing: 4

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                ChampionIcon {
                    championId: stat.champion_id || 0
                    size: 64
                }
            }

            FluText {
                Layout.alignment: Qt.AlignHCenter
                text: Lcu.championName(stat.champion_id || 0) || ("#" + stat.champion_id)
                elide: Text.ElideRight
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 12
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                FluText {
                    text: stat.games + qsTr(" 场")
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
                FluText {
                    text: Math.round(stat.winRate * 100) + "%"
                    color: stat.winRate >= 0.55 ? "#3ea04a"
                         : stat.winRate >= 0.45 ? FluColors.Grey120 : "#c64343"
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            FluText {
                Layout.alignment: Qt.AlignHCenter
                text: "KDA " + stat.kda + "   (" + stat.avgKills + "/" + stat.avgDeaths + "/" + stat.avgAssists + ")"
                color: FluColors.Grey120
                font.pixelSize: 10
            }
        }
    }
}
