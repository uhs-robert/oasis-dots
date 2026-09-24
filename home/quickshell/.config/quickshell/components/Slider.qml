// home/quickshell/.config/quickshell/components/Slider.qml
import QtQuick
import "../theme"

Item {
    id: root

    property real value: 0
    property bool on_selection: false
    signal moved(real value)

    implicitHeight: Style.px(14)

    function set_from_x(x) {
        root.moved(Math.max(0, Math.min(1, x / track.width)));
    }

    Rectangle {
        id: track
        visible: !Style.segmented_levels
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        radius: Style.radius(3)
        color: Theme.bg_surface

        Rectangle {
            width: track.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            radius: parent.radius
            color: root.on_selection && Style.selection_inverse ? Style.selection_fg : Theme.theme_primary
        }
    }

    Meter {
        visible: Style.segmented_levels
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        value: root.value
        hot_from: 0.9
        on_selection: root.on_selection
    }

    MouseArea {
        anchors.fill: parent
        onPressed: mouse => root.set_from_x(mouse.x)
        onPositionChanged: mouse => {
            if (pressed) root.set_from_x(mouse.x);
        }
    }
}
