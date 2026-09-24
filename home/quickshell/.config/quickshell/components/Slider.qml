// home/quickshell/.config/quickshell/components/Slider.qml
import QtQuick
import "../theme"

Item {
    id: root

    readonly property var st: Style.for_item(root)

    property real value: 0
    property bool on_selection: false
    signal moved(real value)

    implicitHeight: Style.px(14)

    function set_from_x(x) {
        root.moved(Math.max(0, Math.min(1, x / track.width)));
    }

    Rectangle {
        id: track
        visible: !root.st.segmented_levels
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
            color: root.on_selection && root.st.selection_inverse ? root.st.selection_fg : Theme.theme_primary
        }
    }

    Meter {
        visible: root.st.segmented_levels
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
