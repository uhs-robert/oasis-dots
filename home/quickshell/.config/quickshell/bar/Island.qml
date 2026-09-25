// home/quickshell/.config/quickshell/bar/Island.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../components"
import "../theme"

Item {
    id: root

    property color bg_color: "#232634"
    property bool cap_left: false
    property bool cap_right: false
    property int border_width: 0
    property color border_color: "transparent"
    property color scanline_color: "transparent"
    property int scanline_period: 3
    property color shade_color: "transparent"
    property bool shade_vertical: false
    property color dither_color: "transparent"
    // An inner line following the slants and bottom edge, inset_gap in from them.
    property real inset_gap: 0
    property real inset_width: 0
    property color inset_color: "transparent"
    // Visor glass: curved bottom corners instead of slants, glass gradient into bg_color, border along sides and bottom.
    property bool visor: false
    readonly property bool shaded: root.shade_color.a > 0 || root.visor
    default property alias content: layout.children

    readonly property alias body_item: body
    readonly property int cap_width: height / 2

    signal clicked

    height: 30
    width: body.width + (cap_left ? cap_width : 0) + (cap_right ? cap_width : 0)

    // The popup style's shade and dither, behind the modules and clipped to the slants.
    Shape {
        visible: root.shaded && !root.visor
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            // The left island mirrors the shade so its light edge faces the screen centre like the right one.
            fillGradient: LinearGradient {
                x1: root.shade_vertical ? 0 : root.cap_right && !root.cap_left ? root.width : 0
                y1: 0
                x2: root.shade_vertical ? 0 : root.cap_right && !root.cap_left ? 0 : root.width
                y2: root.height
                GradientStop { position: 0; color: root.shade_color }
                GradientStop { position: 1; color: root.bg_color }
            }
            startX: 0
            startY: 0
            PathLine { x: root.width; y: 0 }
            PathLine { x: root.width - (root.cap_right ? root.cap_width : 0); y: root.height }
            PathLine { x: root.cap_left ? root.cap_width : 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }

    Shape {
        id: visor_glass
        readonly property real rx: root.cap_width
        readonly property real ry: root.height / 2

        function edge(i, closed) {
            const w = root.width, h = root.height, x = Math.max(0, visor_glass.rx - i), y = Math.max(0, visor_glass.ry - i);
            let d = root.cap_left ? "M " + i + " 0 L " + i + " " + (h - i - y) + " A " + x + " " + y + " 0 0 0 " + (i + x) + " " + (h - i) : "M 0 " + (h - i);
            d += root.cap_right ? " L " + (w - i - x) + " " + (h - i) + " A " + x + " " + y + " 0 0 0 " + (w - i) + " " + (h - i - y) + " L " + (w - i) + " 0" : " L " + w + " " + (h - i);
            return closed ? d + " L " + w + " 0 L 0 0 Z" : d;
        }

        visible: root.visor
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.height
                GradientStop { position: 0; color: Qt.alpha(Theme.ui_visual_bg, 0.75) }
                GradientStop { position: 1; color: root.bg_color }
            }
            PathSvg { path: visor_glass.edge(0, true) }
        }

        ShapePath {
            strokeWidth: root.border_width
            strokeColor: root.border_width > 0 ? root.border_color : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathSvg { path: visor_glass.edge(root.border_width / 2, false) }
        }
    }

    Dither {
        anchors.fill: parent
        slant_left: root.cap_left ? root.cap_width : 0
        slant_right: root.cap_right ? root.cap_width : 0
        color: root.dither_color
    }

    Rectangle {
        id: body

        x: cap_left ? root.cap_width : 0
        height: root.height
        width: Math.ceil(layout.implicitWidth) + 16
        color: root.shaded ? "transparent" : root.bg_color

        // A tick scale rising from the bottom edge.
        Loader {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.border_width
            height: 5
            active: Style.bar_ticks.a > 0
            sourceComponent: TickScale {
                from_end: true
                step: 12
                major_length: 5
                minor_length: 3
                major_color: Style.bar_ticks
            }
        }

        // Declared before the layout so module MouseAreas stack above it.
        MouseArea {
            anchors.fill: parent
            onClicked: root.clicked()
        }

        RowLayout {
            id: layout
            x: 8
            height: parent.height
            spacing: 16
        }
    }

    // Caps overlap the body by 1px so fractional scaling (1.6 on the laptop) leaves no seam.
    Shape {
        visible: root.cap_left
        width: root.cap_width + 1
        height: root.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.shaded ? "transparent" : root.bg_color
            startX: 0
            startY: 0
            PathLine { x: root.cap_width + 1; y: 0 }
            PathLine { x: root.cap_width + 1; y: root.height }
            PathLine { x: root.cap_width; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }

    Shape {
        visible: root.cap_right
        x: root.width - root.cap_width - 1
        width: root.cap_width + 1
        height: root.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.shaded ? "transparent" : root.bg_color
            startX: 0
            startY: 0
            PathLine { x: root.cap_width + 1; y: 0 }
            PathLine { x: 1; y: root.height }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }

    // Static scanlines clipped to the slants; nothing animates them.
    Item {
        visible: root.scanline_color.a > 0
        anchors.fill: parent

        Repeater {
            model: root.scanline_color.a > 0 ? Math.ceil(root.height / root.scanline_period) : 0

            Rectangle {
                required property int index
                readonly property real slant: index * root.scanline_period * root.cap_width / root.height

                x: root.cap_left ? slant : 0
                y: index * root.scanline_period
                width: root.width - x - (root.cap_right ? slant : 0)
                height: 1
                color: root.scanline_color
            }
        }
    }

    // Traces the slants and bottom edge; the sides on the screen edge stay open.
    Shape {
        visible: root.border_width > 0 && !root.visor
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.border_width
            strokeColor: root.border_color
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.MiterJoin

            PathPolyline {
                path: {
                    const w = root.width, h = root.height, c = root.cap_width, i = root.border_width / 2;
                    const pts = [];
                    pts.push(root.cap_left ? Qt.point(i, 0) : Qt.point(0, h - i));
                    if (root.cap_left) pts.push(Qt.point(c + i, h - i));
                    if (root.cap_right) pts.push(Qt.point(w - c - i, h - i));
                    pts.push(root.cap_right ? Qt.point(w - i, 0) : Qt.point(w, h - i));
                    return pts;
                }
            }
        }
    }

    Shape {
        visible: root.inset_width > 0 && root.inset_color.a > 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.inset_width
            strokeColor: root.inset_color
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.MiterJoin

            PathPolyline {
                path: {
                    const w = root.width, h = root.height, off = root.inset_gap + root.inset_width / 2;
                    const slope = root.cap_width / h;
                    const shift = off * Math.sqrt(1 + slope * slope);
                    const pts = [];
                    if (root.cap_left) pts.push(Qt.point(shift, 0), Qt.point(shift + (h - off) * slope, h - off));
                    else pts.push(Qt.point(0, h - off));
                    if (root.cap_right) pts.push(Qt.point(w - shift - (h - off) * slope, h - off), Qt.point(w - shift, 0));
                    else pts.push(Qt.point(w, h - off));
                    return pts;
                }
            }
        }
    }
}
