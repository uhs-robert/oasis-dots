import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Hyprland
import qs.core
import qs.theme
import "BarLayout.js" as BarLayout
import "BarModules.js" as BarModules
// Keeps features/bar/modules in the Quickshell scan; modules load by URL and need BarModule.
import qs.features.bar.modules
import qs.features.media
import qs.features.bar.neovim as Neovim
import qs.features.weather
import qs.features.voice
import qs.features.popups

Item {
    id: root

    property string screen_name: ""
    // Only the focused monitor's bar shows the submap chip, as only its tab shows.
    readonly property bool focused: !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === root.screen_name
    property var rule: null
    // The screen frame's layout (FrameGeometry.frame_layout) while one is on: the side islands move in to the hole's
    // sides, where the frame's side zones put the side popups too.
    property var frame: null
    readonly property bool compact: BarSettings.compact_for(root.rule)
    readonly property int bar_height: BarSettings.height_for(root.rule)
    readonly property string position: BarSettings.position_for(root.rule)
    // A left or right bar is a column: the islands stack top, center, bottom and `bar_height` is its width.
    readonly property bool vertical: BarLayout.is_vertical(root.position)
    // Lualine's sections are horizontal only, so a side bar draws the style's islands instead.
    readonly property bool lualine: Style.bar_lualine && !root.vertical
    readonly property real center_width: center_island.body_item.width
    // The floating strip (Style.strip_floats): the plate sits strip_inset in from the screen edge and strip_side in from
    // each end of the bar (the sides of a top bar, the top and bottom of a column), so the bar window is strip_inset
    // thicker and the islands and plate shift toward the open edge by half of it.
    readonly property real strip_inset: Style.strip_floats ? Style.bar_strip_inset : 0
    readonly property real strip_side: Style.strip_floats ? Style.bar_strip_side : 0
    readonly property real strip_shift: (root.position === "bottom" || root.position === "right" ? -1 : 1) * root.strip_inset / 2
    // Where an island sits across the bar: centred in its window, moved by strip_shift.
    readonly property real cross_center: ((root.vertical ? root.width : root.height) - root.bar_height) / 2 + root.strip_shift
    // Lualine has no center island; its modules move into the right island's sections.
    readonly property bool has_center: !root.lualine && root.center_entries.length > 0

    // Resolves a bars.json module list into loadable entries, skipping unknown names.
    function build_entries(names) {
        const list = [];
        for (const raw of names || []) {
            const parsed = BarSettings.parse_module(raw);
            const spec = BarModules.find(parsed.base);
            if (!spec) {
                BarSettings.warn_unknown_module(parsed.base);
                continue;
            }
            list.push({ base: parsed.base, arg: parsed.arg, url: Qt.resolvedUrl("modules/" + spec.file) });
        }
        return list;
    }

    readonly property var left_entries: root.build_entries(root.rule ? root.rule.left : [])
    readonly property var center_entries: root.build_entries(root.rule ? root.rule.center : [])
    readonly property var right_entries: root.build_entries(root.rule ? root.rule.right : [])
    // Lualine's right-island section for a module; bars.json order is kept inside each, center modules first.
    function lualine_section(base) {
        return BarLayout.lualine_section(base);
    }

    readonly property bool lists_media: [root.left_entries, root.center_entries, root.right_entries].some(l => l.some(e => e.base === "media"))
    // Everything the lualine right island holds: center modules, then right ones.
    readonly property var lualine_entries: root.center_entries.concat(root.right_entries)
    readonly property var right_side: root.lualine ? root.lualine_entries : root.right_entries
    // Right-island entries in drawn order.
    readonly property var right_drawn: root.lualine ? ["x", "y", "z"].reduce((out, k) => out.concat(root.lualine_entries.filter(e => root.lualine_section(e.base) === k)), []) : root.right_entries

    // The start button draws the HyprVim mode chip on a lualine bar.
    // With no left modules the left island is hidden, so a frame has no chip and the dropdown tab shows instead.
    readonly property bool has_frame_chip: Style.screen_frame_on && !root.vertical && !root.lualine && root.left_entries.length > 0
    readonly property bool has_mode_chip: root.lualine && [root.left_entries, root.center_entries, root.right_entries].some(l => l.some(e => e.base === "start"))

    // The oasis horizon decorates the center island when it holds the clock; that clock makes room for it and lends it the time.
    readonly property bool clock_horizon: !root.vertical && Style.bar_clock_layout === "horizon" && root.center_entries.some(e => e.base === "clock")
    property var horizon_clock: null
    readonly property var module_props: ({ compact: root.compact, screen_name: root.screen_name, bar_height: root.bar_height })

    // Sets island/screen/stat properties a module declares, after the Loader instantiates it.
    function wire_module(item, entry, island) {
        item.compact = Qt.binding(() => root.compact);
        item.screen_name = Qt.binding(() => root.screen_name);
        item.bar_height = Qt.binding(() => root.bar_height);
        if (item.hasOwnProperty("vertical")) item.vertical = Qt.binding(() => root.vertical);
        if (entry.base === "clock" && island === center_island) {
            root.horizon_clock = item;
            item.horizon = Qt.binding(() => root.clock_horizon);
        }
        // Color first: setting island triggers the module's popup registration, which reads it.
        if (item.hasOwnProperty("island_color")) item.island_color = Qt.binding(() => island.bg_color);
        if (item.hasOwnProperty("island")) item.island = island.body_item;
        if (entry.arg && item.hasOwnProperty("stat")) item.stat = entry.arg;
    }

    // Lualine is one full-width statusline: section c's fill runs behind the islands.
    Rectangle {
        visible: root.lualine && !Style.islands_translucent
        width: root.width
        height: root.bar_height
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.bg_mantle
    }

    // Translucent, section c fills only between the islands, beside their arrow caps, so no fill stacks on it.
    Shape {
        visible: root.lualine && Style.islands_translucent
        width: root.width
        height: root.bar_height
        anchors.verticalCenter: parent.verticalCenter
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Style.island_fill(Theme.bg_mantle)
            PathPolyline {
                path: {
                    const h = root.bar_height, l = left_island.visible ? left_island.width : 0, lc = left_island.visible ? left_island.cap_width : 0;
                    const r = right_island.visible ? right_island.x : root.width, rc = right_island.visible ? right_island.cap_width : 0;
                    return [Qt.point(l - lc, 0), Qt.point(r + rc, 0), Qt.point(r, h / 2), Qt.point(r + rc, h), Qt.point(l - lc, h), Qt.point(l, h / 2), Qt.point(l - lc, 0)];
                }
            }
        }
    }

    Loader {
        x: root.vertical ? root.cross_center : root.strip_side
        y: root.vertical ? root.strip_side : root.cross_center
        width: root.vertical ? root.bar_height : root.width - root.strip_side * 2
        height: root.vertical ? root.height - root.strip_side * 2 : root.bar_height
        active: Style.strip_shape
        sourceComponent: StripBackground {
            edge: root.position
            length: root.vertical ? parent.height : parent.width
            thickness: root.bar_height
            frame: root.frame
            screen_name: root.screen_name
        }
    }

    Island {
        thickness: root.bar_height
        id: left_island
        cap_right_fill: root.lualine && LualineState.last_fill[root.screen_name] ? LualineState.last_fill[root.screen_name] : "transparent"
        x: root.vertical ? root.cross_center : root.frame ? root.frame.start : root.strip_side
        y: root.vertical ? root.strip_side : root.cross_center
        bg_color: Style.strip_shape ? Style.strip_color : Style.bar_side_bg
        border_width: Style.bar_border_width
        border_color: Style.bar_border_color
        scanline_color: Style.bar_scanline_color
        scanline_period: Style.scanline_period
        shade_color: Style.frame_shade
        shade_vertical: Style.shade_vertical
        dither_color: Qt.alpha(Style.dither, Math.min(1, Style.dither.a * 2.2))
        inset_gap: Style.bar_inset_gap
        inset_width: Style.bar_inset_width
        inset_color: Style.bar_inset_color
        capsule_inset: Style.bar_capsule
        sheen_color: Style.sheen
        edge: root.position
        cap_right: true
        visible: root.left_entries.length > 0

        onClicked: if (root.left_entries.some(e => e.base === "clock")) Popups.toggle("clock", left_island.body_item, left_island.bg_color, root.screen_name)

        Repeater {
            model: root.left_entries

            Loader {
                required property var modelData
                // Reads the module's own `shown`, not `visible`: a hidden Loader would report its child hidden too.
                visible: !item || item.shown === undefined || item.shown
                // Keeps the start button close to the workspace pills it launches into.
                Layout.rightMargin: modelData.base === "start" && !root.lualine && !root.vertical ? -8 : 0
                Layout.bottomMargin: modelData.base === "start" && !root.lualine && root.vertical ? -8 : 0
                Layout.alignment: root.vertical ? Qt.AlignHCenter : 0
                Component.onCompleted: setSource(modelData.url, root.module_props)
                onLoaded: root.wire_module(item, modelData, left_island)
            }
        }

        // With a frame the submap shows as the left island's last item instead of a dropdown tab (lualine styles keep their own mode chip). The left island holds few items, and the centered island does not move when it grows.
        Rectangle {
            visible: root.has_frame_chip && SubmapState.indicator_shown && root.focused
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            implicitWidth: chip_text.implicitWidth + 16
            implicitHeight: chip_text.implicitHeight + 6
            radius: Style.radius(4)
            color: SubmapState.bar_color

            Text {
                id: chip_text
                anchors.centerIn: parent
                text: SubmapState.submap_name.toUpperCase()
                color: Theme.bg_core
                font.family: Style.font_family
                font.pixelSize: Style.bar_font_size - 1
                font.bold: true
                font.letterSpacing: 1
            }
        }
    }

    // Lualine section c after the buffers: the focused app and a terminal's directory.
    Loader {
        id: segment_loader
        active: root.lualine && root.left_entries.length > 0
        x: left_island.width
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: Neovim.WindowSegment {
            screen_name: root.screen_name
            bar_height: root.bar_height
            max_width: Math.max(0, root.section_c - 8 - (lualine_cava.shown ? lualine_cava.width + 16 : 0))
        }
    }

    // Lualine section c: from the left island's end to the right island's cap.
    readonly property real section_c: (right_island.visible ? right_island.x : root.width) - (left_island.visible ? left_island.width : 0)

    // Lualine has no center island: cava plays at the end of section c, left of the right island's cap,
    // in whatever room the window segment's minimum leaves; under 48px it hides on this screen.
    Item {
        id: lualine_cava
        readonly property real room: root.section_c - (segment_loader.item ? segment_loader.item.min_width : 0) - 16
        readonly property bool shown: root.lualine && right_island.visible && MediaState.playing && PowerSource.on_ac && lualine_cava.room >= 48
        visible: lualine_cava.shown
        x: right_island.x - width - 8
        width: Math.max(0, Math.min(120, lualine_cava.room))
        height: root.bar_height
        anchors.verticalCenter: parent.verticalCenter

        onShownChanged: if (lualine_cava.shown) CavaState.register(lualine_cava); else CavaState.unregister(lualine_cava)
        Component.onCompleted: if (lualine_cava.shown) CavaState.register(lualine_cava)
        Component.onDestruction: CavaState.unregister(lualine_cava)

        CavaBars {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            height: parent.height - 6
            flipped: root.position === "bottom"
            active: lualine_cava.shown
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Popups.toggle("media", right_island.body_item, right_island.bg_color, root.screen_name)
        }
    }

    Island {
        thickness: root.bar_height
        id: center_island
        x: root.vertical ? root.cross_center : (root.width - width) / 2
        y: root.vertical ? (root.height - height) / 2 : root.cross_center
        bg_color: Style.strip_shape ? Style.strip_color : Style.bar_center_bg
        border_width: Style.bar_border_width
        border_color: Style.bar_border_color
        scanline_color: Style.bar_scanline_color
        scanline_period: Style.scanline_period
        shade_color: Style.frame_shade
        shade_vertical: Style.shade_vertical
        dither_color: Qt.alpha(Style.dither, Math.min(1, Style.dither.a * 2.2))
        inset_gap: Style.bar_inset_gap
        inset_width: Style.bar_inset_width
        inset_color: Style.bar_inset_color
        capsule_inset: Style.bar_capsule
        sheen_color: Style.sheen
        edge: root.position
        cap_left: true
        cap_right: true
        tab_joined: (SubmapState.indicator_shown && !root.has_frame_chip && !root.has_mode_chip) || VoxSessionState.active
        visible: root.has_center

        onClicked: if (root.center_entries.some(e => e.base === "clock")) Popups.toggle("clock", center_island.body_item, center_island.bg_color, root.screen_name)

        Repeater {
            model: root.has_center ? root.center_entries : []

            Loader {
                required property var modelData
                // Reads the module's own `shown`, not `visible`: a hidden Loader would report its child hidden too.
                visible: !item || item.shown === undefined || item.shown
                Layout.alignment: root.vertical ? Qt.AlignHCenter : 0
                Component.onCompleted: setSource(modelData.url, root.module_props)
                onLoaded: root.wire_module(item, modelData, center_island)
            }
        }
    }

    Loader {
        parent: center_island.body_item
        anchors.fill: parent
        z: -1
        active: root.clock_horizon
        sourceComponent: Horizon {
            date: root.horizon_clock ? root.horizon_clock.date : new Date()
        }
    }

    CavaBars {
        id: island_cava
        parent: center_island.body_item
        // Outside lualine every bar keeps cava running while media plays, drawn or not: the media popup's strip reads the same feed.
        readonly property bool viewing: !Style.bar_lualine
        onViewingChanged: if (island_cava.viewing) CavaState.register(island_cava); else CavaState.unregister(island_cava)
        Component.onCompleted: if (island_cava.viewing) CavaState.register(island_cava)
        Component.onDestruction: CavaState.unregister(island_cava)
        anchors.left: parent.left
        anchors.right: parent.right
        // Sits on the island's open edge: the bottom one, or the top one under a bottom bar, clear of its underline.
        readonly property real open_edge_margin: Style.strip_shape ? root.strip_open_edge_margin : center_island.capsule ? center_island.border_width + 1 : center_island.window ? center_island.height - center_island.window_bottom + center_island.window_edge : center_island.shape === "underline" ? center_island.stroke_width : center_island.filled && center_island.inset_color.a > 0 ? center_island.inset_gap + center_island.inset_width : 0
        anchors.top: center_island.flipped ? parent.top : undefined
        anchors.bottom: center_island.flipped ? undefined : parent.bottom
        anchors.leftMargin: center_island.capsule ? center_island.capsule_radius : 6
        anchors.rightMargin: center_island.capsule ? center_island.capsule_radius : 6
        anchors.topMargin: open_edge_margin
        anchors.bottomMargin: open_edge_margin
        flipped: center_island.flipped
        active: MediaState.playing && root.has_center && !root.vertical
    }

    Island {
        thickness: root.bar_height
        id: right_island
        x: root.vertical ? root.cross_center : root.width - width - (root.frame ? root.frame.end : root.strip_side)
        y: root.vertical ? root.height - height - root.strip_side : root.cross_center
        // Lualine x shares section c's mantle, so the idle cap melts into the bar like lualine's c|x boundary.
        bg_color: root.lualine ? Theme.bg_mantle : Style.strip_shape ? Style.strip_color : Style.bar_side_bg
        border_width: Style.bar_border_width
        border_color: Style.bar_border_color
        scanline_color: Style.bar_scanline_color
        scanline_period: Style.scanline_period
        shade_color: Style.frame_shade
        shade_vertical: Style.shade_vertical
        dither_color: Qt.alpha(Style.dither, Math.min(1, Style.dither.a * 2.2))
        inset_gap: Style.bar_inset_gap
        inset_width: Style.bar_inset_width
        inset_color: Style.bar_inset_color
        capsule_inset: Style.bar_capsule
        sheen_color: Style.sheen
        edge: root.position
        cap_left_fill: root.lualine && LualineState.right_first_fill[root.screen_name] ? LualineState.right_first_fill[root.screen_name] : "transparent"
        cap_left: true
        visible: root.right_side.length > 0

        onClicked: if (!root.lualine && root.right_entries.some(e => e.base === "clock")) Popups.toggle("clock", right_island.body_item, right_island.bg_color, root.screen_name)

        Repeater {
            model: root.lualine ? [] : root.right_entries

            Loader {
                required property var modelData
                // Reads the module's own `shown`, not `visible`: a hidden Loader would report its child hidden too.
                visible: !item || item.shown === undefined || item.shown
                Layout.alignment: root.vertical ? Qt.AlignHCenter : 0
                Component.onCompleted: setSource(modelData.url, root.module_props)
                onLoaded: root.wire_module(item, modelData, right_island)
            }
        }

        // Lualine x, y and z sections (lualine_section).
        Loader {
            active: root.lualine
            visible: active
            Layout.fillHeight: true
            sourceComponent: Row {
                readonly property var wire: (item, entry) => root.wire_module(item, entry, right_island)
                // The sections draw their own fills, so a translucent island leaves its colour out from behind them.
                readonly property bool lualine_fill: true

                Neovim.LualineSection {
                    id: x_section
                    height: right_island.height
                    entries: root.lualine_entries.filter(e => root.lualine_section(e.base) === "x")
                    wire: parent.wire
                    module_props: root.module_props
                    fill: Theme.bg_mantle
                    screen_name: root.screen_name
                }

                Neovim.LualineSection {
                    id: y_section
                    height: right_island.height
                    entries: root.lualine_entries.filter(e => root.lualine_section(e.base) === "y")
                    wire: parent.wire
                    module_props: root.module_props
                    fill: Theme.ui_visual_bg
                    hover_fill: Qt.tint(Theme.ui_visual_bg, Qt.alpha(Theme.theme_primary, 0.3))
                    lead_bg: x_section.shown ? x_section.end_fill : "transparent"
                    separators: false
                }

                Neovim.LualineSection {
                    height: right_island.height
                    entries: root.lualine_entries.filter(e => root.lualine_section(e.base) === "z")
                    wire: parent.wire
                    module_props: root.module_props
                    fill: SubmapState.bar_color
                    accent: true
                    // The mode chip's hover tint.
                    hover_fill: Qt.tint(fill, Qt.alpha(Theme.fg_strong, 0.15))
                    separators: false
                    lead_bg: y_section.shown ? y_section.end_fill : x_section.shown ? x_section.end_fill : "transparent"
                }
            }
        }
    }

    // Clear of the strip's rim and, where the style has one, its inset line.
    readonly property real strip_open_edge_margin: Math.max(Style.bar_border_width + 1, Style.bar_inset_width > 0 && Style.bar_inset_color.a > 0 ? Style.bar_inset_gap + Style.bar_inset_width : 0)

    // The clock has no module item of its own, so its popup anchor follows whichever island lists it.
    function sync_clock_anchor() {
        const has_clock = entries => entries.some(e => e.base === "clock");
        const island = has_clock(root.left_entries) ? left_island : root.has_center && has_clock(root.center_entries) ? center_island : has_clock(root.right_side) ? right_island : null;
        for (const i of [left_island, center_island, right_island]) Popups.unregister("clock", root.screen_name, i.body_item);
        if (island) Popups.register_default("clock", island.body_item, island.bg_color, root.screen_name);
        // Keybind power confirms and the confirm card drop from the center island, else wherever the clock sits.
        const power_island = root.has_center ? center_island : island || right_island;
        Popups.register_default("power", power_island.body_item, power_island.bg_color, root.screen_name);
        Popups.register_default("confirm", power_island.body_item, power_island.bg_color, root.screen_name);
        // Settings drops from the screen's center even under lualine, whose center island is hidden but still centered.
        const settings_island = root.has_center || root.lualine ? center_island : power_island;
        Popups.register_default("settings", settings_island.body_item, settings_island.bg_color, root.screen_name);
        // Without a media module in bars.json, the media popup drops from the center island.
        Popups.unregister("media", root.screen_name, center_island.body_item);
        Popups.unregister("media", root.screen_name, right_island.body_item);
        if (root.has_center && !root.lists_media) Popups.register_default("media", center_island.body_item, center_island.bg_color, root.screen_name);
        // Lualine has no center island, so the media popup drops from the right one.
        else if (root.lualine && !root.lists_media) Popups.register_default("media", right_island.body_item, right_island.bg_color, root.screen_name);
    }

    // Popup names in bar order for Ctrl+H/L walking.
    function popup_names(entries) {
        return entries.filter(e => BarModules.has_popup(e.base)).map(e => e.base);
    }

    function sync_popup_order() {
        const center_names = root.has_center ? root.popup_names(root.center_entries) : [];
        if ((root.has_center || root.lualine) && !root.lists_media) center_names.push("media");
        const right_names = root.popup_names(root.right_drawn);
        // Settings drops from the center; with no center it drops from the right end, so it walks last.
        const has_center_slot = root.has_center || root.lualine;
        if (has_center_slot) center_names.push("settings");
        else right_names.push("settings");
        Popups.register_order(root.screen_name, root.popup_names(root.left_entries).concat(center_names, right_names));
    }

    function sync_popups() {
        sync_clock_anchor();
        sync_popup_order();
    }

    onLeft_entriesChanged: sync_popups()
    onCenter_entriesChanged: sync_popups()
    onHas_centerChanged: sync_popups()
    onRight_drawnChanged: sync_popups()
    Component.onCompleted: sync_popups()
    Component.onDestruction: Popups.unregister_screen(root.screen_name)
}
