// home/quickshell/.config/quickshell/components/ps2/ConfigRow.qml
import QtQuick
import "../../theme"

// A System Configuration line: a thin caps label at the left, its value at the right, an optional glowing bar beneath.
Item {
    id: root

    property string label: ""
    property string value: ""
    property color value_color: Theme.fg_strong
    // Negative hides the bar.
    property real level: -1
    property color level_color: Theme.theme_primary_light

    implicitHeight: label_text.implicitHeight + (root.level >= 0 ? bar.implicitHeight + 2 : 0) + 6

    Text {
        id: label_text
        y: 3
        text: root.label
        color: Theme.theme_primary_light
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 5
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2
    }

    Text {
        anchors.right: parent.right
        anchors.baseline: label_text.baseline
        anchors.left: label_text.right
        anchors.leftMargin: 10
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
        text: root.value
        color: root.value_color
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 2
        font.weight: Font.Light
    }

    GlowBar {
        id: bar
        visible: root.level >= 0
        y: label_text.y + label_text.implicitHeight + 2
        width: parent.width
        value: Math.max(0, root.level)
        color: root.level_color
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_light, 0.22) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
}
