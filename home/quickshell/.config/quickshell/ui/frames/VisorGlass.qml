import QtQuick
import QtQuick.Shapes
import qs.theme
import "PanelCuts.js" as Cuts

// A combat visor pane: glass fill, bottom corners cut with the bar islands' notched bracket, small top cuts when floating.
Shape {
    id: root

    // 0 keeps the top corners square, for frames hung flush from an island.
    property real top_cut: 6
    // The corners that touch the bar stay square.
    property var square: Cuts.none
    property color border_color: Style.frame_border_color
    property real border_width: Math.max(1, Style.frame_border_width)

    readonly property real k: Math.min(18, root.width / 4, root.height / 3)
    readonly property real t: Math.min(root.top_cut, root.height / 4)
    readonly property real step_y: root.height - root.k * 0.52

    visible: Style.frame_visor
    preferredRendererType: Shape.CurveRenderer

    function outline(i) {
        return Cuts.visor(root.width, root.height, i, root.k, root.t, root.step_y, root.square).map(p => Qt.point(p[0], p[1]));
    }

    ShapePath {
        strokeWidth: -1
        fillColor: Qt.alpha(Theme.bg_crust, 0.94)
        PathPolyline { path: root.outline(0) }
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
        PathPolyline { path: root.outline(0) }
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
        PathPolyline { path: root.outline(0) }
    }

    ShapePath {
        strokeWidth: root.border_width
        strokeColor: root.border_color
        fillColor: "transparent"
        joinStyle: ShapePath.MiterJoin
        PathPolyline { path: root.outline(root.border_width / 2) }
    }

    // A tooth under each notch step, like the bar islands'.
    ShapePath {
        strokeWidth: -1
        fillColor: Qt.alpha(root.border_color, Math.min(1, root.border_color.a * 1.8))
        PathSvg {
            path: {
                const w = root.width, k = root.k, y = root.step_y;
                const tooth = (a, b) => "M " + a + " " + y + " L " + b + " " + y + " L " + b + " " + (y + 3) + " L " + a + " " + (y + 3) + " Z";
                return (root.square.bottom_right ? "" : tooth(w - k * 0.58, w - k * 0.36)) + " " + (root.square.bottom_left ? "" : tooth(k * 0.36, k * 0.58));
            }
        }
    }
}
