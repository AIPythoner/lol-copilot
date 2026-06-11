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
    // The combos display the localized label (`name`) while the value sent
    // to OP.GG is the English slug (`value`). Keep them index-aligned.
    property var modeOptions: [
        { name: qsTr("排位"), value: "ranked" },
        { name: qsTr("大乱斗"), value: "aram" },
        { name: qsTr("斗魂竞技场"), value: "arena" },
        { name: qsTr("无限火力"), value: "urf" },
    ]
    property var positionOptions: [
        { name: qsTr("自动"), value: "auto" },
        { name: qsTr("上单"), value: "top" },
        { name: qsTr("打野"), value: "jungle" },
        { name: qsTr("中路"), value: "mid" },
        { name: qsTr("下路"), value: "adc" },
        { name: qsTr("辅助"), value: "support" },
    ]
    property var modeModel: modeOptions.map(function(o) { return o.name })
    property var positionModel: positionOptions.map(function(o) { return o.name })

    function _modeIndex(value) {
        for (var i = 0; i < modeOptions.length; i++) {
            if (modeOptions[i].value === value) return i
        }
        return 0
    }
    function _positionIndex(value) {
        for (var i = 0; i < positionOptions.length; i++) {
            if (positionOptions[i].value === value) return i
        }
        return 0
    }

    Connections {
        target: Lcu
        function onOpggAutoFilled(championId, championName, mode, position) {
            selectedChampionId = championId
            selectedChampionName = championName
            champBox.text = championName
            cbMode.currentIndex = _modeIndex(mode)
            cbPos.currentIndex = _positionIndex(position || "auto")
        }
    }

    // [PERF] Cache QVariant properties locally so bindings don't repeatedly
    // marshal big dicts/lists across the Py↔QML boundary. `Lcu.opggBuild`
    // alone was being touched 10+ times per refresh; each access deep-copies
    // the entire build dict. Reading it once into `build` collapses that
    // into a single marshal per opggBuildChanged signal.
    readonly property var build: Lcu.opggBuild || ({})
    readonly property var champions: Lcu.champions || []

    // build autosuggest data from loaded champions. Each entry carries both
    // the Chinese display name and the English alias plus a lowercased copy
    // so the custom matcher below can match on either field, case-insensitive,
    // and substring-anywhere (e.g. "yas" → Yasuo, "亚" → 亚索).
    property var champSuggestions: {
        var list = champions
        var out = []
        for (var i = 0; i < list.length; i++) {
            var c = list[i]
            var name = c.name || ""
            var alias = c.alias || ""
            out.push({
                id: c.id,
                name: name,
                alias: alias,
                searchText: (name + " " + alias).toLowerCase(),
            })
        }
        return out
    }

    function _filterChampions(query) {
        var q = (query || "").trim().toLowerCase()
        if (!q) return []
        var out = []
        for (var i = 0; i < champSuggestions.length; i++) {
            var s = champSuggestions[i]
            if (s.searchText.indexOf(q) !== -1) {
                out.push(s)
                if (out.length >= 20) break
            }
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

                    Item {
                        Layout.preferredWidth: 240
                        Layout.preferredHeight: 32

                        FluTextBox {
                            id: champBox
                            anchors.fill: parent
                            placeholderText: qsTr("选择英雄 (中文 / 英文 / 简写)")
                            onTextChanged: {
                                if (text.length > 0 && activeFocus) {
                                    suggestPopup.visible = true
                                } else if (text.length === 0) {
                                    suggestPopup.visible = false
                                }
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus) {
                                    // delay so item-click handler still fires
                                    closeTimer.start()
                                } else if (text.length > 0) {
                                    suggestPopup.visible = true
                                }
                            }
                            Timer {
                                id: closeTimer
                                interval: 160
                                onTriggered: suggestPopup.visible = false
                            }
                        }

                        Popup {
                            id: suggestPopup
                            x: 0
                            y: champBox.height
                            width: champBox.width
                            padding: 0
                            visible: false
                            closePolicy: Popup.NoAutoClose

                            property var hits: _filterChampions(champBox.text)

                            background: Rectangle {
                                radius: 4
                                color: FluTheme.dark ? "#252525" : "#fafafa"
                                border.width: 1
                                border.color: FluTheme.dark ? "#3a3a3a" : "#d8d8d8"
                            }

                            contentItem: Item {
                                implicitHeight: Math.min(8, Math.max(1, suggestPopup.hits.length)) * 36

                                ListView {
                                    anchors.fill: parent
                                    clip: true
                                    boundsBehavior: ListView.StopAtBounds
                                    model: suggestPopup.hits
                                    ScrollBar.vertical: FluScrollBar {}

                                    delegate: Rectangle {
                                        width: ListView.view.width
                                        height: 36
                                        color: rowHover.hovered
                                            ? (FluTheme.dark ? "#363636" : "#eaeaea")
                                            : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            ChampionIcon {
                                                championId: modelData.id
                                                size: 26
                                                showTooltip: false
                                            }
                                            FluText {
                                                text: modelData.name
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                            FluText {
                                                text: modelData.alias
                                                color: FluColors.Grey120
                                                font.pixelSize: 11
                                            }
                                        }

                                        HoverHandler { id: rowHover }
                                        TapHandler {
                                            onTapped: {
                                                selectedChampionId = modelData.id
                                                selectedChampionName = modelData.name
                                                champBox.text = modelData.name
                                                suggestPopup.visible = false
                                                champBox.focus = false
                                            }
                                        }
                                    }

                                    FluText {
                                        anchors.centerIn: parent
                                        visible: suggestPopup.hits.length === 0 && champBox.text.length > 0
                                        text: qsTr("没有匹配的英雄")
                                        color: FluColors.Grey120
                                        font.pixelSize: 12
                                    }
                                }
                            }
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
                            var posOpt = positionOptions[cbPos.currentIndex] || positionOptions[0]
                            var modeOpt = modeOptions[cbMode.currentIndex] || modeOptions[0]
                            var posValue = posOpt.value
                            var pos = posValue === "auto" ? "" : posValue
                            var modeValue = modeOpt.value
                            Lcu.loadOpggBuild(name, modeValue, pos)
                        }
                    }
                    FluButton {
                        text: qsTr("当前对局")
                        enabled: Lcu.connected
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("从当前选英雄阶段读取你已选/预选的英雄")
                        onClicked: Lcu.pickFromChampSelect()
                    }
                }

                FluText {
                    visible: champions.length === 0
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
            visible: !!build.champion

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
                        text: (build.champion || "") + "  —  " + (build.mode || "")
                        font: FluTextStyle.Subtitle
                    }
                    FluText {
                        text: qsTr("版本 ") + (build.patch || "-")
                            + (build.position ? "  ·  " + build.position : "")
                        color: FluColors.Grey120
                        font.pixelSize: 11
                    }
                }
                FluFilledButton {
                    text: qsTr("应用出装到客户端")
                    enabled: Lcu.connected
                        && (build.variants || []).length > 0
                        && (
                            (build.variants[0].items_start || []).length
                            + (build.variants[0].items_boots || []).length
                            + (build.variants[0].items_core || []).length
                            + (build.variants[0].items_situational || []).length
                        ) > 0
                    onClicked: Lcu.applyCurrentItemSet()
                }
                FluFilledButton {
                    text: qsTr("应用符文页到客户端")
                    enabled: Lcu.connected
                        && (build.variants || []).length > 0
                        && build.variants[0].runePage
                    onClicked: Lcu.applyCurrentRunePage()
                }
            }
        }

        // ===== build variants =====
        Repeater {
            model: build.variants || []
            delegate: VariantCard { variant: modelData; Layout.fillWidth: true }
        }

        FluText {
            visible: !build.champion
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
