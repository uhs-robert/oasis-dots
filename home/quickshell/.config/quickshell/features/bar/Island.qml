import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.ui.effects
import qs.ui.gauges
import qs.styles.metroid.widgets as Metroid
import qs.theme
import qs.features.popups
import "IslandOutlines.js" as Outlines

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
    // Theme options > Island opacity: every fill goes through faded() (Style.island_fill).
    readonly property real fill_opacity: Style.bar_island_opacity
    readonly property bool translucent: Style.islands_translucent
    // A translucent cap cannot overlap the body, or the overlap shows as a darker line.
    readonly property int cap_overlap: root.translucent ? 0 : 1
    // One of Style.island_shapes; lualine draws its own sections whatever the shape.
    readonly property string shape: root.lualine ? "lualine" : Style.bar_island_shape
    // Metroid Prime visor glass cut into notched bracket ends (VisorIsland) instead of slants.
    readonly property bool visor: root.shape === "visor"
    // A capsule this many px inside the island's top and ends, resting on its bottom edge; sheen_color lights its top edge.
    property real capsule_inset: 0
    property color sheen_color: "transparent"
    readonly property bool capsule: root.shape === "capsule"
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
    // Width the clock's meeting chip adds, which the clock popup leaves out when it sizes from this island.
    property real popup_trim: 0
    // Lualine: side islands end in arrows, the center one leans; content brings its own padding.
    readonly property bool lualine: Style.bar_lualine
    // Fill for the right cap when the content's last segment runs into it.
    property color cap_right_fill: "transparent"
    property color cap_left_fill: "transparent"
    readonly property bool center: root.cap_left && root.cap_right
    // Chamfered corners on the open ends; goldeneye's "watch" adds case lugs on the center island and a white tick at each end.
    readonly property bool watch: root.shape === "watch"
    readonly property bool octagon: root.shape === "octagon" || root.watch
    readonly property real lug: root.watch && root.center ? 4 : 0
    readonly property color tick_color: Style.bar_tick_color
    // nes: a floating Dragon Quest window, its corners cut by one pixel step.
    readonly property bool window: root.shape === "window"
    readonly property int window_edge: root.border_width
    readonly property real window_x: 4
    readonly property real window_width: root.width - root.window_x * 2
    readonly property real window_top: 1
    readonly property real window_bottom: root.height - 1
    // One of IslandOutlines' shapes: a single polygon and its rim, sized and traced there.
    readonly property bool outlined: Outlines.has(root.shape)
    readonly property var outline_rim: root.outlined ? Outlines.rim_path(root.shape, root.width, root.height, root.cap_width, root.cap_left, root.cap_right) : []
    // The rim path moved in by the border: where the fill's effects stop.
    readonly property var outline_inner: root.outlined ? Outlines.inset(root.outline_rim, root.border_width) : []
    readonly property int cap_width: root.outlined ? Outlines.cap_width(root.shape, height) : root.window ? 0 : root.octagon ? Math.round(height * 0.3) : root.lualine ? Math.round(height * 0.4) : root.visor ? Math.round(height * 0.8) : height / 2
    readonly property real pad: root.capsule ? Style.bar_capsule_pad : root.lualine ? (root.center ? 10 : 0) : root.window ? root.window_x + (root.center ? 16 : 6) : root.octagon ? 10 : 8

    readonly property real oct_x0: root.lug
    readonly property real oct_x1: root.width - root.lug
    readonly property real oct_c: root.cap_width
    readonly property real oct_i: root.border_width / 2

    readonly property bool slanted: root.shape === "slant" || root.lualine

    // The fill a row from y0 to y1 lies on, as { x, w }; scanlines, and dither off the slant, clip to it so they follow every shape.
    // The slant samples only y0, as it always has; the other shapes take the narrower end so no row spills past them.
    // y is in the top-bar frame, so a layer clipping to this under a bottom bar must be mirrored with the rest (`mirror`).
    function fill_span(y0, y1) {
        if (root.slanted) {
            const s = y0 * root.cap_width / root.height;
            const x = root.cap_left ? s : 0;
            return { x: x, w: root.width - x - (root.cap_right ? s : 0) };
        }
        const a = root.fill_edges(y0), b = root.fill_edges(y1);
        const x = Math.max(a[0], b[0]);
        return { x: x, w: Math.min(a[1], b[1]) - x };
    }

    // The left and right x of the fill at height y, inside any border that the effects would otherwise cover; [0, 0] outside it.
    function fill_edges(y) {
        const h = root.height, w = root.width, e = root.border_width;
        if (root.window) {
            if (y < root.window_top + e || y > root.window_bottom - e) return [0, 0];
            return [root.window_x + e, root.window_x + root.window_width - e];
        }
        if (root.capsule) {
            const x0 = root.capsule_inset + e, x1 = root.capsule_inset + body.width - e, y0 = root.capsule_inset + e, y1 = h - e;
            if (y < y0 || y > y1) return [0, 0];
            const top_r = Math.max(0, root.capsule_radius - e), bottom_r = Math.max(0, root.capsule_radius * (1 - root.join) - e);
            const corner = (r, dy) => r - Math.sqrt(Math.max(0, r * r - dy * dy));
            const dx = y < y0 + top_r ? corner(top_r, y0 + top_r - y) : y > y1 - bottom_r ? corner(bottom_r, y - y1 + bottom_r) : 0;
            return [x0 + dx, x1 - dx];
        }
        if (root.outlined) return Outlines.span_at(root.outline_inner, y);
        if (root.octagon) {
            const c = root.oct_c;
            const cut = y < c ? c - y : y > h - c ? y - h + c : 0;
            return [root.oct_x0 + (root.cap_left ? cut : 0), root.oct_x1 - (root.cap_right ? cut : 0)];
        }
        // The visor, as VisorIsland cuts it (keep v, u0 and u1 in step with it): each end slopes in to the notch at v, steps in, then on to the bottom.
        if (y > h - e) return [0, 0];
        const c = root.cap_width, v = h * 0.52, u0 = c * 0.42, u1 = c * 0.64;
        const cut = (y <= v ? (c - u1) * y / v : c - u0 + u0 * (y - v) / (h - v)) + e;
        return [root.cap_left ? cut : 0, w - (root.cap_right ? cut : 0)];
    }

    // The screen edge the bar sits on. The decoration below is drawn for "top" (open side down) and mirrored for
    // "bottom"; the modules never flip.
    property string edge: "top"
    readonly property bool flipped: root.edge === "bottom"
    // Shared by the decoration layers that span the island's full height.
    Scale {
        id: mirror
        origin.y: root.height / 2
        yScale: root.flipped ? -1 : 1
    }

    signal clicked

    function faded(c) {
        return Style.island_fill(c);
    }

    height: 30
    width: root.capsule ? body.width + root.capsule_inset * 2 : body.width + (cap_left ? cap_width : 0) + (cap_right ? cap_width : 0) + root.lug * 2

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
        id: capsule_shape
        visible: root.capsule
        x: root.capsule_inset
        y: root.flipped ? 0 : root.capsule_inset
        width: body.width
        height: root.height - root.capsule_inset
        transform: Scale {
            origin.y: capsule_shape.height / 2
            yScale: root.flipped ? -1 : 1
        }
        topLeftRadius: root.capsule_radius
        topRightRadius: root.capsule_radius
        bottomLeftRadius: root.capsule_radius * (1 - root.join)
        bottomRightRadius: root.capsule_radius * (1 - root.join)
        border.width: root.border_width
        border.color: root.border_color
        gradient: Gradient {
            GradientStop { position: 0; color: root.faded(capsule_fill.top_color) }
            GradientStop { position: 1; color: capsule_fill.bottom_fill }
        }

        // Joined, the bottom takes the popup's top shade and drops its border so the fills run on unbroken.
        Rectangle {
            id: capsule_fill
            readonly property color top_color: root.shade_color.a > 0 ? root.shade_color : root.bg_color
            readonly property color bottom_color: Qt.tint(root.bg_color, Qt.alpha(capsule_fill.top_color, root.join))
            // Opaque again as it joins, so a translucent capsule meets the opaque frame without a seam.
            readonly property color bottom_fill: Qt.alpha(capsule_fill.bottom_color, capsule_fill.bottom_color.a * (root.fill_opacity + (1 - root.fill_opacity) * root.join))
            visible: root.join > 0 && root.border_width > 0
            x: root.border_width
            y: parent.height - root.border_width
            width: parent.width - root.border_width * 2
            height: root.border_width
            color: capsule_fill.bottom_fill
            opacity: root.join
        }

        Sheen {
            color_top: root.sheen_color
            corner: root.capsule_radius
            edge: root.border_width
        }
    }

    // The popup style's shade and dither, behind the modules and clipped to the slants.
    Loader {
        anchors.fill: parent
        active: root.shaded && !root.visor && !root.capsule && !root.octagon && !root.window && !root.outlined
        transform: mirror
        sourceComponent: Shape {
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                // The left island mirrors the shade so its light edge faces the screen centre like the right one.
                fillGradient: LinearGradient {
                    x1: root.shade_vertical ? 0 : root.cap_right && !root.cap_left ? root.width : 0
                    y1: 0
                    x2: root.shade_vertical ? 0 : root.cap_right && !root.cap_left ? 0 : root.width
                    y2: root.height
                    GradientStop { position: 0; color: root.faded(root.shade_color) }
                    GradientStop { position: 1; color: root.faded(root.bg_color) }
                }
                startX: 0
                startY: 0
                PathLine { x: root.width; y: 0 }
                PathLine { x: root.width - (root.cap_right ? root.cap_width : 0); y: root.height }
                PathLine { x: root.cap_left ? root.cap_width : 0; y: root.height }
                PathLine { x: 0; y: 0 }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.visor
        transform: mirror
        sourceComponent: Metroid.VisorIsland {
            cap_left: root.cap_left
            cap_right: root.cap_right
            cap: root.cap_width
            bg_color: root.bg_color
            fill_opacity: root.fill_opacity
            border_width: root.border_width
            border_color: root.border_color
        }
    }

    // The octagon: chamfered corners on the open ends, the screen-edge ends square; fill, rim and the case lugs.
    Loader {
        anchors.fill: parent
        active: root.octagon
        sourceComponent: Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillColor: root.faded(root.bg_color)
                PathPolyline {
                    path: {
                        const x0 = root.oct_x0, x1 = root.oct_x1, c = root.oct_c, h = root.height;
                        const l = root.cap_left, r = root.cap_right;
                        return [l ? Qt.point(x0 + c, 0) : Qt.point(x0, 0), r ? Qt.point(x1 - c, 0) : Qt.point(x1, 0), r ? Qt.point(x1, c) : Qt.point(x1, 0), r ? Qt.point(x1, h - c) : Qt.point(x1, h), r ? Qt.point(x1 - c, h) : Qt.point(x1, h), l ? Qt.point(x0 + c, h) : Qt.point(x0, h), l ? Qt.point(x0, h - c) : Qt.point(x0, h), l ? Qt.point(x0, c) : Qt.point(x0, 0)];
                    }
                }
            }
        }
    }

    // The rim sits above the island's content so a module that fills the height cannot cover it.
    Loader {
        anchors.fill: parent
        z: 2
        active: root.octagon
        transform: mirror
        sourceComponent: Shape {
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: root.border_width > 0 ? root.border_width : -1
                strokeColor: root.border_color
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                joinStyle: ShapePath.MiterJoin
                PathPolyline {
                    path: {
                        const x0 = root.oct_x0, x1 = root.oct_x1, c = root.oct_c, h = root.height, i = root.oct_i;
                        const pts = [];
                        if (root.cap_left) pts.push(Qt.point(x0 + c, i), Qt.point(x0 + i, c), Qt.point(x0 + i, h - c), Qt.point(x0 + c, h - i));
                        else pts.push(Qt.point(x0, h - i));
                        if (root.cap_right) pts.push(Qt.point(x1 - c, h - i), Qt.point(x1 - i, h - c), Qt.point(x1 - i, c), Qt.point(x1 - c, i));
                        else pts.push(Qt.point(x1, h - i));
                        return pts;
                    }
                }
            }
        }
    }

    // Case lugs on the center island: short tabs in the rim colour, centred on the ends.
    Repeater {
        model: root.lug > 0 ? [0, 1] : []

        Rectangle {
            required property int modelData
            x: modelData === 0 ? 0 : root.width - root.lug
            y: root.height / 2 - 7
            width: root.lug + 1
            height: 14
            color: root.border_color
            opacity: 0.9
            visible: root.watch
        }
    }

    // The bezel's hour mark at each open end, inside the rim; none on an end that meets the screen edge.
    Repeater {
        model: root.watch ? [0, 1] : []

        Rectangle {
            required property int modelData
            // Above a borrowing style's dither and scanlines, which would hatch it.
            z: 1
            visible: modelData === 0 ? root.cap_left : root.cap_right
            x: modelData === 0 ? root.lug + 5 : root.width - root.lug - 7
            y: (root.height - height) / 2
            width: 2
            height: 12
            color: root.tick_color
        }
    }

    // An outlined shape's fill, one polygon so a translucent fill never stacks. The pixel shape skips the curve
    // renderer's antialiasing so its steps stay crisp.
    Loader {
        anchors.fill: parent
        active: root.outlined
        transform: mirror
        sourceComponent: Shape {
            preferredRendererType: root.shape === "pixel" ? Shape.GeometryRenderer : Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: root.faded(root.bg_color)
                // A style's frame shade, laid out as on the slant.
                fillGradient: root.shade_color.a > 0 ? outline_shade : null
                PathPolyline {
                    path: Outlines.fill_path(root.outline_rim, root.width, root.cap_left, root.cap_right).map(p => Qt.point(p[0], p[1]))
                }
            }

            LinearGradient {
                id: outline_shade
                x1: root.shade_vertical ? 0 : root.cap_right && !root.cap_left ? root.width : 0
                y1: 0
                x2: root.shade_vertical ? 0 : root.cap_right && !root.cap_left ? 0 : root.width
                y2: root.height
                GradientStop { position: 0; color: root.faded(root.shade_color) }
                GradientStop { position: 1; color: root.faded(root.bg_color) }
            }
        }
    }

    // The window's fill; its corner pixels stay clear.
    Item {
        visible: root.window
        x: root.window_x
        y: root.window_top
        width: root.window_width
        height: root.window_bottom - root.window_top

        Rectangle {
            x: root.window_edge
            width: parent.width - root.window_edge * 2
            height: parent.height
            color: root.faded(root.bg_color)
        }

        // The side strips beside the centre column; overlapping it would fill those pixels twice.
        Repeater {
            model: [0, 1]

            Rectangle {
                required property int modelData
                x: modelData === 0 ? 0 : parent.width - root.window_edge
                y: root.window_edge
                width: root.window_edge
                height: parent.height - root.window_edge * 2
                color: root.faded(root.bg_color)
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.dither_color.a > 0
        transform: mirror
        sourceComponent: Dither {
            // The slant keeps Dither's own slant edges (the same line as fill_span's, computed in another order), so slanted styles draw exactly as before.
            slant_left: root.cap_left ? root.cap_width : 0
            slant_right: root.cap_right ? root.cap_width : 0
            row_span: root.slanted ? null : root.fill_span
            color: root.faded(root.dither_color)
        }
    }

    Rectangle {
        id: body

        x: root.capsule ? root.capsule_inset : root.lug + (cap_left ? root.cap_width : 0)
        height: root.height
        width: Math.ceil(layout.implicitWidth) + root.pad * 2
        color: root.shaded || root.octagon || root.window || root.outlined || root.lualine && root.translucent ? "transparent" : root.faded(root.bg_color)

        // Translucent lualine: the island's colour goes only behind modules that draw no section fill of their own
        // (`lualine_fill`), since those fills over this one would show both.
        Repeater {
            model: root.lualine && root.translucent ? layout.children : []

            Rectangle {
                required property Item modelData
                visible: modelData.visible && !(modelData.item && modelData.item.lualine_fill)
                x: layout.x + modelData.x
                width: modelData.width
                height: body.height
                color: root.faded(root.bg_color)
            }
        }

        // A tick scale rising from the open edge.
        Loader {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: root.flipped ? parent.top : undefined
            anchors.bottom: root.flipped ? undefined : parent.bottom
            anchors.topMargin: root.border_width
            anchors.bottomMargin: root.border_width
            height: 5
            active: Style.bar_ticks.a > 0
            sourceComponent: TickScale {
                from_end: !root.flipped
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
            // A window's content centres on the window rather than the bar.
            y: root.capsule && !root.flipped ? root.capsule_inset : 0
            height: parent.height - (root.capsule ? root.capsule_inset : 0)
            spacing: root.lualine && !root.center ? 0 : Style.bar_module_gap
        }
    }

    // Caps overlap the body by 1px so fractional scaling (1.6 on the laptop) leaves no seam.
    Loader {
        width: root.cap_width + root.cap_overlap
        height: root.height
        active: root.cap_left && !root.capsule && !root.octagon && !root.window && !root.outlined
        transform: mirror
        sourceComponent: Shape {
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: root.faded(root.cap_left_fill.a > 0 ? root.cap_left_fill : root.shaded ? "transparent" : root.bg_color)
                PathPolyline {
                    path: {
                        const c = root.cap_width, h = root.height, o = root.cap_overlap;
                        if (!root.lualine) return [Qt.point(0, 0), Qt.point(c + o, 0), Qt.point(c + o, h), Qt.point(c, h), Qt.point(0, 0)];
                        if (root.center) return [Qt.point(c, 0), Qt.point(c + o, 0), Qt.point(c + o, h), Qt.point(0, h), Qt.point(c, 0)];
                        return [Qt.point(c, 0), Qt.point(c + o, 0), Qt.point(c + o, h), Qt.point(c, h), Qt.point(0, h / 2), Qt.point(c, 0)];
                    }
                }
            }
        }
    }

    Loader {
        x: root.width - root.cap_width - root.cap_overlap
        width: root.cap_width + root.cap_overlap
        height: root.height
        active: root.cap_right && !root.capsule && !root.octagon && !root.window && !root.outlined
        transform: mirror
        sourceComponent: Shape {
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: root.faded(root.cap_right_fill.a > 0 ? root.cap_right_fill : root.shaded ? "transparent" : root.bg_color)
                PathPolyline {
                    path: {
                        const c = root.cap_width, h = root.height, o = root.cap_overlap;
                        if (!root.lualine || root.center) return [Qt.point(0, 0), Qt.point(c + o, 0), Qt.point(o, h), Qt.point(0, h), Qt.point(0, 0)];
                        return [Qt.point(0, 0), Qt.point(o, 0), Qt.point(c + o, h / 2), Qt.point(o, h), Qt.point(0, h), Qt.point(0, 0)];
                    }
                }
            }
        }
    }

    // Static scanlines clipped to the slants; nothing animates them.
    Item {
        id: scanlines
        visible: root.scanline_color.a > 0
        x: root.window ? root.window_x + root.window_edge : 0
        y: root.window ? root.window_top + root.window_edge : 0
        width: root.window ? root.window_width - root.window_edge * 2 : root.width
        height: root.window ? root.window_bottom - root.window_top - root.window_edge * 2 : root.height
        transform: Scale {
            origin.y: scanlines.height / 2
            yScale: root.flipped ? -1 : 1
        }

        Repeater {
            model: root.scanline_color.a > 0 ? Math.ceil(scanlines.height / root.scanline_period) : 0

            Rectangle {
                required property int index
                readonly property real island_y: scanlines.y + y
                readonly property var span: root.fill_span(island_y, island_y + 1)

                x: span.x - scanlines.x
                y: index * root.scanline_period
                width: Math.max(0, span.w)
                height: 1
                color: root.faded(root.scanline_color)
            }
        }
    }

    // Traces the slants and bottom edge; the sides on the screen edge stay open.
    Loader {
        anchors.fill: parent
        active: root.border_width > 0 && !root.visor && !root.capsule && !root.octagon && !root.window && !root.outlined
        transform: mirror
        sourceComponent: Shape {
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
    }

    Loader {
        anchors.fill: parent
        active: root.inset_width > 0 && root.inset_color.a > 0 && !root.capsule && !root.octagon && !root.window && !root.outlined
        transform: mirror
        sourceComponent: Shape {
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

    // An outlined shape's rim, above the content like the octagon's, on every side but the screen's.
    Loader {
        anchors.fill: parent
        z: 2
        active: root.outlined && root.border_width > 0
        transform: mirror
        sourceComponent: Shape {
            preferredRendererType: root.shape === "pixel" ? Shape.GeometryRenderer : Shape.CurveRenderer

            ShapePath {
                strokeWidth: root.border_width
                strokeColor: root.border_color
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                joinStyle: ShapePath.MiterJoin
                PathPolyline {
                    path: Outlines.inset(root.outline_rim, root.border_width / 2).map(p => Qt.point(p[0], p[1]))
                }
            }
        }
    }

    // The window's border sits above the content, like the octagon's rim.
    Item {
        visible: root.window
        z: 2
        x: root.window_x
        y: root.window_top
        width: root.window_width
        height: root.window_bottom - root.window_top

        // Top, bottom, left and right edges as [x, y, width, height], each stopping short of the corners.
        Repeater {
            model: [[root.window_edge, 0, parent.width - root.window_edge * 2, root.window_edge], [root.window_edge, parent.height - root.window_edge, parent.width - root.window_edge * 2, root.window_edge], [0, root.window_edge, root.window_edge, parent.height - root.window_edge * 2], [parent.width - root.window_edge, root.window_edge, root.window_edge, parent.height - root.window_edge * 2]]

            Rectangle {
                required property var modelData
                x: modelData[0]
                y: modelData[1]
                width: modelData[2]
                height: modelData[3]
                color: root.border_color
            }
        }
    }
}
