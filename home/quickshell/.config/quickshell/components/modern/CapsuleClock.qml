// home/quickshell/.config/quickshell/components/modern/CapsuleClock.qml
import QtQuick
import "../../theme"

// The bar clock as one capsule line: bold tabular time, a small zone, a hairline, then the date.
Row {
    id: root

    property string time_text: ""
    property string zone_text: ""
    property string date_text: ""
    property bool compact: false
    // The Clock module measures zeroed digits in time_font; the floor keeps the island from resizing every second.
    property real time_floor: 0
    readonly property font time_font: time_label.font

    spacing: 10

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Text {
            id: time_label
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(implicitWidth, Math.ceil(root.time_floor))
            text: root.time_text
            color: Style.bar_clock_fg
            font.family: Style.bar_clock_font
            font.pixelSize: Style.bar_font_size + 3
            font.weight: Font.DemiBold
            font.letterSpacing: -0.3
            font.features: { "tnum": 1 }
        }

        Text {
            id: zone_label
            visible: root.zone_text !== ""
            anchors.baseline: time_label.baseline
            text: root.zone_text
            color: Style.text_muted
            font.family: Style.bar_font_family
            font.pixelSize: Math.max(8, Style.bar_font_size - 3)
            font.weight: Font.DemiBold
            font.letterSpacing: 0.8
            font.capitalization: Font.AllUppercase
        }
    }

    Rectangle {
        visible: !root.compact
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 14
        color: Qt.alpha(Theme.fg_core, 0.14)
    }

    Text {
        visible: !root.compact
        anchors.verticalCenter: parent.verticalCenter
        text: root.date_text
        color: Style.text_dim
        font.family: Style.bar_font_family
        font.pixelSize: Style.bar_font_size
        font.weight: Font.Medium
    }
}
