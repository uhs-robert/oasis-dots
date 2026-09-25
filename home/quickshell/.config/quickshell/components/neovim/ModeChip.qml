// home/quickshell/.config/quickshell/components/neovim/ModeChip.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"
import "../../services"
import "Modes.js" as Modes

// Lualine's section a: the HyprVim mode from the Hyprland submap, with an arrow into the next section.
Item {
    id: root

    property color next_bg: Style.bar_side_bg
    property bool hovered: false
    readonly property color mode_color: SubmapState.bar_color
    readonly property color fill: root.hovered ? Qt.tint(root.mode_color, Qt.alpha(Theme.fg_strong, 0.15)) : root.mode_color
    readonly property real arrow: Math.round(root.height * 0.4)

    implicitWidth: Math.ceil(content.width) + 20 + root.arrow

    TextMetrics {
        id: normal_metrics
        font: label.font
        text: "NORMAL"
    }

    Rectangle {
        width: root.width - root.arrow
        height: root.height
        color: root.fill
    }

    Row {
        id: content
        x: 10
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
        x: root.width - root.arrow
        width: root.arrow
        height: root.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.next_bg
            PathRectangle { width: root.arrow; height: root.height }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: root.fill
            startX: 0
            startY: 0
            PathLine { x: root.arrow; y: root.height / 2 }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }
}
