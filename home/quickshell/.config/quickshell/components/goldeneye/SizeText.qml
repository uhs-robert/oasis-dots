// home/quickshell/.config/quickshell/components/goldeneye/SizeText.qml
import QtQuick
import "../../theme"
import "../../theme/Watch.js" as W

// "W x H" with the numbers in seven-segment digits and the multiplication sign in a text font.
Row {
    id: root

    property int width_px: 0
    property int height_px: 0
    property color color: Style.wk.lit
    property real pixel_size: Style.fs(-3)

    spacing: root.pixel_size * 0.3

    Text {
        text: root.width_px
        color: root.color
        font.family: W.digit_font
        font.pixelSize: root.pixel_size
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "×"
        color: root.color
        font.family: W.mono_font
        font.pixelSize: root.pixel_size
    }

    Text {
        text: root.height_px
        color: root.color
        font.family: W.digit_font
        font.pixelSize: root.pixel_size
    }
}
