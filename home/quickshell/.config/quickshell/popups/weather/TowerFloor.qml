// home/quickshell/.config/quickshell/popups/weather/TowerFloor.qml
import QtQuick
import "../../theme"

// The dark floor the PS2 towers stand on: a faint haze above the horizon, fading into the dark below it.
Item {
    id: root

    property real haze_h: 40

    Rectangle {
        width: parent.width
        height: root.haze_h
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary, 0.12) }
        }
    }

    Rectangle {
        y: root.haze_h
        width: parent.width
        height: parent.height - root.haze_h
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_strong, 0.2) }
            GradientStop { position: 1; color: Qt.alpha(Theme.bg_shadow, 0.5) }
        }
    }

    Rectangle {
        y: root.haze_h
        width: parent.width
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.alpha(Theme.theme_primary_light, 0.3) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
}
