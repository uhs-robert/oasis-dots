// home/quickshell/.config/quickshell/components/SkewBar.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

// An HEV-style readout bar: outlined cells leaning right, lit up to `value`.
Item {
    id: root

    property real value: 0
    property int cells: 10
    property real lean: 0.53
    property real gap: 2
    property color on_color: Style.meter_on
    property color off_color: Style.meter_off
    property color edge_color: Style.hairline_dim
    readonly property real shift: root.lean * root.height
    readonly property real cell_width: Math.max(2, (root.width - root.shift - root.gap * (root.cells - 1)) / root.cells)

    implicitHeight: 11

    Repeater {
        model: root.cells

        Rectangle {
            required property int index
            readonly property bool lit: index < Math.round(Math.max(0, Math.min(1, root.value)) * root.cells)
            x: index * (root.cell_width + root.gap)
            width: root.cell_width
            height: root.height
            antialiasing: true
            color: lit ? root.on_color : root.off_color
            border.width: lit ? 0 : 1
            border.color: root.edge_color
            transform: Matrix4x4 {
                matrix: Qt.matrix4x4(1, -root.lean, 0, root.shift, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
            }
        }
    }
}
