// home/quickshell/.config/quickshell/components/metroid/VisorIsland.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"

// A bar island cut like the Prime combat visor: notched bracket ends, energy-tank ticks, a crosshair under the center.
Item {
    id: root

    property bool cap_left: false
    property bool cap_right: false
    property real cap: 0
    property color bg_color: Theme.bg_crust
    property real border_width: 1
    property color border_color: Theme.theme_primary
    property bool marks_shown: true

    readonly property real h: root.height
    readonly property real w: root.width
    readonly property real bx0: root.cap_left ? root.cap : 0
    readonly property real bx1: root.cap_right ? root.w - root.cap : root.w
    readonly property real cx: root.w / 2
    readonly property bool center: root.cap_left && root.cap_right
    // The notch step: how far out along the cap it starts and ends, and its height.
    readonly property real u0: root.cap * 0.42
    readonly property real u1: root.cap * 0.64
    readonly property real v: root.h * 0.52

    function outline(i, closed) {
        const h = root.h, c = root.cap, v = root.v;
        let d = root.cap_left
            ? "M " + (root.bx0 - c + i) + " 0 L " + (root.bx0 - root.u1) + " " + v + " L " + (root.bx0 - root.u0) + " " + v + " L " + root.bx0 + " " + (h - i)
            : "M 0 " + (h - i);
        d += " L " + root.bx1 + " " + (h - i);
        d += root.cap_right
            ? " L " + (root.bx1 + root.u0) + " " + v + " L " + (root.bx1 + root.u1) + " " + v + " L " + (root.bx1 + c - i) + " 0"
            : " L " + root.w + " " + (h - i);
        return closed ? d + " L " + root.w + " 0 L 0 0 Z" : d;
    }

    readonly property string rail_path: {
        const y = root.h - root.border_width - 3.5, a = root.bx0 + 6, b = root.bx1 - 6;
        if (root.center) return "M " + a + " " + y + " L " + (root.cx - 12) + " " + y + " M " + (root.cx + 12) + " " + y + " L " + b + " " + y;
        return "M " + a + " " + y + " L " + b + " " + y;
    }

    readonly property string teeth_path: {
        const out = [], v = root.v;
        if (root.cap_left) out.push(-1);
        if (root.cap_right) out.push(1);
        return out.map(s => {
            const x = s < 0 ? root.bx0 : root.bx1;
            return "M " + (x + s * root.u0) + " " + v + " L " + (x + s * root.u1) + " " + v + " L " + (x + s * root.u1) + " " + (v + 3) + " L " + (x + s * root.u0) + " " + (v + 3) + " Z";
        }).join(" ") || "M 0 0";
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.h
                GradientStop { position: 0; color: Qt.alpha(Theme.ui_visual_bg, 0.75) }
                GradientStop { position: 1; color: root.bg_color }
            }
            PathSvg { path: root.outline(0, true) }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.cx
                centerY: root.h * 2.4
                focalX: root.cx
                focalY: root.h * 2.4
                centerRadius: Math.max(root.w * 0.6, root.h * 2)
                focalRadius: 0
                GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary, 0.16) }
                GradientStop { position: 0.7; color: Qt.alpha(Theme.theme_primary, 0) }
            }
            PathSvg { path: root.outline(0, true) }
        }

        ShapePath {
            strokeWidth: root.border_width
            strokeColor: root.border_width > 0 ? root.border_color : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.MiterJoin
            PathSvg { path: root.outline(root.border_width / 2, false) }
        }

        // Energy-tank squares along the bottom edge.
        ShapePath {
            strokeWidth: 3
            strokeColor: Qt.alpha(Theme.theme_primary, 0.32)
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            strokeStyle: ShapePath.DashLine
            dashPattern: [1, 1]
            PathSvg { path: root.rail_path }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(Theme.theme_primary, 0.8)
            PathSvg { path: root.teeth_path }
        }
    }

    Shape {
        visible: root.center
        anchors.fill: parent
        opacity: root.marks_shown ? 1 : 0
        preferredRendererType: Shape.CurveRenderer

        Behavior on opacity {
            NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
        }

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(Theme.theme_primary, 0.85)
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathSvg { path: "M " + root.cx + " " + (root.h - 2) + " L " + root.cx + " " + (root.h - 8) + " M " + (root.cx - 4) + " " + (root.h - 5) + " L " + (root.cx + 4) + " " + (root.h - 5) }
        }
    }
}
