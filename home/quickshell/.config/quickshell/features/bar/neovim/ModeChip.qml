import QtQuick
import QtQuick.Shapes
import qs.theme
import "../../../styles/neovim/widgets/Modes.js" as Modes
import qs.features.bar

// Lualine's section a: the HyprVim mode from the Hyprland submap, with an arrow into the next section. In a column
// (`vertical`) there is no room for the label, so it is a square tile with only the glyph, its arrow pointing down
// into the next section (the caller sizes it, BarLayout.mode_chip_column_length).
Item {
    id: root

    property color next_bg: Style.bar_side_bg
    property bool hovered: false
    property bool vertical: false
    readonly property color mode_color: SubmapState.bar_color
    readonly property color fill: root.hovered ? Qt.tint(root.mode_color, Qt.alpha(Theme.fg_strong, 0.15)) : root.mode_color
    // Across the bar: the arrow is drawn as on a row and turned in a column.
    readonly property real thick: root.vertical ? root.width : root.height
    readonly property real arrow: Math.round(root.thick * 0.4)

    implicitWidth: root.vertical ? root.height : Math.ceil(content.width) + 20 + root.arrow

    TextMetrics {
        id: normal_metrics
        font: label.font
        text: "NORMAL"
    }

    Rectangle {
        width: root.vertical ? root.width : root.width - root.arrow
        height: root.vertical ? root.height - root.arrow : root.height
        color: Style.island_fill(root.fill)
    }

    Row {
        id: content
        x: root.vertical ? Math.round((root.width - width) / 2) : 10
        anchors.verticalCenter: parent.verticalCenter
        // A column's tile ends above its arrow.
        anchors.verticalCenterOffset: root.vertical ? -root.arrow / 2 : 0
        spacing: 7

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{e62b}"
            color: Theme.bg_crust
            font.family: Style.bar_font_family
            font.pixelSize: Style.bar_font_size + 1
        }

        Text {
            id: label
            visible: !root.vertical
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(implicitWidth, Math.ceil(normal_metrics.advanceWidth))
            text: Modes.label(SubmapState.submap_name)
            color: Theme.bg_crust
            font.family: Style.bar_font_family
            font.pixelSize: Style.bar_font_size
            font.bold: false
        }
    }

    Matrix4x4 {
        id: turn
        matrix: Qt.matrix4x4(0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    }

    Shape {
        x: root.vertical ? 0 : root.width - root.arrow
        y: root.vertical ? root.height - root.arrow : 0
        width: root.arrow
        height: root.thick
        transform: root.vertical ? [turn] : []
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Style.islands_translucent ? "transparent" : root.next_bg
            PathRectangle { width: root.arrow; height: root.thick }
        }

        // Translucent, the next section's colour fills only beside the arrow instead of under it.
        ShapePath {
            strokeWidth: -1
            fillColor: Style.islands_translucent ? Style.island_fill(root.next_bg) : "transparent"
            PathPolyline {
                path: [Qt.point(0, 0), Qt.point(root.arrow, 0), Qt.point(root.arrow, root.thick), Qt.point(0, root.thick), Qt.point(root.arrow, root.thick / 2), Qt.point(0, 0)]
            }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Style.island_fill(root.fill)
            startX: 0
            startY: 0
            PathLine { x: root.arrow; y: root.thick / 2 }
            PathLine { x: 0; y: root.thick }
            PathLine { x: 0; y: 0 }
        }
    }
}
