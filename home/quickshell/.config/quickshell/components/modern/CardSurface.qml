// home/quickshell/.config/quickshell/components/modern/CardSurface.qml
import QtQuick
import "../../theme"
import ".."

// A card on a layered popup: a faint plate, raised with a highlight and the tab gradient when selected.
Rectangle {
    id: root

    property bool selected: false
    // Toasts float on their own, so they take the popup frame's gradient.
    property bool floating: false

    radius: root.floating ? Style.frame_radius : Style.radius(8)
    border.width: 1
    border.color: Style.frame_border_color
    gradient: Gradient {
        GradientStop { position: 0; color: root.selected ? Style.tab_active_shade : root.floating ? Style.frame_shade : Qt.alpha(Theme.fg_strong, 0.035) }
        GradientStop { position: 1; color: root.selected ? Style.tab_active_bg : root.floating ? Style.frame_color : Qt.alpha(Theme.fg_strong, 0.02) }
    }

    Sheen {
        color_top: root.selected || root.floating ? Style.sheen : "transparent"
        corner: root.radius
        edge: 1
    }
}
