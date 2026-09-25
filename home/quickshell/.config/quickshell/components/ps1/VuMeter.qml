// home/quickshell/.config/quickshell/components/ps1/VuMeter.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"

// The CD Player's segmented level meter, one row per channel: green, yellow from 70%, red from 90%.
Item {
    id: root

    // One level per row, 0-1; a single value draws one row.
    property var levels: [0]
    property bool muted: false
    property int segment_count: 16
    readonly property int gap: 2
    readonly property int rows: Math.max(1, root.levels.length)
    readonly property real row_height: Math.max(3, Math.floor((root.height - (root.rows - 1)) / root.rows))
    readonly property real segment_width: Math.max(2, (root.width - root.gap * (root.segment_count - 1)) / root.segment_count)
    signal moved(real value)

    implicitWidth: root.segment_count * 5
    implicitHeight: Style.px(12)
    opacity: root.muted ? 0.4 : 1

    function color_at(i) {
        const f = (i + 1) / root.segment_count;
        return f > 0.9 ? Theme.red : f > 0.7 ? Theme.yellow : Theme.green;
    }

    Column {
        spacing: 1

        Repeater {
            model: root.rows

            Row {
                id: meter_row
                required property int index
                readonly property real level: Math.max(0, Math.min(1, Number(root.levels[meter_row.index]) || 0))
                spacing: root.gap

                Repeater {
                    model: root.segment_count

                    Rectangle {
                        required property int index
                        readonly property bool lit: index < Math.round(meter_row.level * root.segment_count)
                        width: root.segment_width
                        height: root.row_height
                        color: lit ? root.color_at(index) : Qt.alpha(root.color_at(index), 0.14)
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: mouse => root.moved(Math.max(0, Math.min(1, mouse.x / Math.max(1, root.width))))
        onPositionChanged: mouse => {
            if (pressed) root.moved(Math.max(0, Math.min(1, mouse.x / Math.max(1, root.width))));
        }
    }
}
