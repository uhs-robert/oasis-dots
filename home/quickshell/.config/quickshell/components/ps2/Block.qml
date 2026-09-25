// home/quickshell/.config/quickshell/components/ps2/Block.qml
import QtQuick
import "../../theme"

// A PS2 browser block: a translucent slab with a lit top edge, floating on a soft shadow; the selected one glows.
Item {
    id: root

    property bool selected: false
    property real radius: 6

    Rectangle {
        x: 2
        y: 3
        width: parent.width
        height: parent.height
        radius: root.radius
        color: Qt.alpha(Theme.bg_shadow, 0.35)
    }

    Rectangle {
        visible: root.selected
        anchors.fill: parent
        anchors.margins: -3
        radius: root.radius + 3
        color: Qt.alpha(Theme.theme_primary, 0.16)
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        border.width: 1
        border.color: Qt.alpha(Theme.theme_primary_light, root.selected ? 0.5 : 0.16)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary, root.selected ? 0.3 : 0.12) }
            GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary_strong, root.selected ? 0.16 : 0.05) }
        }
    }

    Rectangle {
        x: root.radius
        y: 1
        width: parent.width - root.radius * 2
        height: 1
        color: Qt.alpha(Theme.fg_strong, root.selected ? 0.35 : 0.12)
    }
}
