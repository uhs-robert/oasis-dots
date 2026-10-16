import QtQuick
import "../../components"
import "../../theme"

// An FF7 menu window inside the popup: gradient fill in a light rim with a faint inner line.
Item {
    id: root

    property real radius: 5

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Style.frame_color
        border.width: 2
        border.color: Style.frame_border_color

        WindowGradient {
            anchors.fill: parent
            anchors.margins: 2
            top_radius: Math.max(0, root.radius - 2)
            bottom_radius: top_radius
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Math.max(0, root.radius - 2)
            color: "transparent"
            border.width: 1
            border.color: Style.frame_inset_color
        }
    }
}
