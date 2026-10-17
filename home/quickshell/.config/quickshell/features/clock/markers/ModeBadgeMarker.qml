import QtQuick
import qs.theme

// neovim: a lualine mode block, MTG 12m before a meeting and a plain MTG during one. On the accent fill it inverts to an ink block.
MarkerBase {
    id: root

    readonly property color block_color: root.on_accent ? root.ink : root.in_meeting ? Theme.syntax_exception : Theme.syntax_special
    readonly property color text_color: root.on_accent ? Theme.theme_primary : Theme.bg_crust

    implicitWidth: Math.ceil(upcoming_width.advanceWidth) + 16
    implicitHeight: label.implicitHeight + 4

    // Sized from the widest countdown, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "MTG 00m"
    }

    Rectangle {
        id: block
        anchors.fill: parent
        radius: 2
        color: root.block_color
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.in_meeting ? "MTG" : "MTG " + root.minutes + "m"
        textFormat: Text.PlainText
        color: root.text_color
        font: root.text_font
    }
}
