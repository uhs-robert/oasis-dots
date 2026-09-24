// home/quickshell/.config/quickshell/components/ChamferFrame.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../theme"

// A steel panel: top-left and bottom-right corners cut by frame_cut, stepped notches, registration marks at the corners.
Item {
    id: root

    property var st: Style.for_item(root)
    property color border_color: root.st.frame_border_color
    property color line_color: root.st.frame_line.a > 0 ? root.st.frame_line : root.border_color
    // The panel sits this far inside the item so the marks land outside its corners.
    readonly property real gap: root.st.frame_marks.a > 0 ? root.st.inset_pad : 0
    readonly property real cut: root.st.frame_cut
    readonly property bool notched: root.st.frame_notch > 0 && root.width > 180
    readonly property real notch: root.notched ? root.st.frame_notch : 0


    function outline(i) {
        const x0 = root.gap + i, y0 = root.gap + i, x1 = root.width - root.gap - i, y1 = root.height - root.gap - i;
        const c = Math.max(0, Math.min(root.cut - i * 0.41, (y1 - y0) / 2)), n = root.notch;
        const pts = [Qt.point(x0 + c, y0)];
        if (root.notched) pts.push(Qt.point(x1 - 64, y0), Qt.point(x1 - 60, y0 + n));
        pts.push(Qt.point(x1, y0 + n), Qt.point(x1, y1 - c), Qt.point(x1 - c, y1));
        if (root.notched) pts.push(Qt.point(x0 + 56, y1), Qt.point(x0 + 52, y1 - n));
        pts.push(Qt.point(x0, y1 - n), Qt.point(x0, y0 + c), Qt.point(x0 + c, y0));
        return pts;
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
                y2: root.height
                GradientStop { position: 0; color: root.border_color }
                GradientStop { position: 0.55; color: root.line_color }
                GradientStop { position: 1; color: root.border_color }
            }
            PathPolyline { path: root.outline(0) }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.height
                GradientStop { position: 0; color: root.st.frame_shade.a > 0 ? root.st.frame_shade : root.st.frame_color }
                GradientStop { position: 0.75; color: root.st.frame_color }
            }
            PathPolyline { path: root.outline(Math.max(1, root.st.frame_border_width)) }
        }
    }

    CornerBrackets {
        anchors.fill: parent
        color: root.st.frame_marks
        inset: 0
        arm: 7
        all_corners: true
    }
}
