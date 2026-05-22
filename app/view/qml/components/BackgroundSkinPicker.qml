import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI

// Skin grid for "自定义生涯背景".
//
// Mirrors sona's ProfileBackgroundPicker behaviour: searchable list of every
// champion's skins (owned + unowned), click a tile to apply. The catalog is
// fetched once via Lcu.refreshAllSkins and projected by bridge; this component
// only handles search + paged rendering + click → Lcu.setBackgroundSkin.
FluPopup {
    id: root

    property string search: ""
    property int visibleCount: 25
    readonly property int pageSize: 25

    readonly property var allSkins: Lcu.allSkins || []
    readonly property bool loading: Lcu.allSkinsLoading || false
    readonly property int appliedId: Lcu.backgroundSkinId || 0

    readonly property var filtered: {
        var q = search.toLowerCase().trim()
        if (!q) return allSkins
        var out = []
        for (var i = 0; i < allSkins.length; i++) {
            var s = allSkins[i]
            if ((s.name || "").toLowerCase().indexOf(q) !== -1
             || (s.champion || "").toLowerCase().indexOf(q) !== -1) {
                out.push(s)
            }
        }
        return out
    }

    width: Math.min(960, Window.window ? Window.window.width - 80 : 880)
    height: 600
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onOpened: {
        search = ""
        visibleCount = pageSize
        if (allSkins.length === 0 && !loading) Lcu.refreshAllSkins()
    }

    onSearchChanged: visibleCount = pageSize

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            FluText { text: qsTr("自定义生涯背景"); font: FluTextStyle.Title }
            Item { Layout.fillWidth: true }
            FluText {
                text: qsTr("共 ") + filtered.length + qsTr(" 款皮肤")
                color: FluColors.Grey120
                font.pixelSize: 12
            }
            FluIconButton {
                iconSource: FluentIcons.Refresh
                iconSize: 14
                onClicked: Lcu.refreshAllSkins()
            }
            FluIconButton {
                iconSource: FluentIcons.ChromeClose
                iconSize: 12
                onClicked: root.close()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            FluTextBox {
                Layout.fillWidth: true
                placeholderText: qsTr("搜索英雄或皮肤…")
                text: root.search
                onTextChanged: root.search = text
            }
            FluText {
                visible: root.loading
                text: qsTr("加载中…")
                color: FluColors.Grey120
                font.pixelSize: 11
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentHeight: grid.implicitHeight + 12
            contentWidth: width
            ScrollBar.vertical: FluScrollBar {}
            onContentYChanged: {
                if (contentY + height >= contentHeight - 200
                    && root.visibleCount < root.filtered.length) {
                    root.visibleCount = Math.min(root.filtered.length, root.visibleCount + root.pageSize)
                }
            }

            GridLayout {
                id: grid
                width: parent.width
                columns: 5
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: root.filtered.slice(0, root.visibleCount)
                    delegate: Item {
                        property var skin: modelData
                        property bool applied: skin && skin.id === root.appliedId
                        Layout.fillWidth: true
                        Layout.preferredHeight: 116

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: FluTheme.dark ? "#1f1f1f" : "#f3f3f3"
                            border.color: applied ? "#d4a04a" : (FluTheme.dark ? "#333" : "#ddd")
                            border.width: applied ? 2 : 1
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: 1
                                source: skin.tilePath || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                smooth: true
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 36
                                color: "#cc000000"
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 1
                                    FluText {
                                        text: skin.name || ""
                                        color: "white"
                                        font.pixelSize: 11
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    FluText {
                                        text: skin.champion || ""
                                        color: "#bbb"
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            Rectangle {
                                visible: applied
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 4
                                radius: 4
                                color: "#d4a04a"
                                width: appliedText.implicitWidth + 10
                                height: appliedText.implicitHeight + 4
                                FluText {
                                    id: appliedText
                                    anchors.centerIn: parent
                                    text: qsTr("使用中")
                                    color: "white"
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: if (skin && skin.id) Lcu.setBackgroundSkin(skin.id)
                            }
                        }
                    }
                }
            }

            FluText {
                anchors.centerIn: parent
                visible: !root.loading && root.filtered.length === 0
                text: qsTr("没有找到相关皮肤")
                color: FluColors.Grey120
            }
        }
    }
}
