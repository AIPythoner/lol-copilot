import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    launchMode: FluPageType.SingleTask
    title: qsTr("OP.GG 出装")

    property int selectedChampionId: 0
    property string selectedChampionName: ""
    property var modeModel: ["ranked", "aram", "arena", "urf"]
    property var positionModel: ["auto", "top", "jungle", "mid", "adc", "support"]

    // build autosuggest data from loaded champions
    property var champSuggestions: {
        var list = Lcu.champions || []
        var out = []
        for (var i = 0; i < list.length; i++) {
            out.push({ title: list[i].name, id: list[i].id, alias: list[i].alias })
        }
        return out
    }

    ColumnLayout {
        width: parent.width
        spacing: 14

        // ===== query panel =====
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: queryCol.implicitHeight + 28
            paddings: 14

            ColumnLayout {
                id: queryCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 10

                FluText { text: qsTr("英雄 & 查询参数"); font: FluTextStyle.Subtitle }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ChampionIcon {
                        championId: selectedChampionId
                        size: 56
                        visible: selectedChampionId > 0
                    }

                    FluAutoSuggestBox {
                        id: champBox
                        Layout.preferredWidth: 240
                        placeholderText: qsTr("选择英雄 (名字 / 别名)")
                        emptyText: qsTr("没有匹配的英雄")
                        items: champSuggestions
                        onItemClicked: (data) => {
                            selectedChampionId = data.id
                            selectedChampionName = data.title
                            text = data.title
                        }
                    }

                    FluComboBox {
                        id: cbMode
                        Layout.preferredWidth: 120
                        model: modeModel
                        currentIndex: 0
                    }
                    FluComboBox {
                        id: cbPos
                        Layout.preferredWidth: 120
                        visible: cbMode.currentIndex === 0
                        model: positionModel
                        currentIndex: 0
                    }
                    FluFilledButton {
                        text: qsTr("查询")
                        enabled: selectedChampionId > 0 || champBox.text.length > 0
                        onClicked: {
                            var name = selectedChampionName || champBox.text
                            var pos = cbPos.currentIndex === 0 ? "" : positionModel[cbPos.currentIndex]
                            Lcu.loadOpggBuild(name, modeModel[cbMode.currentIndex], pos)
                        }
                    }
                }

                FluText {
                    visible: !Lcu.champions || Lcu.champions.length === 0
                    text: qsTr("提示：需要先连接客户端才能加载英雄列表")
                    color: FluColors.Grey120
                    font.pixelSize: 11
                }
            }
        }

        // ===== header for result =====
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 70
            paddings: 12
            visible: Lcu.opggBuild && Lcu.opggBuild.champion

            RowLayout {
                anchors.fill: parent
                spacing: 14
                ChampionIcon {
                    championId: selectedChampionId
                    size: 48
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    FluText {
                        text: (Lcu.opggBuild.champion || "") + "  —  " + (Lcu.opggBuild.mode || "")
                        font: FluTextStyle.Subtitle
                    }
                    FluText {
                        text: qsTr("版本 ") + (Lcu.opggBuild.patch || "-")
                            + (Lcu.opggBuild.position ? "  ·  " + Lcu.opggBuild.position : "")
                        color: FluColors.Grey120
                        font.pixelSize: 11
                    }
                }
                FluFilledButton {
                    text: qsTr("应用符文页到客户端")
                    enabled: Lcu.connected
                        && Lcu.opggBuild
                        && Lcu.opggBuild.variants
                        && Lcu.opggBuild.variants.length > 0
                        && Lcu.opggBuild.variants[0].runePage
                    onClicked: Lcu.applyCurrentRunePage()
                }
            }
        }

        // ===== build variants =====
        Repeater {
            model: (Lcu.opggBuild && Lcu.opggBuild.variants) || []
            delegate: VariantCard { variant: modelData; Layout.fillWidth: true }
        }

        FluText {
            visible: !Lcu.opggBuild || !Lcu.opggBuild.champion
            text: qsTr("选择英雄后点击查询。首次网络请求可能需要 10–15 秒。")
            color: FluColors.Grey120
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // ===== components =====
    component VariantCard: FluArea {
        id: card
        property var variant: ({})
        Layout.preferredHeight: variantCol.implicitHeight + 24
        paddings: 12

        ColumnLayout {
            id: variantCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    Layout.preferredWidth: 4
                    Layout.preferredHeight: 20
                    radius: 2
                    color: "#d4a04a"
                }
                FluText {
                    text: variant.name || ""
                    font: FluTextStyle.Subtitle
                }
                Item { Layout.fillWidth: true }
            }

            // items
            ItemSlotGroup {
                Layout.fillWidth: true
                label: qsTr("起始")
                ids: variant.items_start || []
            }
            ItemSlotGroup {
                Layout.fillWidth: true
                label: qsTr("鞋子")
                ids: variant.items_boots || []
            }
            ItemSlotGroup {
                Layout.fillWidth: true
                label: qsTr("核心出装")
                ids: variant.items_core || []
            }
            ItemSlotGroup {
                Layout.fillWidth: true
                label: qsTr("情景选择")
                ids: variant.items_situational || []
            }

            // summoner spells
            RowLayout {
                Layout.fillWidth: true
                visible: (variant.summoner_spells || []).length > 0
                spacing: 10
                FluText {
                    Layout.preferredWidth: 70
                    text: qsTr("召唤师")
                    color: FluColors.Grey120
                    font.pixelSize: 12
                }
                RowLayout {
                    spacing: 6
                    Repeater {
                        model: variant.summoner_spells || []
                        delegate: SpellIcon { spellId: modelData; size: 30 }
                    }
                }
            }

            // runes
            RowLayout {
                Layout.fillWidth: true
                visible: variant.runePage
                spacing: 10
                FluText {
                    Layout.preferredWidth: 70
                    text: qsTr("符文")
                    color: FluColors.Grey120
                    font.pixelSize: 12
                }
                RuneRow {
                    runePage: variant.runePage
                }
            }
        }
    }

    component ItemSlotGroup: RowLayout {
        property string label: ""
        property var ids: []
        spacing: 6
        FluText {
            Layout.preferredWidth: 70
            text: label
            color: FluColors.Grey120
            font.pixelSize: 12
        }
        Repeater {
            model: ids || []
            delegate: ItemSlot { itemId: modelData; size: 32 }
        }
        FluText {
            visible: !ids || ids.length === 0
            text: qsTr("—")
            color: FluColors.Grey120
        }
        Item { Layout.fillWidth: true }
    }

    component RuneRow: RowLayout {
        property var runePage: ({})
        spacing: 4

        // primary style icon
        Rectangle {
            width: 28; height: 28; radius: 4
            color: FluTheme.dark ? "#1a1a1a" : "#e9e9ef"
            Image {
                anchors.fill: parent
                anchors.margins: 2
                source: runePage && runePage.primary ? Lcu.perkStyleIcon(runePage.primary) : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                cache: true
                asynchronous: true
            }
        }

        Repeater {
            model: runePage ? (runePage.perks || []).slice(0, 4) : []
            delegate: PerkIconCell { perkId: modelData; keystone: index === 0 }
        }

        Rectangle {
            visible: runePage && runePage.sub
            Layout.preferredWidth: 1
            Layout.preferredHeight: 24
            color: FluColors.Grey120
            opacity: 0.3
        }

        Rectangle {
            visible: runePage && runePage.sub
            width: 24; height: 24; radius: 4
            color: FluTheme.dark ? "#1a1a1a" : "#e9e9ef"
            Image {
                anchors.fill: parent
                anchors.margins: 2
                source: runePage && runePage.sub ? Lcu.perkStyleIcon(runePage.sub) : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                cache: true
                asynchronous: true
            }
        }

        Repeater {
            model: runePage ? (runePage.perks || []).slice(4, 6) : []
            delegate: PerkIconCell { perkId: modelData; keystone: false }
        }

        Rectangle {
            visible: runePage && runePage.perks && runePage.perks.length > 6
            Layout.preferredWidth: 1
            Layout.preferredHeight: 24
            color: FluColors.Grey120
            opacity: 0.3
        }

        Repeater {
            model: runePage ? (runePage.perks || []).slice(6, 9) : []
            delegate: PerkIconCell { perkId: modelData; keystone: false; small: true }
        }

        Item { Layout.fillWidth: true }
    }

    component PerkIconCell: Rectangle {
        property int perkId: 0
        property bool keystone: false
        property bool small: false
        width: keystone ? 34 : (small ? 20 : 26)
        height: width
        radius: width / 2
        color: keystone ? "#1c1c1c" : (FluTheme.dark ? "#2a2a2a" : "#d5d5dd")
        Image {
            anchors.fill: parent
            anchors.margins: keystone ? 2 : 1
            source: perkId > 0 ? Lcu.perkIcon(perkId) : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            cache: true
            asynchronous: true
        }
    }
}
