import QtQuick
import "../../theme"

// The recessed strip of a weapon's slot bar that the materia sockets sit in.
Rectangle {
    radius: 4
    border.width: 1
    border.color: Theme.fg_muted
    gradient: Gradient {
        GradientStop { position: 0; color: Qt.alpha(Theme.bg_crust, 0.55) }
        GradientStop { position: 1; color: Qt.alpha(Theme.bg_crust, 0.3) }
    }
}
