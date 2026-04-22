import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    property int spell1: 0
    property int spell2: 0
    property int size: 20
    spacing: 2

    SpellIcon { spellId: root.spell1; size: root.size }
    SpellIcon { spellId: root.spell2; size: root.size }
}
