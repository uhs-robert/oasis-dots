import QtQuick
import "../../theme"

// A daily tower laid on its side: a translucent prism filled from the left to `value`, a bright cap where the fill stops.
Item {
    id: root

    property real value: 0
    property color fill_color: Theme.info
    readonly property real fill_w: root.width * Math.max(0, Math.min(1, root.value))

    implicitHeight: 10

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: 5
        color: Qt.alpha(Theme.theme_primary, 0.08)
    }

    Rectangle {
        anchors.fill: parent
        radius: 2
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_light, 0.4) }
            GradientStop { position: 0.3; color: Qt.alpha(Theme.theme_primary_strong, 0.3) }
            GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary_strong, 0.12) }
        }
    }

    Rectangle {
        visible: root.fill_w > 0
        width: root.fill_w
        height: parent.height
        radius: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(root.fill_color, 0.45) }
            GradientStop { position: 1; color: Qt.alpha(root.fill_color, 0.95) }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: parent.height * 0.38
        color: Qt.alpha(Theme.bg_shadow, 0.25)
    }

    Rectangle {
        visible: root.fill_w > 0
        x: Math.min(root.width - width, Math.max(0, root.fill_w - width))
        y: -2
        width: 2
        height: parent.height + 4
        radius: 1
        color: Qt.lighter(root.fill_color, 1.35)
    }
}
