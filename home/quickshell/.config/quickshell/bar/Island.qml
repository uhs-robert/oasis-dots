// home/quickshell/.config/quickshell/bar/Island.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../components"
import "../components/metroid" as Metroid
import "../services"
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
    // Metroid Prime visor glass cut into notched bracket ends (VisorIsland) instead of slants.
    property bool visor: false
    // Cava plays along the bottom edge; the visor's crosshair makes way for it.
    property bool wave_shown: false
    // A capsule this many px inside the island's top and ends, resting on its bottom edge; sheen_color lights its top edge.
    property real capsule_inset: 0
    property color sheen_color: "transparent"
    readonly property bool capsule: root.capsule_inset > 0
    readonly property real capsule_width: body.width
    readonly property real capsule_radius: (root.height - root.capsule_inset) / 2
    // The submap tab hangs from this island.
    property bool tab_joined: false
    readonly property bool joined: root.capsule && (root.tab_joined || (Popups.open_name !== "" && Popups.open_anchor === body) || (Popups.open_name === "" && Tooltip.visible && Tooltip.island === body))
    // 1 while a popup or the submap tab hangs from the capsule: its bottom corners flatten to meet it.
    property real join: 0
    readonly property bool shaded: root.shade_color.a > 0 || root.visor || root.capsule
    default property alias content: layout.children

    readonly property alias body_item: body
    // Lualine: side islands end in arrows, the center one leans; content brings its own padding.
    readonly property bool lualine: Style.bar_lualine
    // Fill for the right cap when the content's last segment runs into it.
    property color cap_right_fill: "transparent"
    property color cap_left_fill: "transparent"
    readonly property bool center: root.cap_left && root.cap_right
    readonly property int cap_width: root.lualine ? Math.round(height * 0.4) : root.visor ? Math.round(height * 0.8) : height / 2
    readonly property real pad: root.capsule ? Style.bar_capsule_pad : root.lualine ? (root.center ? 10 : 0) : 8

    signal clicked

    height: 30
    width: root.capsule ? body.width + root.capsule_inset * 2 : body.width + (cap_left ? cap_width : 0) + (cap_right ? cap_width : 0)

    onJoinedChanged: {
        join_anim.stop();
        unjoin_anim.stop();
        (root.joined ? join_anim : unjoin_anim).restart();
    }

    NumberAnimation { id: join_anim; target: root; property: "join"; to: 1; duration: 180; easing.type: Easing.OutCubic }

    // Waits for the popup to fold away before the corners round again.
    SequentialAnimation {
        id: unjoin_anim
        PauseAnimation { duration: 120 }
        NumberAnimation { target: root; property: "join"; to: 0; duration: 90; easing.type: Easing.InCubic }
    }

    Rectangle {
        visible: root.capsule
        x: root.capsule_inset
        y: root.capsule_inset
        width: body.width
        height: root.height - root.capsule_inset
        topLeftRadius: root.capsule_radius
        topRightRadius: root.capsule_radius
        bottomLeftRadius: root.capsule_radius * (1 - root.join)
        bottomRightRadius: root.capsule_radius * (1 - root.join)
        border.width: root.border_width
        border.color: root.border_color
        gradient: Gradient {
            GradientStop { position: 0; color: capsule_fill.top_color }
            GradientStop { position: 1; color: capsule_fill.bottom_color }
        }

        // Joined, the bottom takes the popup's top shade and drops its border so the fills run on unbroken.
        Rectangle {
            id: capsule_fill
            readonly property color top_color: root.shade_color.a > 0 ? root.shade_color : root.bg_color
            readonly property color bottom_color: Qt.tint(root.bg_color, Qt.alpha(capsule_fill.top_color, root.join))
            visible: root.join > 0 && root.border_width > 0
            x: root.border_width
            y: parent.height - root.border_width
            width: parent.width - root.border_width * 2
            height: root.border_width
            color: capsule_fill.bottom_color
            opacity: root.join
        }

        Sheen {
            color_top: root.sheen_color
            corner: root.capsule_radius
            edge: root.border_width
        }
    }

    // The popup style's shade and dither, behind the modules and clipped to the slants.
    Shape {
        visible: root.shaded && !root.visor && !root.capsule
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

    Loader {
        anchors.fill: parent
        active: root.visor
        sourceComponent: Metroid.VisorIsland {
            cap_left: root.cap_left
            cap_right: root.cap_right
            cap: root.cap_width
            bg_color: root.bg_color
            border_width: root.border_width
            border_color: root.border_color
            marks_shown: !root.wave_shown
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

        x: root.capsule ? root.capsule_inset : cap_left ? root.cap_width : 0
        height: root.height
        width: Math.ceil(layout.implicitWidth) + root.pad * 2
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
            x: root.pad
            y: root.capsule ? root.capsule_inset : 0
            height: parent.height - y
            spacing: root.lualine && !root.center ? 0 : Style.bar_module_gap
        }
    }

    // Caps overlap the body by 1px so fractional scaling (1.6 on the laptop) leaves no seam.
    Shape {
        visible: root.cap_left && !root.capsule
        width: root.cap_width + 1
        height: root.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.cap_left_fill.a > 0 ? root.cap_left_fill : root.shaded ? "transparent" : root.bg_color
            PathPolyline {
                path: {
                    const c = root.cap_width, h = root.height;
                    if (!root.lualine) return [Qt.point(0, 0), Qt.point(c + 1, 0), Qt.point(c + 1, h), Qt.point(c, h), Qt.point(0, 0)];
                    if (root.center) return [Qt.point(c, 0), Qt.point(c + 1, 0), Qt.point(c + 1, h), Qt.point(0, h), Qt.point(c, 0)];
                    return [Qt.point(c, 0), Qt.point(c + 1, 0), Qt.point(c + 1, h), Qt.point(c, h), Qt.point(0, h / 2), Qt.point(c, 0)];
                }
            }
        }
    }

    Shape {
        visible: root.cap_right && !root.capsule
        x: root.width - root.cap_width - 1
        width: root.cap_width + 1
        height: root.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.cap_right_fill.a > 0 ? root.cap_right_fill : root.shaded ? "transparent" : root.bg_color
            PathPolyline {
                path: {
                    const c = root.cap_width, h = root.height;
                    if (!root.lualine || root.center) return [Qt.point(0, 0), Qt.point(c + 1, 0), Qt.point(1, h), Qt.point(0, h), Qt.point(0, 0)];
                    return [Qt.point(0, 0), Qt.point(1, 0), Qt.point(c + 1, h / 2), Qt.point(1, h), Qt.point(0, h), Qt.point(0, 0)];
                }
            }
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
        visible: root.border_width > 0 && !root.visor && !root.capsule
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
        visible: root.inset_width > 0 && root.inset_color.a > 0 && !root.capsule
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
