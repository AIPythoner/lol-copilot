import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

// Friends list with premade-group color coding.
//
// For every friend currently in a game, bridge groups them by lol.gameId; any
// game with 2+ friends gets a unique color so you can spot premades at a
// glance. Clicking a friend opens their summoner profile.
FluScrollablePage {
    id: page
    launchMode: FluPageType.SingleTask
    title: qsTr("好友")

    readonly property var friendsAll: Lcu.friends || []
    readonly property var inGame: friendsAll.filter(function(f) { return f.inGame })
    readonly property var others: friendsAll.filter(function(f) { return !f.inGame })

    Component.onCompleted: if (Lcu.connected) Lcu.refreshFriends()
    Connections {
        target: Lcu
        function onConnectedChanged() { if (Lcu.connected) Lcu.refreshFriends() }
    }

    function _availabilityLabel(av) {
        if (av === "chat") return qsTr("在线")
        if (av === "away") return qsTr("离开")
        if (av === "dnd") return qsTr("请勿打扰")
        if (av === "mobile") return qsTr("手机在线")
        if (av === "offline") return qsTr("离线")
        return av || qsTr("未知")
    }

    function _availabilityColor(av) {
        if (av === "chat") return "#3ea04a"
        if (av === "dnd") return "#c64343"
        if (av === "mobile") return "#4684d4"
        if (av === "away") return "#d4a04a"
        return FluColors.Grey120
    }

    function _gameStatusLabel(status, mode) {
        if (status === "championSelect") return qsTr("选人中")
        if (status === "inGame") return qsTr("游戏中") + (mode ? " · " + mode : "")
        if (status === "hosting" || status === "inQueue") return qsTr("匹配中")
        if (status === "spectating") return qsTr("观战中")
        return mode || qsTr("游戏中")
    }

    ColumnLayout {
        width: parent.width
        spacing: 14

        // ===== header =====
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            paddings: 14
            ColumnLayout {
                anchors.fill: parent
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    FluText {
                        text: qsTr("好友列表")
                        font: FluTextStyle.Subtitle
                    }
                    FluText {
                        text: qsTr("共 ") + page.friendsAll.length
                            + qsTr(" · 游戏中 ") + page.inGame.length
                        color: FluColors.Grey120
                        font.pixelSize: 12
                    }
                    Item { Layout.fillWidth: true }
                    FluIconButton {
                        iconSource: FluentIcons.Refresh
                        iconSize: 14
                        enabled: Lcu.connected
                        onClicked: Lcu.refreshFriends()
                    }
                }
                FluText {
                    text: qsTr("同一对局里的多位好友会用相同颜色标记开黑组。点击头像打开战绩。")
                    color: FluColors.Grey120
                    font.pixelSize: 11
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }

        // ===== in-game friends =====
        FluText {
            text: qsTr("游戏中") + " (" + page.inGame.length + ")"
            font: FluTextStyle.Subtitle
            visible: page.inGame.length > 0
        }

        Repeater {
            model: page.inGame
            delegate: FriendCard { entry: modelData; Layout.fillWidth: true }
        }

        // ===== other friends =====
        FluDivider {
            Layout.fillWidth: true
            visible: page.others.length > 0
        }
        FluText {
            text: qsTr("其他") + " (" + page.others.length + ")"
            font: FluTextStyle.Subtitle
            visible: page.others.length > 0
        }

        Repeater {
            model: page.others
            delegate: FriendCard { entry: modelData; Layout.fillWidth: true }
        }

        FluText {
            visible: page.friendsAll.length === 0
            text: Lcu.connected ? qsTr("暂无好友数据，请刷新") : qsTr("请先连接客户端")
            Layout.alignment: Qt.AlignHCenter
            color: FluColors.Grey120
        }
    }

    component FriendCard: FluArea {
        property var entry: ({})
        Layout.preferredHeight: 64
        paddings: 0

        // Same-game color stripe (only set for premade groups of 2+).
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 5
            color: entry.groupColor || "transparent"
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: entry.puuid ? Qt.PointingHandCursor : Qt.ArrowCursor
            hoverEnabled: true
            enabled: !!entry.puuid
            onClicked: Lcu.openSummonerProfileByPuuid(entry.puuid)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 12

            ProfileIcon {
                iconId: entry.iconId || 29
                size: 44
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                FluText {
                    text: (entry.name || "?") + (entry.tag ? " #" + entry.tag : "")
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                FluText {
                    text: entry.inGame
                        ? page._gameStatusLabel(entry.gameStatus, entry.gameMode)
                        : page._availabilityLabel(entry.availability)
                    color: entry.inGame
                        ? (entry.groupColor || "#d4a04a")
                        : page._availabilityColor(entry.availability)
                    font.pixelSize: 11
                }
            }

            FluText {
                visible: entry.groupColor && entry.groupColor.length > 0
                text: qsTr("开黑组")
                color: entry.groupColor
                font.pixelSize: 10
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
