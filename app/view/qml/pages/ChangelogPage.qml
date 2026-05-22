import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleTask
    title: qsTr("更新日志")

    readonly property var entries: [
        {
            version: "v0.2.5",
            date: "2026-05-23",
            title: qsTr("个性化资料、好友开黑标记与可点击卡片"),
            items: [
                qsTr("工具页支持自定义个性签名（恢复国服雪藏的签名编辑）"),
                qsTr("新增「自定义生涯背景」皮肤选择器，可应用任意英雄任意皮肤（含未拥有），支持搜索"),
                qsTr("新增「好友」页：同一对局中的好友用相同颜色条标记开黑组，按在线状态分区展示"),
                qsTr("选人页 / 对局页的玩家卡片现可点击，跳转召唤师主页查战绩"),
                qsTr("修复战绩详情点英雄头像无响应；自动发送队友胜率不再重复发送")
            ]
        },
        {
            version: "v0.2.4",
            date: "2026-05-22",
            title: qsTr("OP.GG 修复优化与请求节流"),
            items: [
                qsTr("OP.GG 出装相关修复与优化，国内访问更稳定"),
                qsTr("LCU GET 请求加入节流，选人阶段玩家卡片可跨次刷新复用，降低客户端压力")
            ]
        },
        {
            version: "v0.2.3",
            date: "2026-05-19",
            title: qsTr("OP.GG 自动出装与新版适配"),
            items: [
                qsTr("选人阶段可自动抓取 OP.GG 出装并写入客户端装备栏"),
                qsTr("适配 OP.GG 2026-05 React 新版组件结构，恢复出装解析"),
                qsTr("QML 页面缓存 Lcu QVariant 读取，界面切换更流畅")
            ]
        },
        {
            version: "v0.2.2",
            date: "2026-05-16",
            title: qsTr("自动动作与工具完善"),
            items: [
                qsTr("抛光自动接受 / 自动 BP / 段位展示 / OP.GG 板块的细节"),
                qsTr("修复工具页若干按钮无响应的问题"),
                qsTr("补充 QQ 群入口")
            ]
        },
        {
            version: "v0.2.1",
            date: "2026-04-23",
            title: qsTr("战绩详情体验大改"),
            items: [
                qsTr("战绩详情图标加载与整体渲染加速明显"),
                qsTr("战绩页展示 Riot ID 标签，新增一键复制召唤师名字"),
                qsTr("改写侧栏导航实现，修复历史页面被切换后内存泄漏")
            ]
        },
        {
            version: "v0.1.3",
            date: "2026-04-23",
            title: qsTr("AI 对局分析与战利品工具"),
            items: [
                qsTr("接入 AI 对局分析，支持 OpenAI 兼容的流式输出"),
                qsTr("新增海克斯战利品自动整理"),
                qsTr("新增对局回放一键启动")
            ]
        }
    ]

    ColumnLayout {
        width: parent.width
        spacing: 14

        FluText {
            text: qsTr("最近 5 次主要更新")
            font: FluTextStyle.Subtitle
            color: FluColors.Grey120
        }

        Repeater {
            model: page.entries
            delegate: FluArea {
                Layout.fillWidth: true
                Layout.preferredHeight: entryCol.implicitHeight + 28
                paddings: 14

                ColumnLayout {
                    id: entryCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        FluText {
                            text: modelData.version
                            font: FluTextStyle.Subtitle
                        }
                        FluText {
                            text: modelData.date
                            color: FluColors.Grey120
                            font.pixelSize: 12
                        }
                        Item { Layout.fillWidth: true }
                    }

                    FluText {
                        text: modelData.title
                        font.pixelSize: 15
                        font.bold: true
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: modelData.items
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                FluText {
                                    text: "•"
                                    color: FluColors.Grey120
                                    Layout.alignment: Qt.AlignTop
                                }
                                FluText {
                                    Layout.fillWidth: true
                                    text: modelData
                                    color: FluColors.Grey120
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
