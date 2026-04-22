import QtQuick
import QtQuick.Layouts
import FluentUI

RowLayout {
    id: root
    property var items: []       // list of 7 item ids (item0..item6)
    property int slotSize: 28
    property int trinketSeparation: 6
    spacing: 3

    Repeater {
        model: 6
        delegate: ItemSlot {
            size: root.slotSize
            itemId: root.items && root.items.length > index ? root.items[index] : 0
        }
    }

    Item {
        Layout.preferredWidth: root.trinketSeparation
    }

    ItemSlot {
        size: root.slotSize
        itemId: root.items && root.items.length > 6 ? root.items[6] : 0
    }
}
