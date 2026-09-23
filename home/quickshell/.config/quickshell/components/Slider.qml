// home/quickshell/.config/quickshell/components/Slider.qml
import QtQuick
import "../theme"

Item {
    id: root

    property real value: 0
    signal moved(real value)

    implicitHeight: 14

    function set_from_x(x) {
        root.moved(Math.max(0, Math.min(1, x / track.width)));
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        radius: 3
        color: Theme.bg_surface

        Rectangle {
            width: track.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            radius: parent.radius
            color: Theme.theme_primary
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: mouse => root.set_from_x(mouse.x)
        onPositionChanged: mouse => {
            if (pressed) root.set_from_x(mouse.x);
        }
    }
}
