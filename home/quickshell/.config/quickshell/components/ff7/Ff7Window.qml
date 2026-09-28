// home/quickshell/.config/quickshell/components/ff7/Ff7Window.qml
import QtQuick
import "../../theme"
import ".."

// The FF7 style's own popup window: blue gradient fill, light border and drop shadow.
Item {
    id: root

    property real radius: Style.frame_radius

    Rectangle {
        visible: Style.frame_drop > 0
        x: Style.frame_drop
        y: Style.frame_drop
        width: parent.width
        height: parent.height
        radius: root.radius
        color: Qt.alpha(Theme.bg_shadow, 0.6)
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: root.radius
        color: Style.frame_color
        border.width: Style.frame_border_width
        border.color: Style.frame_border_color

        WindowGradient {
            anchors.fill: parent
            anchors.margins: Style.frame_border_width
            top_radius: Math.max(0, root.radius - Style.frame_border_width)
            bottom_radius: top_radius
        }

        FrameInset {
            top_radius: root.radius
            bottom_radius: root.radius
        }
    }
}
