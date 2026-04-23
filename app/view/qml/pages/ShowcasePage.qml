import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../components"

FluScrollablePage {
    launchMode: FluPageType.SingleInstance
    title: qsTr("组件预览")

    ColumnLayout {
        width: parent.width
        spacing: 18

        FluText {
            text: qsTr("样例展示（LoL 客户端未运行时也能看见图片，直接从 Community Dragon CDN 加载）")
            color: FluColors.Grey120
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        // ----- champion icons -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            paddings: 14
            ColumnLayout {
                anchors.fill: parent
                FluText { text: qsTr("ChampionIcon / PositionIcon"); font: FluTextStyle.Subtitle }
                RowLayout {
                    spacing: 14
                    ChampionIcon { championId: 266; size: 56 }  // Aatrox
                    ChampionIcon { championId: 142; size: 48 }  // Zoe
                    ChampionIcon { championId: 245; size: 40 }  // Ekko
                    ChampionIcon { championId: 103; size: 32 }  // Ahri
                    ChampionIcon { championId: 64;  size: 24 }  // Lee Sin
                    Item { Layout.preferredWidth: 20 }
                    PositionIcon { position: "TOP"; size: 28 }
                    PositionIcon { position: "JUNGLE"; size: 28 }
                    PositionIcon { position: "MIDDLE"; size: 28 }
                    PositionIcon { position: "BOTTOM"; size: 28 }
                    PositionIcon { position: "UTILITY"; size: 28 }
                }
            }
        }

        // ----- items / spells / runes -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            paddings: 14
            ColumnLayout {
                anchors.fill: parent
                FluText { text: qsTr("ItemRow / SpellPair / RuneBadge"); font: FluTextStyle.Subtitle }
                RowLayout {
                    spacing: 16
                    Layout.alignment: Qt.AlignVCenter
                    SpellPair { spell1: 4;  spell2: 14; size: 28 }  // Flash + Ignite
                    RuneBadge { keystoneId: 8005; subStyleId: 8100; size: 44 }  // PTA + Domination
                    ItemRow {
                        items: [3078, 3153, 3074, 3031, 3036, 3111, 3363]
                        slotSize: 34
                    }
                }
            }
        }

        // ----- tier badges -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            paddings: 14
            ColumnLayout {
                anchors.fill: parent
                FluText { text: qsTr("TierBadge"); font: FluTextStyle.Subtitle }
                GridLayout {
                    columns: 3
                    columnSpacing: 24
                    rowSpacing: 8
                    TierBadge { tier: "IRON"; division: "II"; leaguePoints: 45; emblemSize: 30 }
                    TierBadge { tier: "BRONZE"; division: "I"; leaguePoints: 12; emblemSize: 30 }
                    TierBadge { tier: "SILVER"; division: "III"; leaguePoints: 88; emblemSize: 30 }
                    TierBadge { tier: "GOLD"; division: "II"; leaguePoints: 34; emblemSize: 30 }
                    TierBadge { tier: "PLATINUM"; division: "IV"; leaguePoints: 72; emblemSize: 30 }
                    TierBadge { tier: "EMERALD"; division: "I"; leaguePoints: 91; emblemSize: 30 }
                    TierBadge { tier: "DIAMOND"; division: "II"; leaguePoints: 24; emblemSize: 30 }
                    TierBadge { tier: "MASTER"; division: ""; leaguePoints: 125; emblemSize: 30 }
                    TierBadge { tier: "GRANDMASTER"; division: ""; leaguePoints: 380; emblemSize: 30 }
                    TierBadge { tier: "CHALLENGER"; division: ""; leaguePoints: 920; emblemSize: 30 }
                    TierBadge { tier: "UNRANKED"; emblemSize: 30 }
                }
            }
        }

        // ----- score badges -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            paddings: 14
            ColumnLayout {
                anchors.fill: parent
                FluText { text: qsTr("ScoreBadge"); font: FluTextStyle.Subtitle }
                RowLayout {
                    spacing: 10
                    ScoreBadge { score: 82 }
                    ScoreBadge { score: 65 }
                    ScoreBadge { score: 50 }
                    ScoreBadge { score: 28 }
                    ScoreBadge { score: 88; tags: ["MVP"] }
                    ScoreBadge { score: 41; tags: ["ACE"] }
                }
            }
        }

        // ----- damage bars -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            paddings: 14
            ColumnLayout {
                anchors.fill: parent
                FluText { text: qsTr("DamageBar"); font: FluTextStyle.Subtitle }
                DamageBar { Layout.fillWidth: true; damage: 38420; share: 1.0;  teamId: 100 }
                DamageBar { Layout.fillWidth: true; damage: 24150; share: 0.63; teamId: 100 }
                DamageBar { Layout.fillWidth: true; damage: 18910; share: 0.49; teamId: 200 }
                DamageBar { Layout.fillWidth: true; damage: 12045; share: 0.31; teamId: 200 }
            }
        }

        // ----- misc -----
        FluArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 110
            paddings: 14
            ColumnLayout {
                anchors.fill: parent
                FluText { text: qsTr("WinLossDots / QueueBadge / ProfileIcon"); font: FluTextStyle.Subtitle }
                RowLayout {
                    spacing: 16
                    Layout.alignment: Qt.AlignVCenter
                    WinLossDots {
                        matches: [
                            {win: true}, {win: true}, {win: false}, {win: true}, {win: true},
                            {win: false}, {win: true}, {win: false}, {win: false}, {win: true}
                        ]
                    }
                    QueueBadge { queueId: 420 }
                    QueueBadge { queueId: 440 }
                    QueueBadge { queueId: 450 }
                    QueueBadge { queueId: 1700 }
                    Item { Layout.preferredWidth: 10 }
                    ProfileIcon { iconId: 29; level: 321; size: 48 }
                    ProfileIcon { iconId: 4625; level: 80; size: 48 }
                }
            }
        }
    }
}
