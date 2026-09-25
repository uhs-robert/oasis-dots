// home/quickshell/.config/quickshell/components/neovim/FloatFrame.qml
import QtQuick
import "../../theme"

// A Neovim floating window: FloatBorder round the frame, the title as a chip set into the top border, a status in the border at the right.
Item {
    id: root

    property var st: Style
    property string title: ""
    property string status: ""
    property real chip_height: 20
    property real radius: root.st.frame_radius
    readonly property real border_y: Math.round(root.chip_height / 2)

    Rectangle {
        y: root.border_y
        width: root.width
        height: Math.max(0, root.height - root.border_y)
        radius: root.radius
        color: root.st.frame_color
        border.width: root.st.frame_border_width
        border.color: root.st.frame_border_color
    }

    BorderTitle {
        id: chip
        visible: root.title !== ""
        x: 12
        y: root.border_y - Math.round(height / 2)
        st: root.st
        title: root.title
    }

    Rectangle {
        visible: root.status !== "" && x > chip.x + chip.width + 12
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: root.border_y - height / 2
        width: status_text.implicitWidth + 10
        height: status_text.implicitHeight
        color: root.st.frame_color

        Text {
            id: status_text
            anchors.centerIn: parent
            text: root.status
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-3)
        }
    }
}
