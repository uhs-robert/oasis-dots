// home/quickshell/.config/quickshell/components/neovim/BorderTitle.qml
import QtQuick
import "../../theme"

// A title chip set into a floating frame's top border; centre it on the border line.
Item {
    id: root

    property var st: Style
    property string title: ""
    property color fill: root.st.title_bg
    property color ink: root.st.title_fg

    implicitWidth: chip.width
    implicitHeight: chip.height

    // Breaks the border line around the chip.
    Rectangle {
        x: -4
        y: Math.round(chip.height / 2) - 1
        width: chip.width + 8
        height: root.st.frame_border_width + 2
        color: root.st.frame_color
    }

    Rectangle {
        id: chip
        width: label.implicitWidth + 14
        height: label.implicitHeight + 4
        radius: 3
        color: root.fill

        Text {
            id: label
            anchors.centerIn: parent
            text: root.title
            color: root.ink
            font.family: root.st.title_font_family
            font.pixelSize: root.st.fs(-2)
            font.bold: true
        }
    }
}
