import QtQuick
import "../../theme"

// A gauge as a memory card's row of 15 save blocks, `value` (0-1) of them used. With `mark_last`, the last used block
// is lit like the selected save, for a reading that marks a point in a range rather than an amount.
Item {
    id: root

    property real value: 0
    property color fill_color: Theme.theme_primary_light
    property bool mark_last: false

    readonly property int card_blocks: 15
    readonly property int gap: 2
    readonly property real block_w: Math.max(3, (root.width - root.gap * (root.card_blocks - 1)) / root.card_blocks)
    readonly property real clamped: Math.max(0, Math.min(1, root.value))
    readonly property int used: root.mark_last ? Math.round(root.clamped * (root.card_blocks - 1)) + 1 : Math.round(root.clamped * root.card_blocks)

    implicitHeight: Math.round(Math.min(Style.px(12), Math.max(6, root.block_w)))

    Row {
        spacing: root.gap

        Repeater {
            model: root.card_blocks

            Rectangle {
                id: block
                required property int index
                readonly property bool is_used: block.index < root.used
                readonly property bool is_marked: root.mark_last && block.index === root.used - 1

                width: root.block_w
                height: root.height
                radius: 2
                color: block.is_used ? Qt.alpha(root.fill_color, block.is_marked ? 1 : 0.7) : Qt.alpha(Theme.bg_shadow, 0.45)
                border.width: block.is_marked ? 2 : 1
                border.color: block.is_marked ? Style.text_strong : block.is_used ? Qt.lighter(root.fill_color, 1.3) : Qt.alpha(Style.frame_border_color, 0.6)
            }
        }
    }
}
