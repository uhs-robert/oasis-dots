import QtQuick
import "../../theme"

// A day's reading as a vertical targeting scale: ticks lit up to `value` (0-1), a caption above and the figure beside the lit tip.
// A `mark` (0-1, negative for none) adds a lock-coloured hairline with its own figure on the other side, for a gust or peak over the reading.
Item {
    id: root

    property real value: 0
    property real mark: -1
    property string caption: ""
    property string value_text: ""
    property string mark_text: ""
    property color color: Style.text_primary
    property color mark_color: Style.selection_brackets.a > 0 ? Style.selection_brackets : Theme.theme_label

    readonly property int caption_h: Math.round(Style.fs(-3) + 4)
    readonly property int gauge_w: 10
    readonly property real base_y: root.height
    readonly property bool has_mark: root.mark >= 0
    readonly property real mark_y: root.base_y - Math.round(Math.max(0, Math.min(1, root.mark)) * (scale_ticks.tick_count - 1)) * scale_ticks.pitch
    readonly property real tip_y: root.base_y - scale_ticks.mark_x

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.caption
        color: root.color
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
    }

    TickGauge {
        id: scale_ticks
        x: Math.round((root.width - root.gauge_w) / 2)
        y: root.base_y
        width: Math.max(8, root.height - root.caption_h - 14)
        height: root.gauge_w
        transformOrigin: Item.TopLeft
        rotation: -90
        value: root.value
        color: root.color
    }

    Rectangle {
        visible: root.has_mark
        x: scale_ticks.x - 4
        y: root.mark_y - 0.5
        width: root.gauge_w + 8
        height: 1.5
        color: root.mark_color
    }

    Text {
        visible: root.value_text !== ""
        x: root.has_mark ? scale_ticks.x - width - 6 : Math.round((root.width - width) / 2)
        y: Math.max(root.caption_h, root.has_mark ? root.tip_y - height / 2 : root.tip_y - height - 3)
        text: root.value_text
        color: Style.text_strong
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
    }

    Text {
        visible: root.has_mark && root.mark_text !== ""
        x: scale_ticks.x + root.gauge_w + 6
        y: Math.max(root.caption_h, root.mark_y - height / 2)
        text: root.mark_text
        color: root.mark_color
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
    }
}
