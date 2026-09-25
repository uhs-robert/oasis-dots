// home/quickshell/.config/quickshell/components/ps2/DialogPanel.qml
import QtQuick
import "../../theme"

// A PS2 system dialog box: a rounded translucent panel with a lit rim, glowing when selected.
Item {
    id: root

    property bool selected: false
    property color accent: Theme.theme_primary_light
    property real radius: 10

    Rectangle {
        visible: root.selected
        anchors.fill: parent
        radius: root.radius
        color: Qt.alpha(Theme.theme_primary, 0.1)
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.selected ? 3 : 0
        radius: root.radius - (root.selected ? 3 : 0)
        border.width: 1
        border.color: Qt.alpha(root.accent, root.selected ? 0.6 : 0.25)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary, root.selected ? 0.24 : 0.1) }
            GradientStop { position: 1; color: Qt.alpha(Theme.bg_shadow, root.selected ? 0.35 : 0.2) }
        }
    }

    Rectangle {
        x: root.radius
        y: root.selected ? 4 : 1
        width: parent.width - root.radius * 2
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.alpha(Theme.fg_strong, root.selected ? 0.4 : 0.15) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
}
