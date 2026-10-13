// home/quickshell/.config/quickshell/components/clock_marker/EnergyTanksMarker.qml
import QtQuick
import "../../theme"

// metroid: energy tanks that empty as the meeting nears, beside a two-digit ENERGY readout; in a meeting the tanks are empty, the readout reads 00 and flashes like low energy.
Row {
    id: root

    // Shared marker inputs; see MeetingMarker.
    property int minutes: 0
    property bool in_meeting: false
    property real progress: 0
    property bool on_accent: false
    property color ink: "black"
    property font text_font

    readonly property int tank_count: 4
    readonly property int full_tanks: root.in_meeting ? 0 : Math.ceil((1 - root.progress) * root.tank_count - 0.001)
    readonly property color tank_color: root.on_accent ? root.ink : Theme.theme_secondary
    readonly property color alarm_color: root.on_accent ? root.ink : Theme.warning

    // 0 to 1; how strongly the low-energy alarm is lit.
    property real alarm: 0

    spacing: 5

    TextMetrics {
        id: number_width
        font: root.text_font
        text: "00"
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Repeater {
            model: root.tank_count

            Rectangle {
                required property int index
                readonly property bool full: index < root.full_tanks
                width: 6
                height: 8
                radius: 1
                color: full ? root.tank_color : "transparent"
                border.width: 1
                border.color: full ? root.tank_color : Qt.tint(Qt.alpha(root.tank_color, 0.55), Qt.alpha(root.alarm_color, root.alarm))
            }
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.ceil(number_width.advanceWidth)
        text: root.in_meeting ? "00" : String(Math.min(99, root.minutes)).padStart(2, "0")
        textFormat: Text.PlainText
        color: Qt.tint(root.on_accent ? root.ink : Style.bar_fg, Qt.alpha(root.alarm_color, root.alarm))
        font: root.text_font
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
    }

    SequentialAnimation on alarm {
        running: root.in_meeting && root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 500; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.alarm = 0
    }
}
