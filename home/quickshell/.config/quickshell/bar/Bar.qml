// home/quickshell/.config/quickshell/bar/Bar.qml
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"
import "modules"
import "../components/oasis" as Oasis
import "../components/neovim" as Neovim

Item {
    id: root

    property string screen_name: ""
    property var rule: null
    readonly property bool compact: BarConfig.compact_for(root.rule, root.screen_name)
    readonly property int bar_height: BarConfig.height_for(root.rule)
    readonly property real center_width: center_island.body_item.width
    // Lualine has no center island; its modules move into the right island's sections.
    readonly property bool has_center: !Style.bar_lualine && root.center_entries.length > 0

    readonly property var module_map: ({
        start: start_component,
        workspaces: workspaces_component,
        clock: clock_component,
        tray: tray_component,
        volume: volume_component,
        battery: battery_component,
        bluetooth: bluetooth_component,
        system: system_component,
        network: network_component,
        weather: weather_component,
        keeptabs: keeptabs_component,
        updates: updates_component,
        voxtype: voxtype_component,
        recording: recording_component,
        notifications: notifications_component,
        media: media_component
    })

    // Resolves a bars.json module list into loadable entries, skipping unknown names.
    function build_entries(names) {
        const list = [];
        for (const raw of names || []) {
            const parsed = BarConfig.parse_module(raw);
            const component = root.module_map[parsed.base];
            if (!component) {
                BarConfig.warn_unknown_module(parsed.base);
                continue;
            }
            list.push({ base: parsed.base, arg: parsed.arg, component: component });
        }
        return list;
    }

    readonly property var left_entries: root.build_entries(root.rule ? root.rule.left : [])
    readonly property var center_entries: root.build_entries(root.rule ? root.rule.center : [])
    readonly property var right_entries: root.build_entries(root.rule ? root.rule.right : [])
    // Lualine's right-island section for a module; bars.json order is kept inside each, center modules first.
    function lualine_section(base) {
        return base === "notifications" || base === "clock" ? "z" : ["network", "bluetooth", "recording", "voxtype"].indexOf(base) >= 0 ? "y" : "x";
    }

    readonly property bool lists_media: [root.left_entries, root.center_entries, root.right_entries].some(l => l.some(e => e.base === "media"))
    // Everything the lualine right island holds: center modules, then right ones.
    readonly property var lualine_entries: root.center_entries.concat(root.right_entries)
    readonly property var right_side: Style.bar_lualine ? root.lualine_entries : root.right_entries
    // Right-island entries in drawn order.
    readonly property var right_drawn: Style.bar_lualine ? ["x", "y", "z"].reduce((out, k) => out.concat(root.lualine_entries.filter(e => root.lualine_section(e.base) === k)), []) : root.right_entries

    // The start button draws the HyprVim mode chip on a lualine bar.
    readonly property bool has_mode_chip: Style.bar_lualine && [root.left_entries, root.center_entries, root.right_entries].some(l => l.some(e => e.base === "start"))

    // The oasis horizon decorates the center island when it holds the clock; that clock makes room for it and lends it the time.
    readonly property bool clock_horizon: Style.bar_clock_layout === "horizon" && root.center_entries.some(e => e.base === "clock")
    property var horizon_clock: null

    // Sets island/screen/stat properties a module declares, after the Loader instantiates it.
    function wire_module(item, entry, island) {
        if (entry.base === "clock" && island === center_island) {
            root.horizon_clock = item;
            item.horizon = Qt.binding(() => root.clock_horizon);
        }
        // Color first: setting island triggers the module's popup registration, which reads it.
        if (item.hasOwnProperty("island_color")) item.island_color = Qt.binding(() => island.bg_color);
        if (item.hasOwnProperty("island")) item.island = island.body_item;
        if (entry.arg && item.hasOwnProperty("stat")) item.stat = entry.arg;
    }

    Component { id: start_component; StartButton { compact: root.compact; screen_name: root.screen_name; bar_height: root.bar_height } }
    Component { id: workspaces_component; Workspaces { compact: root.compact; screen_name: root.screen_name; bar_height: root.bar_height } }
    Component { id: clock_component; Clock { compact: root.compact; screen_name: root.screen_name } }
    Component { id: tray_component; Tray { compact: root.compact; screen_name: root.screen_name } }
    Component { id: volume_component; Volume { compact: root.compact; screen_name: root.screen_name } }
    Component { id: battery_component; Battery { compact: root.compact; screen_name: root.screen_name } }
    Component { id: bluetooth_component; Bluetooth { compact: root.compact; screen_name: root.screen_name } }
    Component { id: system_component; System { compact: root.compact; screen_name: root.screen_name } }
    Component { id: network_component; Network { screen_name: root.screen_name } }
    Component { id: weather_component; Weather { compact: root.compact; screen_name: root.screen_name } }
    Component { id: keeptabs_component; Keeptabs { compact: root.compact; screen_name: root.screen_name } }
    Component { id: updates_component; Updates { compact: root.compact; screen_name: root.screen_name } }
    Component { id: voxtype_component; Voxtype { compact: root.compact } }
    Component { id: recording_component; Recording { compact: root.compact } }
    Component { id: notifications_component; Notifications { compact: root.compact; screen_name: root.screen_name } }
    Component { id: media_component; Media { compact: root.compact; screen_name: root.screen_name } }

    // Lualine is one full-width statusline: section c's fill runs behind the islands.
    Rectangle {
        visible: Style.bar_lualine
        width: root.width
        height: root.bar_height
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.bg_mantle
    }

    Island {
        height: root.bar_height
        id: left_island
        cap_right_fill: Style.bar_lualine && LualineState.last_fill[root.screen_name] ? LualineState.last_fill[root.screen_name] : "transparent"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Style.bar_side_bg
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
        visor: Style.frame_visor
        capsule_inset: Style.bar_capsule
        sheen_color: Style.sheen
        cap_right: true
        visible: root.left_entries.length > 0

        onClicked: if (root.left_entries.some(e => e.base === "clock")) Popups.toggle("clock", left_island.body_item, left_island.bg_color, root.screen_name)

        Repeater {
            model: root.left_entries

            Loader {
                required property var modelData
                sourceComponent: modelData.component
                // Reads the module's own `shown`, not `visible`: a hidden Loader would report its child hidden too.
                visible: !item || item.shown === undefined || item.shown
                // Keeps the start button close to the workspace pills it launches into.
                Layout.rightMargin: modelData.base === "start" && !Style.bar_lualine ? -8 : 0
                onLoaded: root.wire_module(item, modelData, left_island)
            }
        }
    }

    // Lualine section c after the buffers: the focused app and a terminal's directory.
    Loader {
        id: segment_loader
        active: Style.bar_lualine && root.left_entries.length > 0
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
        readonly property bool shown: Style.bar_lualine && right_island.visible && MediaState.playing && Power.on_ac && lualine_cava.room >= 48
        visible: lualine_cava.shown
        x: right_island.x - width - 8
        width: Math.max(0, Math.min(120, lualine_cava.room))
        height: root.bar_height
        anchors.verticalCenter: parent.verticalCenter

        onShownChanged: CavaState.lualine_viewers += lualine_cava.shown ? 1 : -1
        Component.onCompleted: if (lualine_cava.shown) CavaState.lualine_viewers += 1
        Component.onDestruction: if (lualine_cava.shown) CavaState.lualine_viewers -= 1

        CavaBars {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            height: parent.height - 6
            active: lualine_cava.shown
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Popups.toggle("media", right_island.body_item, right_island.bg_color, root.screen_name)
        }
    }

    Island {
        height: root.bar_height
        id: center_island
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Style.bar_center_bg
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
        visor: Style.frame_visor
        capsule_inset: Style.bar_capsule
        sheen_color: Style.sheen
        cap_left: true
        cap_right: true
        tab_joined: SubmapState.active && !root.has_mode_chip
        wave_shown: MediaState.playing
        visible: root.has_center

        onClicked: if (root.center_entries.some(e => e.base === "clock")) Popups.toggle("clock", center_island.body_item, center_island.bg_color, root.screen_name)

        Repeater {
            model: root.has_center ? root.center_entries : []

            Loader {
                required property var modelData
                sourceComponent: modelData.component
                // Reads the module's own `shown`, not `visible`: a hidden Loader would report its child hidden too.
                visible: !item || item.shown === undefined || item.shown
                onLoaded: root.wire_module(item, modelData, center_island)
            }
        }
    }

    Loader {
        parent: center_island.body_item
        anchors.fill: parent
        z: -1
        active: root.clock_horizon
        sourceComponent: Oasis.Horizon {
            date: root.horizon_clock ? root.horizon_clock.date : new Date()
        }
    }

    CavaBars {
        parent: center_island.body_item
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: center_island.capsule ? center_island.capsule_radius : 6
        anchors.rightMargin: center_island.capsule ? center_island.capsule_radius : 6
        anchors.bottomMargin: center_island.capsule ? center_island.border_width + 1 : center_island.inset_color.a > 0 ? center_island.inset_gap + center_island.inset_width : 0
        active: MediaState.playing && root.has_center
    }

    Island {
        height: root.bar_height
        id: right_island
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        // Lualine x shares section c's mantle, so the idle cap melts into the bar like lualine's c|x boundary.
        bg_color: Style.bar_lualine ? Theme.bg_mantle : Style.bar_side_bg
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
        visor: Style.frame_visor
        capsule_inset: Style.bar_capsule
        sheen_color: Style.sheen
        cap_left_fill: Style.bar_lualine && LualineState.right_first_fill[root.screen_name] ? LualineState.right_first_fill[root.screen_name] : "transparent"
        cap_left: true
        visible: root.right_entries.length > 0

        onClicked: if (!Style.bar_lualine && root.right_entries.some(e => e.base === "clock")) Popups.toggle("clock", right_island.body_item, right_island.bg_color, root.screen_name)

        Repeater {
            model: Style.bar_lualine ? [] : root.right_entries

            Loader {
                required property var modelData
                sourceComponent: modelData.component
                // Reads the module's own `shown`, not `visible`: a hidden Loader would report its child hidden too.
                visible: !item || item.shown === undefined || item.shown
                onLoaded: root.wire_module(item, modelData, right_island)
            }
        }

        // Lualine x, y and z sections (lualine_section).
        Loader {
            active: Style.bar_lualine
            visible: active
            Layout.fillHeight: true
            sourceComponent: Row {
                readonly property var wire: (item, entry) => root.wire_module(item, entry, right_island)

                Neovim.LualineSection {
                    id: x_section
                    height: right_island.height
                    entries: root.lualine_entries.filter(e => root.lualine_section(e.base) === "x")
                    wire: parent.wire
                    fill: Theme.bg_mantle
                    screen_name: root.screen_name
                }

                Neovim.LualineSection {
                    id: y_section
                    height: right_island.height
                    entries: root.lualine_entries.filter(e => root.lualine_section(e.base) === "y")
                    wire: parent.wire
                    fill: Theme.ui_visual_bg
                    hover_fill: Qt.tint(Theme.ui_visual_bg, Qt.alpha(Theme.theme_primary, 0.3))
                    lead_bg: x_section.shown ? x_section.end_fill : "transparent"
                    separators: false
                }

                Neovim.LualineSection {
                    height: right_island.height
                    entries: root.lualine_entries.filter(e => root.lualine_section(e.base) === "z")
                    wire: parent.wire
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

    // The clock has no module item of its own, so its popup anchor follows whichever island lists it.
    function sync_clock_anchor() {
        const has_clock = entries => entries.some(e => e.base === "clock");
        const island = has_clock(root.left_entries) ? left_island : root.has_center && has_clock(root.center_entries) ? center_island : has_clock(root.right_side) ? right_island : null;
        for (const i of [left_island, center_island, right_island]) Popups.unregister("clock", root.screen_name, i.body_item);
        if (island) Popups.register_default("clock", island.body_item, island.bg_color, root.screen_name);
        // Without a media module in bars.json, the media popup drops from the center island.
        Popups.unregister("media", root.screen_name, center_island.body_item);
        Popups.unregister("media", root.screen_name, right_island.body_item);
        if (root.has_center && !root.lists_media) Popups.register_default("media", center_island.body_item, center_island.bg_color, root.screen_name);
        // Lualine has no center island, so the media popup drops from the right one.
        else if (Style.bar_lualine && !root.lists_media) Popups.register_default("media", right_island.body_item, right_island.bg_color, root.screen_name);
    }

    // Popup names in bar order for Ctrl+H/L walking; workspaces, voxtype and recording have no popup.
    function popup_names(entries) {
        return entries.filter(e => ["workspaces", "voxtype", "recording"].indexOf(e.base) < 0).map(e => e.base);
    }

    function sync_popup_order() {
        const center_names = root.has_center ? root.popup_names(root.center_entries) : [];
        if ((root.has_center || Style.bar_lualine) && !root.lists_media) center_names.push("media");
        Popups.register_order(root.screen_name, root.popup_names(root.left_entries).concat(center_names, root.popup_names(root.right_drawn)));
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
