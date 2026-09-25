// home/quickshell/.config/quickshell/components/ps1/Digits.qml
import QtQuick
import "../../theme"

// 7-segment digits (DSEG7) over their unlit "8" ghosts, like the CD Player and codec readouts.
Item {
    id: root

    property string text: ""
    property color color: Theme.green
    property real size: 18

    implicitWidth: lit_text.implicitWidth
    implicitHeight: lit_text.implicitHeight

    Text {
        text: root.text.replace(/[0-9]/g, "8").replace(/[^8.:\s]/g, "8")
        color: Qt.alpha(root.color, 0.12)
        font: lit_text.font
    }

    Text {
        id: lit_text
        text: root.text
        color: root.color
        font.family: "DSEG7 Classic"
        font.pixelSize: root.size
        font.bold: true
    }
}
