// home/quickshell/.config/quickshell/components/clock_marker/ModeBadgeMarker.qml
import QtQuick
import "../../theme"

// neovim: a lualine mode block, MTG 12m before a meeting and a pulsing IN MTG during one. On the accent fill it inverts to an ink block.
Item {
    id: root

    // Shared marker inputs; see MeetingMarker.
    property int minutes: 0
    property bool in_meeting: false
    property real progress: 0
    property bool on_accent: false
    property color ink: "black"
    property font text_font

    readonly property color block_color: root.on_accent ? root.ink : root.in_meeting ? Theme.syntax_exception : Theme.syntax_special
    readonly property color text_color: root.on_accent ? Theme.theme_primary : Theme.bg_crust

    implicitWidth: Math.ceil(root.in_meeting ? live_width.advanceWidth : upcoming_width.advanceWidth) + 16
    implicitHeight: label.implicitHeight + 4

    // Sized from the widest countdown, so the minutes ticking down do not resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "MTG 00m"
    }

    TextMetrics {
        id: live_width
        font: root.text_font
        text: "IN MTG"
    }

    Rectangle {
        id: block
        anchors.fill: parent
        radius: 2
        color: root.block_color

        SequentialAnimation on opacity {
            running: root.in_meeting && root.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.55; duration: 500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) block.opacity = 1
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.in_meeting ? "IN MTG" : "MTG " + root.minutes + "m"
        textFormat: Text.PlainText
        color: root.text_color
        font: root.text_font
    }
}
