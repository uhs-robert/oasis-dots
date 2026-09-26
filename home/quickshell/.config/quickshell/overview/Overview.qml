// home/quickshell/.config/quickshell/overview/Overview.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../theme"
import "../services"
import "Layout.js" as Layout
import "../picker/Fuzzy.js" as Fuzzy

// Every monitor's workspaces in one full-screen view on the focused monitor: pick, focus and move windows by key.
PanelWindow {
    id: root

    property bool wanted: false
    property string held_screen_name: ""
    // The filmstrip view instead of the mini-map, until the overview closes.
    property bool filmstrip: false
    property real reveal: 0

    property string selected_key: ""
    property string selected_address: ""
    // Carried window addresses, and the marks they came from so Esc can put them back.
    property var picked: []
    property bool picked_from_marks: false
    property var marks: []
    property bool typing: false
    property bool help_open: false
    property string query: ""

    readonly property var model: root.visible ? root.build(Hyprland.monitors.values, Hyprland.workspaces.values, Hyprland.toplevels.values) : ({ groups: [], tiles: [] })
    readonly property var groups: root.model.groups
    readonly property var tiles: root.model.tiles
    readonly property var tile_index_of: {
        const out = {};
        root.tiles.forEach((t, i) => out[t.key] = i);
        return out;
    }

    // Tile delegates live per workspace key; closed windows drop out of marks and the carried set.
    onTilesChanged: {
        Layout.sync_keys(tile_slots, root.tiles.map(t => t.key));
        const known = {};
        for (const t of root.tiles) for (const w of t.windows) known[w.address] = true;
        if (root.tiles.length === 0) return;
        if (root.marks.some(a => !known[a])) root.marks = root.marks.filter(a => known[a]);
        if (root.picked.some(a => !known[a])) root.picked = root.picked.filter(a => known[a]);
    }

    ListModel {
        id: tile_slots
    }
    readonly property int selected_index: Math.max(0, root.tiles.findIndex(t => t.key === root.selected_key))
    readonly property var selected_tile: root.tiles[root.selected_index] || null
    readonly property var tab_order: root.selected_tile ? root.reading_order(root.selected_tile.windows) : []
    readonly property string current_address: root.tab_order.some(w => w.address === root.selected_address) ? root.selected_address : root.tab_order.length > 0 ? root.tab_order[0].address : ""
    readonly property bool carrying: root.picked.length > 0
    readonly property var picked_set: root.to_set(root.picked)
    readonly property var picked_toplevel: root.carrying ? WindowState.find(root.picked[0]) : null
    readonly property var mark_numbers: {
        const out = {};
        root.marks.forEach((a, i) => out[a] = i + 1);
        return out;
    }
    // One window carried inside its own workspace, selection on another window there: m/Enter swaps them.
    readonly property string swap_address: root.picked.length === 1 && !!root.selected_tile && root.selected_tile.windows.some(w => w.address === root.picked[0]) && root.current_address !== root.picked[0] ? root.current_address : ""
    readonly property bool can_drop: root.carrying && root.swap_address === "" && !!root.selected_tile && root.picked.some(a => !root.selected_tile.windows.some(w => w.address === a))
    readonly property var nav_order: Layout.flat(Layout.flat(Layout.bands(root.groups)).map(g => root.groups[g].tiles))
    readonly property var matches: root.query === "" ? null : root.match_set(root.query)
    readonly property int match_count: root.matches ? Object.keys(root.matches).length : 0

    readonly property var metrics: ({
        gap: Style.px(10),
        pad: Style.px(10),
        label: Style.fs(-3) + Style.px(12),
        group_gap: Style.px(22),
        strip: Style.px(150)
    })
    readonly property var layout: Layout.compute(root.filmstrip, root.groups, root.tiles, frame.body.width, frame.body.height, root.metrics, root.selected_index)
    readonly property bool animate_moves: root.filmstrip && Power.on_ac && root.reveal === 1

    screen: Quickshell.screens.find(s => s.name === root.held_screen_name) || null
    visible: false
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "overview"

        function open(): string {
            root.show_overview();
            return "ok";
        }

        function close(): string {
            root.hide_overview();
            return "ok";
        }

        function toggle(): string {
            if (root.wanted) root.hide_overview();
            else root.show_overview();
            return "ok";
        }
    }

    function show_overview() {
        if (root.wanted) return;
        Popups.close();
        const mon = Hyprland.focusedMonitor;
        const target = (mon && Quickshell.screens.find(s => s.name === mon.name)) || Quickshell.screens[0];
        root.held_screen_name = target ? target.name : "";
        root.refresh();
        root.filmstrip = false;
        root.picked = [];
        root.marks = [];
        root.help_open = false;
        root.clear_filter();
        const ws = Hyprland.focusedWorkspace;
        root.selected_key = ws ? "ws:" + ws.id : "";
        root.selected_address = WindowState.active_address;
        root.wanted = true;
        root.visible = true;
        reveal_anim.stop();
        if (Power.on_ac) {
            reveal_anim.to = 1;
            reveal_anim.start();
        } else {
            root.reveal = 1;
        }
        keys.forceActiveFocus();
    }

    function hide_overview() {
        if (!root.wanted) return;
        root.wanted = false;
        root.typing = false;
        root.help_open = false;
        reveal_anim.stop();
        if (Power.on_ac && root.visible) {
            reveal_anim.to = 0;
            reveal_anim.start();
        } else {
            root.reveal = 0;
            root.visible = false;
        }
    }

    function refresh() {
        WindowState.refresh();
        Hyprland.refreshMonitors();
    }

    function reading_order(windows) {
        return windows.slice().sort((a, b) => a.ry - b.ry || a.rx - b.rx);
    }

    function logical_size(m) {
        const ipc = m.lastIpcObject || {};
        const s = m.scale > 0 ? m.scale : 1;
        const turned = (ipc.transform || 0) % 2 === 1;
        return { w: (turned ? m.height : m.width) / s, h: (turned ? m.width : m.height) / s };
    }

    function window_entry(t, g) {
        const ipc = t.lastIpcObject || {};
        const at = ipc.at || [g.x, g.y];
        const size = ipc.size || [g.w, g.h];
        const full = (ipc.fullscreen || 0) > 0;
        const clamp = v => Math.max(0, Math.min(1, v));
        const rx = full ? 0 : clamp((at[0] - g.x) / g.w);
        const ry = full ? 0 : clamp((at[1] - g.y) / g.h);
        return {
            address: t.address,
            toplevel: t,
            rx: rx,
            ry: ry,
            rw: full ? 1 : Math.min(1 - rx, size[0] / g.w),
            rh: full ? 1 : Math.min(1 - ry, size[1] / g.h),
            floating: ipc.floating === true,
            label: WindowState.short_class(t),
            title: t.title || "",
            cls: WindowState.class_of(t)
        };
    }

    // Monitors with their workspaces in id order, then a fresh workspace slot to drop windows on.
    function build(monitors, workspaces, toplevels) {
        const groups = [];
        const tiles = [];
        const used = {};
        for (const w of workspaces) used[w.id] = true;
        for (const m of monitors) {
            const size = root.logical_size(m);
            const g = { name: m.name, monitor: m, x: m.x, y: m.y, w: size.w, h: size.h, tiles: [], focused: m.focused };
            const list = workspaces.filter(w => w.monitor === m && !(w.name || "").startsWith("special:")).sort((a, b) => a.id - b.id);
            for (const w of list) {
                const wins = toplevels.filter(t => t.workspace === w).map(t => root.window_entry(t, g));
                wins.sort((a, b) => (a.floating ? 1 : 0) - (b.floating ? 1 : 0));
                g.tiles.push(tiles.length);
                tiles.push({ key: "ws:" + w.id, id: w.id, name: w.name || String(w.id), ws: w, group: groups.length, is_new: false, focused: w.focused, shown_on_monitor: m.activeWorkspace === w, windows: wins });
            }
            let next = Math.max(0, ...list.map(w => w.id)) + 1;
            while (used[next]) next++;
            used[next] = true;
            g.tiles.push(tiles.length);
            tiles.push({ key: "new:" + m.name, id: next, name: String(next), ws: null, group: groups.length, is_new: true, focused: false, shown_on_monitor: false, windows: [] });
            groups.push(g);
        }
        return { groups: groups, tiles: tiles };
    }

    function match_set(query) {
        const terms = Fuzzy.terms_of(query);
        const set = {};
        if (terms.length === 0) return set;
        for (const tile of root.tiles) {
            for (const w of tile.windows) {
                if (Fuzzy.score_item(terms, { label: w.label, description: w.title, keywords: [w.cls] })) set[w.address] = true;
            }
        }
        return set;
    }

    // Matching windows in the order hjkl walks the tiles, each tile in reading order.
    function match_list() {
        if (!root.matches) return [];
        const out = [];
        for (const i of root.nav_order) {
            for (const w of root.reading_order(root.tiles[i].windows)) {
                if (root.matches[w.address]) out.push({ tile: i, address: w.address });
            }
        }
        return out;
    }

    function step_match(delta) {
        const list = root.match_list();
        if (list.length === 0) return;
        const at = list.findIndex(m => m.tile === root.selected_index && m.address === root.current_address);
        const next = at < 0 ? (delta > 0 ? 0 : list.length - 1) : (at + delta + list.length) % list.length;
        root.select(list[next].tile, list[next].address);
    }

    function select(index, address) {
        const tile = root.tiles[index];
        if (!tile) return;
        root.selected_key = tile.key;
        if (address !== undefined) {
            root.selected_address = address;
        } else {
            const order = root.reading_order(tile.windows);
            const active = order.find(w => w.address === WindowState.active_address);
            root.selected_address = active ? active.address : order.length > 0 ? order[0].address : "";
        }
    }

    function move(dx, dy) {
        const from = root.selected_index;
        let to = -1;
        if (root.filmstrip) {
            const order = root.layout.order;
            if (dx !== 0) {
                const at = order.indexOf(from);
                to = at >= 0 ? order[at + dx] : -1;
            } else {
                const band_order = Layout.flat(Layout.bands(root.groups));
                const tile = root.tiles[from];
                const g = band_order.indexOf(tile.group) + dy;
                if (g >= 0 && g < band_order.length) {
                    const target = root.groups[band_order[g]].tiles;
                    to = target[Math.min(root.groups[tile.group].tiles.indexOf(from), target.length - 1)];
                }
            }
        } else {
            to = Layout.neighbor(root.layout.tile_rects, from, dx, dy);
        }
        if (to !== undefined && to >= 0) root.select(to);
    }

    function cycle_window(delta) {
        const order = root.tab_order;
        if (order.length === 0) return;
        const at = order.findIndex(w => w.address === root.current_address);
        root.selected_address = order[(at + delta + order.length) % order.length].address;
    }

    function jump(id) {
        const i = root.tiles.findIndex(t => !t.is_new && t.id === id);
        if (i >= 0) root.select(i);
    }

    function focus_workspace(tile) {
        if (tile.is_new) {
            const g = root.groups[tile.group];
            Hyprland.dispatch("hl.dsp.focus({ monitor = '" + g.name + "' })");
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + tile.id + " })");
            return;
        }
        const target = WindowState.workspace_selector(tile.id);
        if (target !== "") Hyprland.dispatch("hl.dsp.focus({ workspace = " + target + " })");
    }

    function activate() {
        const tile = root.selected_tile;
        if (!tile) return;
        if (root.current_address !== "") WindowState.focus(root.current_address);
        else root.focus_workspace(tile);
        root.hide_overview();
    }

    function to_set(list) {
        const out = {};
        for (const a of list) out[a] = true;
        return out;
    }

    function alive(list) {
        return list.filter(a => WindowState.find(a) !== null);
    }

    function toggle_mark() {
        const a = root.current_address;
        if (a === "") return;
        root.marks = root.marks.indexOf(a) >= 0 ? root.marks.filter(m => m !== a) : root.marks.concat([a]);
    }

    // Marks every window in the selected workspace, or unmarks them all when they already are.
    function toggle_mark_all() {
        const here = root.tab_order.map(w => w.address);
        if (here.length === 0) return;
        const all = here.every(a => root.marks.indexOf(a) >= 0);
        root.marks = all ? root.marks.filter(m => here.indexOf(m) < 0) : root.marks.concat(here.filter(a => root.marks.indexOf(a) < 0));
    }

    function pick() {
        const marked = root.alive(root.marks);
        if (marked.length > 0) {
            root.picked = marked;
            root.picked_from_marks = true;
            root.marks = [];
        } else if (root.current_address !== "") {
            root.picked = [root.current_address];
            root.picked_from_marks = false;
        }
    }

    function cancel_pick() {
        if (root.picked_from_marks) root.marks = root.alive(root.picked);
        root.picked = [];
    }

    // Swaps inside a workspace, else moves every carried window there without following; a fresh slot is then sent to its monitor.
    function drop() {
        const tile = root.selected_tile;
        const carried = root.alive(root.picked);
        const swap_with = root.swap_address;
        const moving = tile ? carried.filter(a => !tile.windows.some(w => w.address === a)) : [];
        if (swap_with === "" && moving.length === 0) {
            root.cancel_pick();
            return;
        }
        root.picked = [];
        if (swap_with !== "") {
            WindowState.swap(carried[0], swap_with);
            root.selected_address = carried[0];
            refresh_timer.restart();
            return;
        }
        for (const a of moving) WindowState.move_to_workspace(a, tile.id, false);
        if (tile.is_new) Hyprland.dispatch("hl.dsp.workspace.move({ workspace = " + tile.id + ", monitor = '" + root.groups[tile.group].name + "' })");
        root.selected_key = "ws:" + tile.id;
        root.selected_address = moving[0];
        refresh_timer.restart();
    }

    function start_filter() {
        root.typing = true;
        filter_input.forceActiveFocus();
        filter_input.cursorPosition = filter_input.text.length;
    }

    function accept_filter() {
        root.typing = false;
        keys.forceActiveFocus();
    }

    function clear_filter() {
        root.typing = false;
        filter_input.text = "";
        if (root.visible) keys.forceActiveFocus();
    }

    function show_help() {
        root.help_open = true;
        key_help.forceActiveFocus();
    }

    function hide_help() {
        root.help_open = false;
        if (root.typing) filter_input.forceActiveFocus();
        else keys.forceActiveFocus();
    }

    function is_help_key(event) {
        return event.key === Qt.Key_Question || event.text === "?";
    }

    function handle_key(event) {
        const k = event.key;
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) return;
        if (root.is_help_key(event)) {
            root.show_help();
        } else if (k === Qt.Key_Escape) {
            if (root.carrying) root.cancel_pick();
            else if (root.marks.length > 0) root.marks = [];
            else if (root.query !== "") root.clear_filter();
            else root.hide_overview();
        } else if (k === Qt.Key_Q) {
            root.hide_overview();
        } else if (k === Qt.Key_H || k === Qt.Key_Left) {
            root.move(-1, 0);
        } else if (k === Qt.Key_L || k === Qt.Key_Right) {
            root.move(1, 0);
        } else if (k === Qt.Key_K || k === Qt.Key_Up) {
            root.move(0, -1);
        } else if (k === Qt.Key_J || k === Qt.Key_Down) {
            root.move(0, 1);
        } else if (k === Qt.Key_Tab) {
            root.cycle_window(1);
        } else if (k === Qt.Key_Backtab) {
            root.cycle_window(-1);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (root.carrying) root.drop();
            else root.activate();
        } else if (k === Qt.Key_M) {
            if (root.carrying) root.drop();
            else root.pick();
        } else if (!root.carrying && (k === Qt.Key_Space || (k === Qt.Key_V && !(event.modifiers & Qt.ShiftModifier)))) {
            root.toggle_mark();
        } else if (!root.carrying && k === Qt.Key_V) {
            root.toggle_mark_all();
        } else if (k === Qt.Key_F) {
            root.filmstrip = !root.filmstrip;
        } else if (k === Qt.Key_Slash || event.text === "/") {
            root.start_filter();
        } else if (k >= Qt.Key_1 && k <= Qt.Key_9) {
            root.jump(k - Qt.Key_0);
        } else {
            return;
        }
        event.accepted = true;
    }

    // A click on a tile's background focuses the workspace itself rather than one of its windows.
    function tile_clicked(index, address) {
        root.select(index, address);
        if (root.carrying) {
            root.drop();
        } else if (address === "" && root.selected_tile) {
            root.focus_workspace(root.selected_tile);
            root.hide_overview();
        } else {
            root.activate();
        }
    }

    readonly property string footer_text: root.help_open ? "? back · Esc back · q close"
        : root.typing ? "Enter accept · Tab next match · Esc clear · ? help"
        : root.swap_address !== "" ? "m swap · Enter swap · Tab other window · hjkl workspace · Esc cancel · ? help"
        : root.carrying ? "hjkl workspace · Tab window · m drop · Enter drop · Esc cancel · ? help"
        : root.marks.length > 0 ? "Space mark · V mark all · m move " + root.marks.length + " · hjkl move · Esc clear marks · ? help"
        : "hjkl move · Tab window · Enter focus · m move · Space mark · / filter · f view · ? help · q close"

    readonly property string normal_help: "h/j/k/l move between workspaces · Arrows move between workspaces · Tab next window · Shift+Tab previous window · Enter focus window, or the workspace if empty · m pick up window, or every marked window · Space/v mark or unmark window · V mark or unmark all in workspace · / filter windows · 1-9 select workspace by id · f toggle filmstrip view, j/k there jump monitors · Click focus window or workspace"
    readonly property string carry_help: "h/j/k/l choose target workspace · Arrows choose target workspace · 1-9 target workspace by id · Tab/Shift+Tab choose a window in the same workspace to swap with · m drop there, or swap with the SWAP window · Enter drop there, or swap · f toggle filmstrip view · Click drop on workspace · Esc cancel, marks come back"
    readonly property string help_text: root.typing ? "Type filter by class or title · Enter accept filter · Tab/Down next match · Shift+Tab/Up previous match · Backspace delete, clears when empty · Esc clear filter"
        : root.carrying ? root.carry_help
        : root.marks.length > 0 ? "Esc clear all marks · " + root.normal_help
        : root.query !== "" ? "Esc clear filter · / edit filter · " + root.normal_help
        : root.normal_help

    readonly property string status_text: {
        if (root.typing || root.query !== "") return "/" + root.query + (root.typing ? "_" : "") + "  " + root.match_count + " match" + (root.match_count === 1 ? "" : "es");
        const lead = root.picked_toplevel ? WindowState.short_class(root.picked_toplevel) : "window";
        if (root.swap_address !== "") {
            const other = WindowState.find(root.swap_address);
            return ("SWAP " + lead + " with " + (other ? WindowState.short_class(other) : "window")).toUpperCase();
        }
        if (root.carrying) return root.picked.length > 1 ? "MOVE " + root.picked.length + " windows" : "MOVE " + lead.toUpperCase();
        const tile = root.selected_tile;
        if (!tile) return "";
        const mon = root.groups[tile.group] ? root.groups[tile.group].name : "";
        return (root.marks.length > 0 ? root.marks.length + " marked · " : "") + mon + " · " + (tile.is_new ? "new workspace " + tile.name : "workspace " + tile.name + " · " + tile.windows.length + " window" + (tile.windows.length === 1 ? "" : "s"));
    }

    NumberAnimation {
        id: reveal_anim
        target: root
        property: "reveal"
        duration: 170
        easing.type: Easing.OutCubic
        onFinished: if (!root.wanted) root.visible = false
    }

    Timer {
        id: refresh_timer
        interval: 120
        onTriggered: root.refresh()
    }

    Connections {
        target: Hyprland
        enabled: root.visible

        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode", "fullscreen", "monitoradded", "monitorremoved", "moveworkspace", "moveworkspacev2"].indexOf(event.name) >= 0) refresh_timer.restart();
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.alpha(Theme.bg_crust, 0.6)
        opacity: root.reveal

        MouseArea {
            anchors.fill: parent
            onClicked: root.hide_overview()
        }
    }

    OverviewFrame {
        id: frame
        x: Style.px(36)
        y: Style.px(30)
        width: parent.width - x * 2
        height: parent.height - y * 2
        opacity: root.reveal
        scale: 0.97 + 0.03 * root.reveal
        title: "OVERVIEW"
        status: root.status_text
        status_color: root.carrying || root.marks.length > 0 || root.query !== "" ? Style.text_accent : Style.text_muted
        footer: root.footer_text

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => root.handle_key(event)
        }

        TextInput {
            id: filter_input
            width: 0
            height: 0
            opacity: 0
            maximumLength: 64
            onTextChanged: {
                root.query = text;
                if (text !== "") {
                    const list = root.match_list();
                    if (list.length > 0) root.select(list[0].tile, list[0].address);
                }
            }
            Keys.onPressed: event => {
                const k = event.key;
                if (root.is_help_key(event)) {
                    root.show_help();
                } else if (k === Qt.Key_Escape) {
                    root.clear_filter();
                } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                    root.accept_filter();
                } else if (k === Qt.Key_Tab || k === Qt.Key_Down) {
                    root.step_match(1);
                } else if (k === Qt.Key_Backtab || k === Qt.Key_Up) {
                    root.step_match(-1);
                } else if (k === Qt.Key_Backspace && filter_input.text === "") {
                    root.clear_filter();
                } else {
                    return;
                }
                event.accepted = true;
            }
        }

        Repeater {
            model: root.groups

            Item {
                id: group
                required property var modelData
                required property int index
                readonly property var rect: root.layout.group_rects[group.index] || ({ x: 0, y: 0, w: 0, h: 0 })
                readonly property bool holds_selection: !!root.selected_tile && root.selected_tile.group === group.index

                x: group.rect.x
                y: group.rect.y
                width: group.rect.w
                height: group.rect.h

                Behavior on x {
                    enabled: root.animate_moves
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    visible: !root.filmstrip
                    anchors.fill: parent
                    radius: Style.radius(8)
                    color: Qt.alpha(Theme.bg_mantle, 0.5)
                    border.width: 1
                    border.color: group.holds_selection ? Qt.alpha(Style.caret_color, 0.6) : Qt.alpha(Theme.ui_border, 0.6)
                }

                Rectangle {
                    visible: root.filmstrip
                    y: root.metrics.label - Style.px(4)
                    width: parent.width
                    height: 1
                    color: group.holds_selection ? Style.caret_color : Theme.ui_border
                }

                Item {
                    x: root.metrics.pad
                    y: root.filmstrip ? 0 : Style.px(6)
                    width: parent.width - root.metrics.pad * 2
                    height: section.implicitHeight
                    clip: true

                    MenuSection {
                        id: section
                        label: group.modelData.name + (group.modelData.focused ? " · focused" : "")
                        color: group.holds_selection ? Style.text_primary : Style.section_fg
                    }
                }
            }
        }

        Repeater {
            model: tile_slots

            WorkspaceTile {
                id: tile
                required property string key
                readonly property int index: root.tile_index_of[tile.key] !== undefined ? root.tile_index_of[tile.key] : -1
                readonly property var modelData: root.tiles[tile.index] || null
                readonly property var rect: root.layout.tile_rects[tile.index] || ({ x: 0, y: 0, w: 0, h: 0 })

                x: tile.rect.x
                y: tile.rect.y
                width: tile.rect.w
                height: tile.rect.h
                visible: tile.rect.w > 0 && tile.x + tile.width > 0 && tile.x < frame.body.width
                entry: tile.modelData
                selected: tile.index === root.selected_index
                selected_address: root.current_address
                picked: root.picked_set
                picked_toplevel: root.picked_toplevel
                picked_count: root.picked.length
                marks: root.mark_numbers
                swap_address: tile.selected ? root.swap_address : ""
                drop_target: tile.selected && root.can_drop
                matches: root.matches
                shown: root.visible
                live: tile.selected && !root.filmstrip

                onTile_clicked: root.tile_clicked(tile.index, "")
                onWindow_clicked: address => root.tile_clicked(tile.index, address)

                Behavior on x {
                    enabled: root.animate_moves
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }
        }

        WorkspaceTile {
            id: big_tile
            readonly property var rect: root.layout.big || ({ x: 0, y: 0, w: 0, h: 0 })
            visible: root.filmstrip && !!root.layout.big
            x: big_tile.rect.x
            y: big_tile.rect.y
            width: big_tile.rect.w
            height: big_tile.rect.h
            entry: root.selected_tile
            selected: true
            selected_address: root.current_address
            picked: root.picked_set
            picked_toplevel: root.picked_toplevel
            picked_count: root.picked.length
            marks: root.mark_numbers
            swap_address: root.swap_address
            drop_target: root.can_drop
            matches: root.matches
            shown: root.visible && root.filmstrip
            live: true

            onTile_clicked: root.tile_clicked(root.selected_index, "")
            onWindow_clicked: address => root.tile_clicked(root.selected_index, address)
        }

        // The full key list for the current mode, drawn over the tiles.
        Rectangle {
            visible: root.help_open
            anchors.fill: parent
            color: Style.frame_color.a > 0.5 ? Style.frame_color : Theme.bg_crust

            KeyHelp {
                id: key_help
                anchors.fill: parent
                text: root.help_text
                general: [{ key: "?", desc: "back" }, { key: "Esc", desc: "back" }, { key: "q", desc: "close overview" }]
                onBack: root.hide_help()
                onClose_requested: root.hide_overview()
            }
        }
    }
}
