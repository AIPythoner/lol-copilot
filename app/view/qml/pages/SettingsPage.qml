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

    // [PERF] Lcu.settings is a sizeable dict (window + auto_actions + opgg
    // + ai). Cache it once so the four bindings below don't re-marshal it
    // on each settingsChanged.
    readonly property var settings: Lcu.settings || ({})
    readonly property var opggPrefs: settings.opgg || ({})

    function indexOf(arr, v) {
        for (var i = 0; i < arr.length; i++) if (arr[i] === v) return i
        return 0
    }

    ColumnLayout {
        width: parent.width
        spacing: 14

        // ----- theme -----
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            paddings: 14
            radius: AppTheme.radiusLg
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

        // ----- OP.GG prefs -----
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: opggCol.implicitHeight + 32
            paddings: 14
            radius: AppTheme.radiusLg
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
                        currentIndex: indexOf(tierModel, opggPrefs.tier)
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
                        currentIndex: indexOf(regionModel, opggPrefs.region)
                        onActivated: Lcu.updateOpggPrefs({"region": regionModel[currentIndex]})
                    }
                }
            }
        }

        // ----- client customization -----
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: custCol.implicitHeight + 32
            paddings: 14
            radius: AppTheme.radiusLg
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

        // ----- AI analysis config -----
        GlassCard {
            id: aiCard
            Layout.fillWidth: true
            Layout.preferredHeight: aiCol.implicitHeight + 32
            paddings: 14
            radius: AppTheme.radiusLg

            // Read via this id (not a fragile parent.parent chain).
            readonly property var ai: (Lcu.settings && Lcu.settings.ai) || ({})

            ColumnLayout {
                id: aiCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        spacing: 3
                        RowLayout {
                            spacing: AppTheme.sp2
                            FluText { text: qsTr("AI 战绩复盘"); font: FluTextStyle.Subtitle }
                            Rectangle {
                                radius: AppTheme.radiusPill
                                color: AppTheme.accentGlass
                                border.width: 1
                                border.color: AppTheme.accentGlassBorder
                                implicitWidth: freeTag.implicitWidth + 16
                                implicitHeight: freeTag.implicitHeight + 6
                                Layout.alignment: Qt.AlignVCenter
                                FluText {
                                    id: freeTag
                                    anchors.centerIn: parent
                                    text: qsTr("免费")
                                    color: AppTheme.accentBright
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                        }
                        FluText {
                            text: qsTr("由 DeepSeek 提供，开箱即用，无需配置 API Key。")
                            color: AppTheme.textSecondary
                            font.pixelSize: 11
                        }
                    }
                    Item { Layout.fillWidth: true }
                    FluToggleSwitch {
                        checked: aiCard.ai.enabled === true
                        onClicked: Lcu.updateAiConfig({"enabled": checked})
                    }
                }
                FluText {
                    text: qsTr("在「对局详情」页点「AI 复盘」即可使用。免费额度按 IP 限制，请合理使用；分析结果仅供参考。")
                    color: AppTheme.textSecondary
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
    }

}
