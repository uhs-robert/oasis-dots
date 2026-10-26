import QtQuick
import QtQuick.Shapes
import qs.theme
import "../../../styles/neovim/widgets/Modes.js" as Modes
import qs.features.bar

// Lualine's section a: the HyprVim mode from the Hyprland submap, with an arrow into the next section. In a column
// (`vertical`) there is no room for the label or the arrow, so it is a square tile with only the glyph.
Item {
    id: root

    property color next_bg: Style.bar_side_bg
    property bool hovered: false
    property bool vertical: false
    readonly property color mode_color: SubmapState.bar_color
    readonly property color fill: root.hovered ? Qt.tint(root.mode_color, Qt.alpha(Theme.fg_strong, 0.15)) : root.mode_color
    readonly property real arrow: root.vertical ? 0 : Math.round(root.height * 0.4)

    implicitWidth: root.vertical ? root.height : Math.ceil(content.width) + 20 + root.arrow

    TextMetrics {
        id: normal_metrics
        font: label.font
        text: "NORMAL"
    }

    Rectangle {
        width: root.width - root.arrow
        height: root.height
        color: Style.island_fill(root.fill)
    }

    Row {
        id: content
        x: root.vertical ? Math.round((root.width - width) / 2) : 10
        anchors.verticalCenter: parent.verticalCenter
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

    Shape {
        visible: !root.vertical
        x: root.width - root.arrow
        width: root.arrow
        height: root.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Style.islands_translucent ? "transparent" : root.next_bg
            PathRectangle { width: root.arrow; height: root.height }
        }

        // Translucent, the next section's colour fills only beside the arrow instead of under it.
        ShapePath {
            strokeWidth: -1
            fillColor: Style.islands_translucent ? Style.island_fill(root.next_bg) : "transparent"
            PathPolyline {
                path: [Qt.point(0, 0), Qt.point(root.arrow, 0), Qt.point(root.arrow, root.height), Qt.point(0, root.height), Qt.point(root.arrow, root.height / 2), Qt.point(0, 0)]
            }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Style.island_fill(root.fill)
            startX: 0
            startY: 0
            PathLine { x: root.arrow; y: root.height / 2 }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }
}
