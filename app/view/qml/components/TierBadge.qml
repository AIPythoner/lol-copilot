import QtQuick
import QtQuick.Layouts
import FluentUI

RowLayout {
    id: root
    property string tier: ""          // "DIAMOND" / "UNRANKED" / ...
    property string division: ""      // "I".."IV"
    property int leaguePoints: 0
    property int emblemSize: 28
    property bool showText: true
    spacing: 6

    Image {
        Layout.preferredWidth: root.emblemSize
        Layout.preferredHeight: root.emblemSize
        smooth: true
        cache: true
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        source: Lcu.tierEmblem(root.tier || "UNRANKED")
        sourceSize.width: root.emblemSize * 2
        sourceSize.height: root.emblemSize * 2
    }

    FluText {
        visible: root.showText
        text: root.tier && root.tier !== "UNRANKED" && root.tier !== "NONE"
            ? root.tier.charAt(0) + root.tier.slice(1).toLowerCase() + (root.division ? " " + root.division : "")
              + (root.leaguePoints ? "  " + root.leaguePoints + " LP" : "")
            : qsTr("Unranked")
        color: _tierColor(root.tier)
    }

    function _tierColor(t) {
        switch ((t || "").toUpperCase()) {
            case "IRON": return "#7d6c5e"
            case "BRONZE": return "#a07048"
            case "SILVER": return "#9faebd"
            case "GOLD": return "#d4a04a"
            case "PLATINUM": return "#5ac8b5"
            case "EMERALD": return "#3ea04a"
            case "DIAMOND": return "#4684d4"
            case "MASTER": return "#b964e0"
            case "GRANDMASTER": return "#e06c75"
            case "CHALLENGER": return "#f8d458"
            default: return FluColors.Grey120
        }
    }
}
