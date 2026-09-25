pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"

// The link bars joining a workspace's materia slots in pairs; with no slots it is one bare socket.
Item {
    id: root

    property int count: 0
    property int slot: 24
    property real spacing: 6
    property bool lit: false
    property bool raised: false

    Repeater {
        model: Math.floor(root.count / 2)

        Rectangle {
            required property int index
            x: index * 2 * (root.slot + root.spacing) + root.slot / 2
            y: (root.height - height) / 2
            width: root.slot + root.spacing
            height: 6
            color: root.lit ? Theme.theme_secondary_strong : Qt.tint(Theme.fg_dim, Qt.alpha(Theme.bg_surface, 0.3))

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.alpha(Theme.fg_strong, 0.3)
            }
        }
    }

    MateriaSlot {
        visible: root.count === 0
        anchors.centerIn: parent
        width: root.slot
        height: root.slot
        lit: root.lit
        raised: root.raised
        opacity: 0.7
    }
}
