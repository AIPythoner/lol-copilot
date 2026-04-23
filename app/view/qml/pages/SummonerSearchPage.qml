import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    launchMode: FluPageType.SingleInstance
    title: qsTr("召唤师搜索")

    property string query: ""

    function submit() {
        if (query.length === 0) return
        Lcu.openSummonerProfile(query)
    }

    ColumnLayout {
        width: parent.width
        spacing: 14

        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            paddings: 14
            RowLayout {
                anchors.fill: parent
                spacing: 10
                FluTextBox {
                    Layout.fillWidth: true
                    placeholderText: qsTr("召唤师名 或 游戏名#TAG (如 Faker#KR1)")
                    text: query
                    onTextChanged: query = text
                    Keys.onReturnPressed: submit()
                }
                FluFilledButton {
                    text: qsTr("搜索")
                    enabled: Lcu.connected && query.length > 0
                    onClicked: submit()
                }
            }
        }

        FluText {
            text: qsTr("输入后按回车或点击搜索。点击搜索结果会打开对方主页（可在主页继续查看历史对局详情）。")
            color: FluColors.Grey120
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            visible: Lcu.connected
        }

        FluText {
            visible: !Lcu.connected
            text: qsTr("请先连接客户端")
            color: FluColors.Grey120
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
