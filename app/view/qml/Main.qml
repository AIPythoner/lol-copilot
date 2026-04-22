import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI

FluWindow {
    id: window
    title: qsTr("LoL 战绩助手")
    width: Lcu.settings.window && Lcu.settings.window.width ? Lcu.settings.window.width : 1100
    height: Lcu.settings.window && Lcu.settings.window.height ? Lcu.settings.window.height : 720
    minimumWidth: 900
    minimumHeight: 600
    launchMode: FluWindowType.SingleTask
    fitsAppBarWindows: true

    Timer {
        id: saveGeomTimer
        interval: 500
        repeat: false
        onTriggered: Lcu.saveWindowGeometry(window.x, window.y, window.width, window.height)
    }
    onWidthChanged: saveGeomTimer.restart()
    onHeightChanged: saveGeomTimer.restart()
    onXChanged: saveGeomTimer.restart()
    onYChanged: saveGeomTimer.restart()

    appBar: FluAppBar {
        width: window.width
        height: 30
        showDark: true
        closeClickListener: () => {
            // Minimise to tray instead of quitting — user can fully close from
            // the tray menu. Acts like Seraphine / 微信 / QQ.
            window.hide()
        }
        z: 7
    }

    Component.onCompleted: {
        // Restore persisted theme choice. First launch defaults to Dark.
        var mode = (Lcu.settings && Lcu.settings.dark_mode) || "dark"
        if (mode === "light") FluTheme.darkMode = FluThemeType.Light
        else if (mode === "system") FluTheme.darkMode = FluThemeType.System
        else FluTheme.darkMode = FluThemeType.Dark
        FluTheme.animationEnabled = true
    }

    FluInfoBar {
        id: infoBar
        root: window
    }

    Connections {
        target: Lcu
        function onNavigationRequested(relPath) {
            nav.push(Qt.resolvedUrl(relPath))
        }
        function onNotify(title, body) {
            infoBar.showInfo(body, 4000, title)
        }
        function onErrorOccurred(msg) {
            infoBar.showWarning(msg, 5000, qsTr("错误"))
        }
    }

    FluNavigationView {
        id: nav
        anchors.fill: parent
        anchors.topMargin: 30
        displayMode: FluNavigationViewType.Open
        pageMode: FluNavigationViewType.Stack
        logo: "qrc:/qt-project.org/imports/FluentUI/Image/favicon.ico"
        title: qsTr("LoL Agent")

        items: FluObject {
            FluPaneItem {
                title: qsTr("我的生涯")
                icon: FluentIcons.Home
                url: Qt.resolvedUrl("pages/OverviewPage.qml")
                onTap: nav.push(url)
            }
            FluPaneItem {
                title: qsTr("战绩")
                icon: FluentIcons.HistoryList
                url: Qt.resolvedUrl("pages/MatchesPage.qml")
                onTap: nav.push(url)
            }
            FluPaneItem {
                title: qsTr("选人")
                icon: FluentIcons.People
                url: Qt.resolvedUrl("pages/ChampSelectPage.qml")
                onTap: nav.push(url)
            }
            FluPaneItem {
                title: qsTr("对局")
                icon: FluentIcons.Play
                url: Qt.resolvedUrl("pages/GameflowPage.qml")
                onTap: nav.push(url)
            }
            FluPaneItem {
                title: qsTr("OP.GG 出装")
                icon: FluentIcons.Lightbulb
                url: Qt.resolvedUrl("pages/OpggPage.qml")
                onTap: nav.push(url)
            }
            FluPaneItemSeparator {}
            FluPaneItem {
                title: qsTr("召唤师搜索")
                icon: FluentIcons.Search
                url: Qt.resolvedUrl("pages/SummonerSearchPage.qml")
                onTap: nav.push(url)
            }
            FluPaneItem {
                title: qsTr("英雄池")
                icon: FluentIcons.FavoriteStar
                url: Qt.resolvedUrl("pages/ChampionPoolPage.qml")
                onTap: nav.push(url)
            }
            FluPaneItem {
                title: qsTr("最近队友")
                icon: FluentIcons.Group
                url: Qt.resolvedUrl("pages/TeammatesPage.qml")
                onTap: nav.push(url)
            }
            FluPaneItem {
                title: qsTr("ARAM 增益")
                icon: FluentIcons.Shield
                url: Qt.resolvedUrl("pages/AramPage.qml")
                onTap: nav.push(url)
            }
            FluPaneItemSeparator {}
            FluPaneItem {
                title: qsTr("工具")
                icon: FluentIcons.DeveloperTools
                url: Qt.resolvedUrl("pages/ToolsPage.qml")
                onTap: nav.push(url)
            }
            FluPaneItemSeparator {}
        }

        footerItems: FluObject {
            FluPaneItem {
                title: qsTr("组件预览")
                icon: FluentIcons.Color
                url: Qt.resolvedUrl("pages/ShowcasePage.qml")
                onTap: nav.push(url)
            }
            FluPaneItem {
                title: qsTr("设置")
                icon: FluentIcons.Settings
                url: Qt.resolvedUrl("pages/SettingsPage.qml")
                onTap: nav.push(url)
            }
        }

        Component.onCompleted: {
            nav.setCurrentIndex(0)
        }
    }
}
