// home/quickshell/.config/quickshell/components/VisorGlass.qml
import QtQuick
import QtQuick.Shapes
import "../theme"

// A visor pane: rounded top, wide elliptical bottom and a glass gradient.
Shape {
    id: root

    property real top_radius: Style.frame_radius
    property color border_color: Style.frame_border_color
    property real border_width: Math.max(1, Style.frame_border_width)

    readonly property real rt: Math.min(root.top_radius, root.width / 2, root.height / 2)
    readonly property real rx: Math.min(34, root.width / 4)
    readonly property real ry: Math.max(0, Math.min(46, (root.height - root.rt) * 0.6))

    visible: Style.frame_visor
    preferredRendererType: Shape.CurveRenderer

    function outline(i) {
        const w = root.width, h = root.height, t = Math.max(0, root.rt - i), x = Math.max(0, root.rx - i), y = Math.max(0, root.ry - i);
        return "M " + i + " " + (i + t)
            + " A " + t + " " + t + " 0 0 1 " + (i + t) + " " + i
            + " L " + (w - i - t) + " " + i
            + " A " + t + " " + t + " 0 0 1 " + (w - i) + " " + (i + t)
            + " L " + (w - i) + " " + (h - i - y)
            + " A " + x + " " + y + " 0 0 1 " + (w - i - x) + " " + (h - i)
            + " L " + (i + x) + " " + (h - i)
            + " A " + x + " " + y + " 0 0 1 " + i + " " + (h - i - y)
            + " Z";
    }

    ShapePath {
        strokeWidth: -1
        fillColor: Qt.alpha(Theme.bg_crust, 0.94)
        PathSvg { path: root.outline(0) }
    }

    ShapePath {
        strokeWidth: -1
        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: 0
            y2: root.height
            GradientStop { position: 0; color: Qt.alpha(Theme.ui_visual_bg, 0.55) }
            GradientStop { position: 1; color: Qt.alpha(Theme.ui_visual_bg, 0) }
        }
        PathSvg { path: root.outline(0) }
    }

    ShapePath {
        strokeWidth: -1
        fillGradient: RadialGradient {
            centerX: root.width / 2
            centerY: root.height * 1.3
            focalX: root.width / 2
            focalY: root.height * 1.3
            centerRadius: Math.max(root.width * 0.5, root.height * 0.9)
            focalRadius: 0
            GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary, 0.2) }
            GradientStop { position: 0.6; color: Qt.alpha(Theme.theme_primary, 0) }
        }
        PathSvg { path: root.outline(0) }
    }

    ShapePath {
        strokeWidth: root.border_width
        strokeColor: root.border_color
        fillColor: "transparent"
        PathSvg { path: root.outline(root.border_width / 2) }
    }
}
