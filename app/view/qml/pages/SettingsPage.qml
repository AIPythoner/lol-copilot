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

    function indexOf(arr, v) {
        for (var i = 0; i < arr.length; i++) if (arr[i] === v) return i
        return 0
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

        // ----- AI analysis config -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: aiCol.implicitHeight + 32
            paddings: 14

            property var ai: (Lcu.settings && Lcu.settings.ai) || {}

            ColumnLayout {
                id: aiCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    FluText { text: qsTr("AI 战绩复盘"); font: FluTextStyle.Subtitle }
                    Item { Layout.fillWidth: true }
                    FluToggleSwitch {
                        checked: (parent.parent.ai.enabled === true)
                        onClicked: Lcu.updateAiConfig({"enabled": checked})
                    }
                }
                FluText {
                    text: qsTr("兼容 OpenAI chat/completions 协议的任一端点都可以——DeepSeek / OpenRouter / OneAPI / 本地 LM Studio 都行。Key 只存本地。")
                    color: FluColors.Grey120
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    FluText { text: qsTr("Base URL"); Layout.preferredWidth: 80 }
                    FluTextBox {
                        id: tbBaseUrl
                        Layout.fillWidth: true
                        placeholderText: "https://api.deepseek.com/v1"
                        text: aiCol.parent.ai.base_url || ""
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    FluText { text: qsTr("模型"); Layout.preferredWidth: 80 }
                    FluTextBox {
                        id: tbModel
                        Layout.fillWidth: true
                        placeholderText: "deepseek-chat / gpt-4o-mini / qwen-max ..."
                        text: aiCol.parent.ai.model || ""
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    FluText { text: qsTr("API Key"); Layout.preferredWidth: 80 }
                    FluTextBox {
                        id: tbApiKey
                        Layout.fillWidth: true
                        placeholderText: "sk-..."
                        echoMode: TextInput.Password
                        text: aiCol.parent.ai.api_key || ""
                    }
                    FluFilledButton {
                        text: qsTr("保存")
                        onClicked: Lcu.updateAiConfig({
                            "base_url": tbBaseUrl.text,
                            "model": tbModel.text,
                            "api_key": tbApiKey.text
                        })
                    }
                }
            }
        }
    }

}
