// home/quickshell/.config/quickshell/components/ps2/GlowBar.qml
import QtQuick
import "../../theme"

// The System Configuration level: a thin bar on a faint track, its lit part glowing.
Item {
    id: root

    property real value: 0
    property color color: Theme.theme_primary_light
    readonly property real fill: root.width * Math.max(0, Math.min(1, root.value))

    implicitHeight: 8

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 2
        radius: 1
        color: Qt.alpha(Theme.theme_primary, 0.16)
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: root.fill
        height: 6
        radius: 3
        color: Qt.alpha(root.color, 0.22)
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: root.fill
        height: 2
        radius: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(root.color, 0.5) }
            GradientStop { position: 1; color: Theme.fg_strong }
        }
    }

    Rectangle {
        visible: root.fill > 0
        x: root.fill - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: 4
        radius: 2
        color: Theme.fg_strong
    }
}
