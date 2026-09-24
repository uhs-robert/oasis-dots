// home/quickshell/.config/quickshell/components/OctagonFrame.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../theme"

// A viewport cut to an octagon: gradient edge line, glass fill, clipped scan rows, corner struts and edge ticks.
Item {
    id: root

    property var st: Style.for_item(root)
    property real cut: root.st.frame_octagon
    property real edge: 1.5
    property color edge_color: root.st.frame_border_color
    property color strut_color: root.st.frame_struts
    readonly property real c: Math.max(0, Math.min(root.cut, root.width / 2, root.height / 2))
    readonly property real inner_cut: Math.max(0, root.c - root.edge * (2 - Math.SQRT2))
    readonly property real strut_length: root.c * 1.5

    function octagon(i, k) {
        const w = root.width - i, h = root.height - i;
        return [Qt.point(i + k, i), Qt.point(w - k, i), Qt.point(w, i + k), Qt.point(w, h - k), Qt.point(w - k, h), Qt.point(i + k, h), Qt.point(i, h - k), Qt.point(i, i + k), Qt.point(i + k, i)];
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
                GradientStop { position: 0; color: root.edge_color }
                GradientStop { position: 1; color: Qt.alpha(root.edge_color, root.edge_color.a * 0.4) }
            }
            PathPolyline { path: root.octagon(0, root.c) }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width / 2
                centerY: 0
                focalX: root.width / 2
                focalY: 0
                centerRadius: Math.max(root.width * 0.65, root.height)
                focalRadius: 0
                GradientStop { position: 0; color: Qt.tint(Theme.bg_core, Qt.alpha(root.edge_color, 0.07)) }
                GradientStop { position: 0.8; color: root.st.frame_color }
            }
            PathPolyline { path: root.octagon(root.edge, root.inner_cut) }
        }
    }

    // Static rows trimmed to the cut corners; nothing animates them.
    Repeater {
        model: root.st.scanlines ? Math.max(0, Math.ceil((root.height - root.edge * 2) / 3)) : 0

        Rectangle {
            required property int index
            readonly property real row_y: root.edge + index * 3
            readonly property real trim: Math.max(0, root.c + root.edge - Math.min(row_y, root.height - row_y - 1))

            x: Math.max(root.edge, trim)
            y: row_y
            width: Math.max(0, root.width - x * 2)
            height: 1
            color: root.st.scanline_color
        }
    }

    Repeater {
        model: root.strut_color.a > 0 && root.c > 0 ? [[0, 0, 45], [1, 0, 135], [0, 1, -45], [1, 1, -135]] : []

        Rectangle {
            required property var modelData

            x: (modelData[0] === 1 ? root.width - root.c / 2 : root.c / 2)
            y: (modelData[1] === 1 ? root.height - root.c / 2 : root.c / 2) - 1
            width: root.strut_length
            height: 2
            antialiasing: true
            transformOrigin: Item.Left
            rotation: modelData[2]
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.strut_color }
                GradientStop { position: 1; color: Qt.alpha(root.strut_color, 0) }
            }
        }
    }

    Repeater {
        model: root.strut_color.a > 0 ? [[0.5, 0, true], [0.5, 1, true], [0, 0.5, false], [1, 0.5, false]] : []

        Rectangle {
            required property var modelData
            readonly property bool upright: modelData[2]

            width: upright ? 2 : 9
            height: upright ? 9 : 2
            x: (root.width - width) * modelData[0]
            y: (root.height - height) * modelData[1]
            color: root.strut_color
        }
    }
}
