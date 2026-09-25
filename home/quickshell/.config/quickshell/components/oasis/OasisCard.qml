// home/quickshell/.config/quickshell/components/oasis/OasisCard.qml
import QtQuick
import "../../theme"
import ".."

// A raised night-blue card with a light top edge; sand marks the selected one, a red edge a critical one.
Rectangle {
    id: root

    property bool selected: false
    property bool critical: false
    // Toasts float on their own and take the full panel look: sky gradient and an outer edge.
    property bool panel: false

    readonly property color sand: Theme.theme_secondary

    radius: root.panel ? Style.radius(8) : Style.radius(6)
    border.width: root.panel || root.selected ? 1 : 0
    border.color: root.selected ? Qt.alpha(root.sand, 0.45) : Style.frame_border_color
    gradient: Gradient {
        GradientStop { position: 0; color: root.panel ? Style.frame_shade : Qt.alpha(Theme.bg_surface, 0.7) }
        GradientStop { position: 1; color: root.panel ? Style.frame_color : Qt.alpha(Theme.bg_surface, 0.3) }
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: root.selected
        color: Qt.alpha(root.sand, 0.07)
    }

    Sheen {
        color_top: Style.sheen
        corner: root.radius
        edge: root.border.width
    }

    Rectangle {
        visible: root.critical || root.selected
        x: root.border.width
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: Math.max(0, root.height - root.radius * 2)
        topRightRadius: 2
        bottomRightRadius: 2
        color: root.critical ? Qt.alpha(Theme.theme_label, 0.8) : root.sand
    }
}
