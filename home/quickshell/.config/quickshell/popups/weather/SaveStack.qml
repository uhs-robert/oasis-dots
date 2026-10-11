// home/quickshell/.config/quickshell/popups/weather/SaveStack.qml
import QtQuick
import "../../theme"
import "../../services"

// A memory card's 15 save blocks stood on end, used from block `low` (0-1) up to block `high`; the top used block
// is lit like the selected save. Each used block takes the temperature colour of its own place on the scale.
Item {
    id: root

    property real low: 0
    property real high: 0
    property real scale_min: 0
    property real scale_max: 1
    property bool selected: false

    readonly property int card_blocks: 15
    readonly property int gap: 2
    readonly property real block_h: Math.max(2, (root.height - root.gap * (root.card_blocks - 1)) / root.card_blocks)
    readonly property int low_block: root.block_at(root.low)
    readonly property int high_block: Math.max(root.low_block, root.block_at(root.high))
    readonly property real high_y: root.y_of(root.high_block)
    readonly property real low_bottom: root.y_of(root.low_block) + root.block_h

    function block_at(v) {
        return Math.round(Math.max(0, Math.min(1, v)) * (root.card_blocks - 1));
    }

    // Block 0 sits at the bottom so warmer reads higher.
    function y_of(block) {
        return (root.card_blocks - 1 - block) * (root.block_h + root.gap);
    }

    Repeater {
        model: root.card_blocks

        Rectangle {
            id: block
            required property int index
            readonly property bool is_used: block.index >= root.low_block && block.index <= root.high_block
            readonly property bool is_marked: block.index === root.high_block
            readonly property color fill: WeatherState.temp_color(root.scale_min + (root.scale_max - root.scale_min) * block.index / (root.card_blocks - 1))

            width: root.width
            height: root.block_h
            y: root.y_of(block.index)
            radius: 2
            color: block.is_used ? Qt.alpha(block.fill, block.is_marked ? 1 : root.selected ? 0.8 : 0.55) : Qt.alpha(Theme.bg_shadow, 0.45)
            border.width: block.is_marked ? 2 : 1
            border.color: block.is_marked ? Style.text_strong : block.is_used ? Qt.lighter(block.fill, 1.3) : Qt.alpha(Style.frame_border_color, 0.6)
        }
    }
}
