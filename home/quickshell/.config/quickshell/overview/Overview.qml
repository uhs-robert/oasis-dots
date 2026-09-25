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
    // Temporary: which layout draft is drawn (1 mini-map, 2 rows, 3 filmstrip).
    property int draft: 1
    property real reveal: 0

    property string selected_key: ""
    property string selected_address: ""
    property string picked_address: ""
    property bool typing: false
    property string query: ""

    readonly property var model: root.visible ? root.build(Hyprland.monitors.values, Hyprland.workspaces.values, Hyprland.toplevels.values) : ({ groups: [], tiles: [] })
    readonly property var groups: root.model.groups
    readonly property var tiles: root.model.tiles
    readonly property int selected_index: Math.max(0, root.tiles.findIndex(t => t.key === root.selected_key))
    readonly property var selected_tile: root.tiles[root.selected_index] || null
    readonly property var tab_order: root.selected_tile ? root.reading_order(root.selected_tile.windows) : []
    readonly property string current_address: root.tab_order.some(w => w.address === root.selected_address) ? root.selected_address : root.tab_order.length > 0 ? root.tab_order[0].address : ""
    readonly property var picked_toplevel: root.picked_address !== "" ? WindowState.find(root.picked_address) : null
    readonly property var nav_order: Layout.flat(Layout.flat(Layout.bands(root.groups)).map(g => root.groups[g].tiles))
    readonly property var matches: root.query === "" ? null : root.match_set(root.query)
    readonly property int match_count: root.matches ? Object.keys(root.matches).length : 0

    readonly property var metrics: ({
        gap: Style.px(10),
        pad: Style.px(10),
        label: Style.fs(-3) + Style.px(12),
        group_gap: Style.px(22),
        label_col: Style.px(130),
        strip: Style.px(150)
    })
    readonly property var layout: Layout.compute(root.draft, root.groups, root.tiles, frame.body.width, frame.body.height, root.metrics, root.selected_index)
    readonly property bool animate_moves: root.draft === 3 && Power.on_ac && root.reveal === 1

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

    IpcHandler {
        target: "overview_draft"

        function set(n: int): string {
            if (n < 1 || n > 3) return "unknown";
            root.draft = n;
            return "ok";
        }

        function get(): int {
            return root.draft;
        }
    }

    function show_overview() {
        if (root.wanted) return;
        Popups.close();
        const mon = Hyprland.focusedMonitor;
        const target = (mon && Quickshell.screens.find(s => s.name === mon.name)) || Quickshell.screens[0];
        root.held_screen_name = target ? target.name : "";
        root.refresh();
        root.picked_address = "";
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
        if (root.draft === 3) {
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

    function pick() {
        if (root.current_address !== "") root.picked_address = root.current_address;
    }

    // Moves the carried window without following it; a fresh slot's workspace is then sent to its monitor.
    function drop() {
        const tile = root.selected_tile;
        const address = root.picked_address;
        root.picked_address = "";
        if (!tile || address === "" || tile.windows.some(w => w.address === address)) return;
        WindowState.move_to_workspace(address, tile.id, false);
        if (tile.is_new) Hyprland.dispatch("hl.dsp.workspace.move({ workspace = " + tile.id + ", monitor = '" + root.groups[tile.group].name + "' })");
        root.selected_key = "ws:" + tile.id;
        root.selected_address = address;
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

    function handle_key(event) {
        const k = event.key;
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) return;
        if (k === Qt.Key_Escape) {
            if (root.picked_address !== "") root.picked_address = "";
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
            if (root.picked_address !== "") root.drop();
            else root.activate();
        } else if (k === Qt.Key_M) {
            if (root.picked_address !== "") root.drop();
            else root.pick();
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
        if (root.picked_address !== "") {
            root.drop();
        } else if (address === "" && root.selected_tile) {
            root.focus_workspace(root.selected_tile);
            root.hide_overview();
        } else {
            root.activate();
        }
    }

    readonly property string footer_text: root.typing ? "Enter accept · Tab next match · Esc clear"
        : root.picked_address !== "" ? "hjkl target · m drop · Enter drop · 1-9 workspace · Esc cancel"
        : "hjkl move · Tab window · Enter focus · m move · / filter · 1-9 workspace · q close"

    readonly property string status_text: {
        if (root.typing || root.query !== "") return "/" + root.query + (root.typing ? "_" : "") + "  " + root.match_count + " match" + (root.match_count === 1 ? "" : "es");
        if (root.picked_address !== "") return "MOVE " + (root.picked_toplevel ? WindowState.short_class(root.picked_toplevel) : "window").toUpperCase();
        const tile = root.selected_tile;
        if (!tile) return "";
        const mon = root.groups[tile.group] ? root.groups[tile.group].name : "";
        return mon + " · " + (tile.is_new ? "new workspace " + tile.name : "workspace " + tile.name + " · " + tile.windows.length + " window" + (tile.windows.length === 1 ? "" : "s"));
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
        status_color: root.picked_address !== "" || root.query !== "" ? Style.text_accent : Style.text_muted
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
                if (k === Qt.Key_Escape) {
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
                    visible: root.draft !== 3
                    anchors.fill: parent
                    radius: Style.radius(8)
                    color: Qt.alpha(Theme.bg_mantle, 0.5)
                    border.width: 1
                    border.color: group.holds_selection ? Qt.alpha(Style.caret_color, 0.6) : Qt.alpha(Theme.ui_border, 0.6)
                }

                Rectangle {
                    visible: root.draft === 3
                    y: root.metrics.label - Style.px(4)
                    width: parent.width
                    height: 1
                    color: group.holds_selection ? Style.caret_color : Theme.ui_border
                }

                Item {
                    x: root.metrics.pad
                    y: root.draft === 2 ? (parent.height - height) / 2 : root.draft === 3 ? 0 : Style.px(6)
                    width: (root.draft === 2 ? root.metrics.label_col : parent.width) - root.metrics.pad * 2
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
            model: root.tiles

            WorkspaceTile {
                id: tile
                required property var modelData
                required property int index
                readonly property var rect: root.layout.tile_rects[tile.index] || ({ x: 0, y: 0, w: 0, h: 0 })

                x: tile.rect.x
                y: tile.rect.y
                width: tile.rect.w
                height: tile.rect.h
                visible: tile.rect.w > 0 && tile.x + tile.width > 0 && tile.x < frame.body.width
                entry: tile.modelData
                selected: tile.index === root.selected_index
                selected_address: root.current_address
                picked_address: root.picked_address
                picked_toplevel: root.picked_toplevel
                matches: root.matches
                shown: root.visible
                live: tile.selected && root.draft !== 3

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
            visible: root.draft === 3 && !!root.layout.big
            x: big_tile.rect.x
            y: big_tile.rect.y
            width: big_tile.rect.w
            height: big_tile.rect.h
            entry: root.selected_tile
            selected: true
            selected_address: root.current_address
            picked_address: root.picked_address
            picked_toplevel: root.picked_toplevel
            matches: root.matches
            shown: root.visible && root.draft === 3
            live: true

            onTile_clicked: root.tile_clicked(root.selected_index, "")
            onWindow_clicked: address => root.tile_clicked(root.selected_index, address)
        }
    }
}
