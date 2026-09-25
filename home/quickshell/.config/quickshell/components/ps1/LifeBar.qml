// home/quickshell/.config/quickshell/components/ps1/LifeBar.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"

// An MGS LIFE-style gauge: label and value over a long framed bar, green until under 10% charge.
ColumnLayout {
    id: root

    property string label: "BAT"
    property real value: 0
    property string value_text: Math.round(root.value * 100) + "%"
    property string detail: ""
    readonly property bool low: root.value < 0.1
    readonly property color fill: root.low ? Theme.red : Theme.green

    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            text: root.label
            color: root.low ? Theme.red : Theme.bright_green
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 2
            font.bold: true
            font.letterSpacing: 1
            style: Text.Raised
            styleColor: Style.text_shadow
        }

        Item { Layout.fillWidth: true }

        Text {
            text: root.value_text
            color: Style.text_strong
            font.family: Style.font_family
            font.pixelSize: Style.font_size + 2
            style: Text.Raised
            styleColor: Style.text_shadow
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.px(12)
        color: Theme.bg_shadow
        border.width: 2
        border.color: Style.frame_border_color

        Rectangle {
            x: 3
            y: 3
            width: Math.max(0, (parent.width - 6) * Math.max(0, Math.min(1, root.value)))
            height: parent.height - 6
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.tint(root.fill, Qt.alpha(Theme.fg_strong, 0.35)) }
                GradientStop { position: 0.5; color: root.fill }
                GradientStop { position: 1; color: Qt.darker(root.fill, 1.4) }
            }
        }
    }

    Text {
        visible: root.detail !== ""
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.detail
        color: Style.text_muted
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 4
    }
}
