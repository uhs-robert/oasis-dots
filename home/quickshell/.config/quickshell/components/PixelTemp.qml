// home/quickshell/.config/quickshell/components/PixelTemp.qml
import QtQuick
import "../theme"

// A temperature whose degree sign is a hollow pixel square raised to cap height.
Row {
    id: root

    readonly property var st: Style.for_item(root)

    property real value: 0
    property string unit: ""
    property color color: root.st.text_fg
    property string font_family: root.st.font_family
    property int font_size: root.st.font_size
    readonly property int ring: Math.max(3, Math.round(root.font_size / 4))

    spacing: 0

    Text {
        id: number_text
        text: Math.round(root.value)
        color: root.color
        font.family: root.font_family
        font.pixelSize: root.font_size
    }

    Item {
        width: root.ring + 2
        height: number_text.height

        Rectangle {
            x: 1
            y: Math.round(number_text.height * 0.18)
            width: root.ring
            height: root.ring
            color: "transparent"
            border.width: 1
            border.color: root.color
        }
    }

    Text {
        visible: root.unit !== ""
        text: root.unit
        color: root.color
        font.family: root.font_family
        font.pixelSize: root.font_size
    }
}
