// home/quickshell/.config/quickshell/tmux_overview/TmuxOverview.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../theme"
import "../services"
import "../overview"
import "../overview/Layout.js" as Layout
import "../picker/Fuzzy.js" as Fuzzy
import "TmuxData.js" as TmuxData
import "Ansi.js" as Ansi

// Every tmux session and window in one full-screen view: jump to, move, swap and kill windows by key.
PanelWindow {
    id: root

    property bool wanted: false
    property string held_screen_name: ""
    property bool filmstrip: false
    property real reveal: 0

    property var model: ({ groups: [], tiles: [], clients: [] })
    property bool loaded: false
    // pane_id -> rich text, and the raw capture it came from.
    property var previews: ({})
    property var raw_captures: ({})

    property string selected_key: ""
    property string selected_pane: ""
    // Carried window ids, and the marks they came from so Esc can put them back.
    property var picked: []
    property bool picked_from_marks: false
    property var marks: []
    property bool typing: false
    property bool help_open: false
    property string query: ""
    property int hit: 0
    property bool from_search: false

    readonly property var groups: root.model.groups
    readonly property var tiles: root.model.tiles
    readonly property var clients: root.model.clients
    readonly property var tile_index_of: {
        const out = {};
        root.tiles.forEach((t, i) => out[t.key] = i);
        return out;
    }
    readonly property int selected_index: Math.max(0, root.tiles.findIndex(t => t.key === root.selected_key))
    readonly property var selected_tile: root.tiles[root.selected_index] || null
    readonly property var tab_order: root.selected_tile ? root.reading_order(root.selected_tile.panes) : []
    readonly property var current_pane_entry: root.tab_order.find(p => p.pane_id === root.selected_pane) || root.tab_order.find(p => p.active) || root.tab_order[0] || null
    readonly property string current_pane: root.current_pane_entry ? root.current_pane_entry.pane_id : ""
    readonly property bool carrying: root.picked.length > 0
    readonly property var picked_set: root.to_set(root.picked)
    readonly property var mark_numbers: {
        const out = {};
        root.marks.forEach((k, i) => out[k] = i + 1);
        return out;
    }
    // One window carried inside its own session, selection on another window there: m/Enter swaps them.
    readonly property string swap_key: root.picked.length === 1 && !!root.selected_tile && root.selected_tile.key !== root.picked[0] && root.session_of(root.picked[0]) === root.selected_tile.session_id ? root.selected_tile.key : ""
    readonly property bool can_drop: root.carrying && root.swap_key === "" && !!root.selected_tile && root.picked.some(k => root.session_of(k) !== root.selected_tile.session_id)
    readonly property var nav_order: Layout.flat(Layout.flat(Layout.bands(root.groups)).map(g => root.groups[g].tiles))
    readonly property var ranked: root.typing ? root.rank(TmuxData.search_entries(root.tiles, Quickshell.env("HOME") || "", root.picked_set), root.query) : []
    readonly property int hit_index: Math.min(root.hit, root.ranked.length - 1)
    readonly property var hit_entry: root.ranked[root.hit_index] || null
    readonly property var matches: root.query === "" ? null : root.to_set(root.ranked.map(e => e.key))
    readonly property int match_count: root.ranked.length
    readonly property real list_width: root.typing ? Math.min(Style.px(460), frame.body.width * 0.34) : 0
    readonly property var ansi_palette: [Theme.black, Theme.red, Theme.green, Theme.yellow, Theme.blue, Theme.magenta, Theme.cyan, Theme.white, Theme.bright_black, Theme.bright_red, Theme.bright_green, Theme.bright_yellow, Theme.bright_blue, Theme.bright_magenta, Theme.bright_cyan, Theme.bright_white].map(c => String(c))

    readonly property var metrics: ({
        gap: Style.px(10),
        pad: Style.px(10),
        label: Style.fs(-3) + Style.px(12),
        group_gap: Style.px(22),
        strip: Style.px(150)
    })
    readonly property var layout: Layout.compute(root.filmstrip, root.groups, root.tiles, frame.body.width - root.list_width, frame.body.height, root.metrics, root.selected_index)
    readonly property string term_name: (DefaultApps.app_value("term") || Quickshell.env("TERMINAL") || "kitty").toLowerCase()
    readonly property bool animate_moves: root.filmstrip && Power.on_ac && root.reveal === 1
    // The selected pane (or the whole tile) in body coordinates, for the scope skin.
    readonly property var aim: {
        const tile = root.selected_tile;
        const r = root.filmstrip ? root.layout.big : root.layout.tile_rects[root.selected_index];
        if (!tile || !r || r.w <= 0) return null;
        const g = root.groups[tile.group];
        const place = (g ? g.name + " : " : "") + tile.index + " " + tile.name.trim();
        const p = root.current_pane_entry;
        if (!p) return { x: r.x, y: r.y, w: r.w, h: r.h, cls: "EMPTY", place: place, real: null };
        const cw = r.w - 4;
        const ch = r.h - 4;
        return { x: r.x + 2 + p.rx * cw, y: r.y + 2 + p.ry * ch, w: Math.max(4, p.rw * cw), h: Math.max(4, p.rh * ch), cls: p.cmd.toUpperCase(), place: place, real: { x: p.left, y: p.top, w: p.cols, h: p.rows } };
    }

    onTilesChanged: {
        Layout.sync_keys(tile_slots, root.tiles.map(t => t.key));
        if (!root.loaded) return;
        if (root.marks.some(k => root.tile_index_of[k] === undefined)) root.marks = root.marks.filter(k => root.tile_index_of[k] !== undefined);
        if (root.picked.some(k => root.tile_index_of[k] === undefined)) root.picked = root.picked.filter(k => root.tile_index_of[k] !== undefined);
        if (root.tiles.length > 0 && root.tile_index_of[root.selected_key] === undefined) root.select(Math.min(root.selected_index, root.tiles.length - 1));
    }

    ListModel {
        id: tile_slots
    }

    screen: Quickshell.screens.find(s => s.name === root.held_screen_name) || null
    visible: false
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-tmux-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "tmux-overview"

        function open(): string {
            root.show_overview();
            return "ok";
        }

        function close(): string {
            root.hide_overview();
            return "ok";
        }

        function search(): string {
            root.show_overview();
            root.start_filter(true);
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
        WindowState.refresh();
        root.filmstrip = false;
        root.loaded = false;
        root.model = { groups: [], tiles: [], clients: [] };
        root.previews = {};
        root.raw_captures = {};
        root.selected_key = "";
        root.selected_pane = "";
        root.picked = [];
        root.from_search = false;
        root.marks = [];
        root.help_open = false;
        digit_timer.stop();
        root.clear_filter();
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
        root.reload();
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

    function reload() {
        if (list_proc.running) {
            list_proc.again = true;
            return;
        }
        list_proc.command = TmuxData.list_command();
        list_proc.running = true;
    }

    // The first load lands on the window the most recent client is looking at.
    function apply_model(text) {
        const next = TmuxData.parse_model(text);
        const first = !root.loaded;
        root.model = next;
        root.loaded = true;
        if (first) {
            const latest = TmuxData.latest_client(next.clients);
            const group = latest ? next.groups.find(g => g.id === latest.session_id) : null;
            const start = group ? group.active_tile : next.tiles.length > 0 ? 0 : -1;
            if (start >= 0) root.select(start);
            if (root.typing) root.reset_hit();
        }
        const missing = Layout.flat(next.tiles.map(t => t.panes)).map(p => p.pane_id).filter(id => root.previews[id] === undefined);
        if (missing.length > 0) root.capture(missing);
    }

    function capture(pane_ids) {
        if (capture_proc.running) {
            capture_proc.queued = capture_proc.queued.concat(pane_ids.filter(id => capture_proc.queued.indexOf(id) < 0));
            return;
        }
        capture_proc.command = TmuxData.capture_command(pane_ids);
        capture_proc.running = true;
    }

    function apply_captures(text) {
        const parsed = TmuxData.parse_captures(text);
        const html = Object.assign({}, root.previews);
        const raw = Object.assign({}, root.raw_captures);
        let changed = false;
        const panes = {};
        for (const t of root.tiles) for (const p of t.panes) panes[p.pane_id] = p;
        for (const id of Object.keys(parsed)) {
            if (raw[id] === parsed[id] || !panes[id]) continue;
            raw[id] = parsed[id];
            html[id] = Ansi.to_html(parsed[id], root.ansi_palette, String(Theme.fg_core), String(Theme.bg_core), panes[id].rows);
            changed = true;
        }
        if (changed) {
            root.raw_captures = raw;
            root.previews = html;
        }
    }

    function reading_order(panes) {
        return panes.slice().sort((a, b) => a.ry - b.ry || a.rx - b.rx);
    }

    function session_of(key) {
        const t = root.tiles[root.tile_index_of[key]];
        return t ? t.session_id : "";
    }

    function rank(entries, query) {
        const terms = Fuzzy.terms_of(query);
        if (terms.length === 0) return entries;
        const scored = [];
        for (const e of entries) {
            const s = Fuzzy.score_item(terms, e);
            if (s) scored.push({ entry: e, score: s.score });
        }
        scored.sort((a, b) => b.score - a.score || a.entry.recency - b.entry.recency);
        return scored.map(s => s.entry);
    }

    function select_entry(entry) {
        const at = entry ? root.tile_index_of[entry.key] : undefined;
        if (at !== undefined) root.select(at);
    }

    function set_hit(i) {
        root.hit = i;
        root.select_entry(root.hit_entry);
    }

    // An empty query starts on the window before the latest client's when searching, else on the selected window.
    function reset_hit() {
        const list = root.ranked;
        const latest = TmuxData.latest_client(root.clients);
        const group = latest ? root.groups.find(g => g.id === latest.session_id) : null;
        const current = group ? root.tiles[group.active_tile] : null;
        let at = 0;
        if (root.query === "") at = root.from_search ? (list.length >= 2 && current && list[0].key === current.key ? 1 : 0) : Math.max(0, list.findIndex(e => e.key === root.selected_key));
        root.set_hit(at);
    }

    function step_hit(delta) {
        const n = root.ranked.length;
        if (n > 0) root.set_hit((root.hit_index + delta + n) % n);
    }

    function accept_hit() {
        const entry = root.hit_entry;
        if (!entry) return;
        root.select_entry(entry);
        root.clear_filter();
        if (root.carrying) root.drop();
        else root.activate();
    }

    function select(index, pane) {
        const tile = root.tiles[index];
        if (!tile) return;
        root.selected_key = tile.key;
        if (pane !== undefined) {
            root.selected_pane = pane;
        } else {
            const active = tile.panes.find(p => p.active) || tile.panes[0];
            root.selected_pane = active ? active.pane_id : "";
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
                root.move_session(0, dy);
                return;
            }
        } else {
            to = Layout.neighbor(root.layout.tile_rects, from, dx, dy);
        }
        if (to !== undefined && to >= 0) root.select(to);
    }

    function select_session(group_index) {
        const g = root.groups[group_index];
        if (g) root.select(g.active_tile);
    }

    // Ctrl moves by session: the neighbouring group on the map, or the next or previous in the strip.
    function move_session(dx, dy) {
        const from = root.selected_tile ? root.selected_tile.group : 0;
        if (root.filmstrip) {
            const order = Layout.flat(Layout.bands(root.groups));
            const at = order.indexOf(from) + (dx !== 0 ? dx : dy);
            if (at >= 0 && at < order.length) root.select_session(order[at]);
            return;
        }
        const to = Layout.neighbor(root.layout.group_rects, from, dx, dy);
        if (to >= 0) root.select_session(to);
    }

    function cycle_pane(delta) {
        const order = root.tab_order;
        if (order.length === 0) return;
        const at = order.findIndex(p => p.pane_id === root.current_pane);
        root.selected_pane = order[(at + delta + order.length) % order.length].pane_id;
    }

    function cursor_key() {
        return root.selected_key + "|" + root.current_pane;
    }
    function play_if_moved(before) {
        if (root.cursor_key() !== before) ThemeAudio.play("cursor");
    }

    function jump(window_index) {
        const group = root.selected_tile ? root.selected_tile.group : -1;
        const i = root.tiles.findIndex(t => t.group === group && t.index === window_index);
        if (i >= 0) root.select(i);
        return i >= 0;
    }

    // Digits typed in quick succession name one window index, so 1 then 2 lands on 12 when it exists.
    function type_digit(d) {
        const before = root.cursor_key();
        const joined = digit_timer.running ? digit_timer.typed + d : "";
        if (joined !== "" && root.jump(parseInt(joined))) {
            digit_timer.typed = joined;
        } else {
            root.jump(parseInt(d));
            digit_timer.typed = d;
        }
        root.play_if_moved(before);
        digit_timer.restart();
    }

    function window_address(session_name) {
        const t = WindowState.windows.find(w => (WindowState.class_of(w) || "").toLowerCase().indexOf(root.term_name) >= 0 && TmuxData.title_matches(w.title || "", session_name));
        return t ? t.address : "";
    }

    function session_name_of(session_id) {
        const g = root.groups.find(x => x.id === session_id);
        return g ? g.name : "";
    }

    function tmux(args) {
        Quickshell.execDetached(["tmux"].concat(args));
    }

    // Focus waits for the exclusive keyboard grab to drop, see focus_timer.
    function activate() {
        const tile = root.selected_tile;
        if (!tile) return;
        const select = ["select-window", "-t", tile.key, ";", "select-pane", "-t", root.current_pane];
        let address = TmuxData.client_of(root.clients, tile.session_id) ? root.window_address(tile.session_name) : "";
        if (address !== "") {
            root.tmux(select);
        } else {
            const latest = TmuxData.latest_client(root.clients);
            if (latest) {
                address = root.window_address(root.session_name_of(latest.session_id));
                root.tmux(["switch-client", "-c", latest.name, "-t", tile.session_id, ";"].concat(select));
            } else {
                root.tmux(select);
                Quickshell.execDetached(["sh", "-c", "t=\"${XDG_STATE_HOME:-$HOME/.local/state}/hypr/bin/term\"; [ -x \"$t\" ] || t=\"${TERMINAL:-kitty}\"; exec \"$t\" -e tmux attach-session -t \"$1\"", "sh", tile.session_id]);
            }
        }
        root.hide_overview();
        if (address === "") return;
        WindowState.focus(address);
        focus_timer.address = address;
        focus_timer.restart();
    }

    function to_set(list) {
        const out = {};
        for (const k of list) out[k] = true;
        return out;
    }

    function alive(list) {
        return list.filter(k => root.tile_index_of[k] !== undefined);
    }

    function toggle_mark() {
        const k = root.selected_key;
        if (!root.selected_tile) return;
        root.marks = root.marks.indexOf(k) >= 0 ? root.marks.filter(m => m !== k) : root.marks.concat([k]);
    }

    // Marks every window in the selected session, or unmarks them all when they already are.
    function toggle_mark_all() {
        if (!root.selected_tile) return;
        const here = root.groups[root.selected_tile.group].tiles.map(i => root.tiles[i].key);
        const all = here.every(k => root.marks.indexOf(k) >= 0);
        root.marks = all ? root.marks.filter(m => here.indexOf(m) < 0) : root.marks.concat(here.filter(k => root.marks.indexOf(k) < 0));
    }

    // Kills every marked window, or the selected one; selection steps to the next window in the session.
    function kill_windows() {
        const marked = root.alive(root.marks);
        const doomed = marked.length > 0 ? marked : root.selected_tile ? [root.selected_key] : [];
        if (doomed.length === 0) return;
        const siblings = root.groups[root.selected_tile.group].tiles.map(i => root.tiles[i].key);
        const at = siblings.indexOf(root.selected_key);
        const left = siblings.filter(k => doomed.indexOf(k) < 0);
        const next = left.find(k => siblings.indexOf(k) > at) || left[left.length - 1];
        if (next) root.selected_key = next;
        root.marks = [];
        let args = [];
        for (const k of doomed) args = args.concat(args.length > 0 ? [";"] : [], ["kill-window", "-t", k]);
        root.tmux(args);
        reload_timer.restart();
    }

    function pick() {
        const marked = root.alive(root.marks);
        if (marked.length > 0) {
            root.picked = marked;
            root.picked_from_marks = true;
            root.marks = [];
        } else if (root.selected_tile) {
            root.picked = [root.selected_key];
            root.picked_from_marks = false;
        }
    }

    function cancel_pick() {
        if (root.picked_from_marks) root.marks = root.alive(root.picked);
        root.picked = [];
    }

    // Swaps inside a session, else moves every carried window into the selected session.
    function drop() {
        const tile = root.selected_tile;
        const carried = root.alive(root.picked);
        const swap_with = root.swap_key;
        const moving = tile ? carried.filter(k => root.session_of(k) !== tile.session_id) : [];
        if (swap_with === "" && moving.length === 0) {
            root.cancel_pick();
            return;
        }
        root.picked = [];
        if (swap_with !== "") {
            root.tmux(["swap-window", "-s", carried[0], "-t", swap_with]);
            root.selected_key = carried[0];
        } else {
            let args = [];
            for (const k of moving) args = args.concat(args.length > 0 ? [";"] : [], ["move-window", "-s", k, "-t", tile.session_id + ":"]);
            root.tmux(args);
            root.selected_key = tile.session_id + ":" + moving[0].split(":")[1];
        }
        reload_timer.restart();
    }

    function start_filter(from_search) {
        root.from_search = from_search;
        root.typing = true;
        filter_input.forceActiveFocus();
        filter_input.cursorPosition = filter_input.text.length;
        root.reset_hit();
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

    function handle_ctrl(event) {
        const before = root.cursor_key();
        const k = event.key;
        if (k === Qt.Key_H || k === Qt.Key_Left) root.move_session(-1, 0);
        else if (k === Qt.Key_L || k === Qt.Key_Right) root.move_session(1, 0);
        else if (k === Qt.Key_K || k === Qt.Key_Up) root.move_session(0, -1);
        else if (k === Qt.Key_J || k === Qt.Key_Down) root.move_session(0, 1);
        else if (k >= Qt.Key_0 && k <= Qt.Key_9) root.select_session(k === Qt.Key_0 ? 9 : k - Qt.Key_1);
        else return;
        root.play_if_moved(before);
        event.accepted = true;
    }

    function handle_key(event) {
        const before = root.cursor_key();
        const k = event.key;
        if (event.modifiers & Qt.AltModifier) return;
        if (event.modifiers & Qt.ControlModifier) {
            root.handle_ctrl(event);
            return;
        }
        if (root.is_help_key(event)) {
            root.show_help();
        } else if (k === Qt.Key_Escape) {
            ThemeAudio.play("cancel");
            if (root.carrying) root.cancel_pick();
            else if (root.marks.length > 0) root.marks = [];
            else if (root.query !== "") root.clear_filter();
            else root.hide_overview();
        } else if (k === Qt.Key_Q) {
            ThemeAudio.play("cancel");
            root.hide_overview();
        } else if (k === Qt.Key_H || k === Qt.Key_Left) {
            root.move(-1, 0);
            root.play_if_moved(before);
        } else if (k === Qt.Key_L || k === Qt.Key_Right) {
            root.move(1, 0);
            root.play_if_moved(before);
        } else if (k === Qt.Key_K || k === Qt.Key_Up) {
            root.move(0, -1);
            root.play_if_moved(before);
        } else if (k === Qt.Key_J || k === Qt.Key_Down) {
            root.move(0, 1);
            root.play_if_moved(before);
        } else if (k === Qt.Key_Tab) {
            root.cycle_pane(1);
            root.play_if_moved(before);
        } else if (k === Qt.Key_Backtab) {
            root.cycle_pane(-1);
            root.play_if_moved(before);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            ThemeAudio.play("confirm");
            if (root.carrying) root.drop();
            else root.activate();
        } else if (k === Qt.Key_M) {
            ThemeAudio.play("confirm");
            if (root.carrying) root.drop();
            else root.pick();
        } else if (!root.carrying && (k === Qt.Key_Space || (k === Qt.Key_V && !(event.modifiers & Qt.ShiftModifier)))) {
            root.toggle_mark();
            ThemeAudio.play("confirm");
        } else if (!root.carrying && k === Qt.Key_V) {
            root.toggle_mark_all();
            ThemeAudio.play("confirm");
        } else if (!root.carrying && k === Qt.Key_X) {
            root.kill_windows();
            ThemeAudio.play("confirm");
        } else if (k === Qt.Key_F) {
            root.filmstrip = !root.filmstrip;
        } else if (k === Qt.Key_Slash || event.text === "/") {
            root.start_filter(false);
        } else if (k >= Qt.Key_0 && k <= Qt.Key_9) {
            root.type_digit(String(k - Qt.Key_0));
        } else {
            return;
        }
        event.accepted = true;
    }

    // A click on a pane selects it and goes there; a click on the tile itself goes to its active pane.
    function tile_clicked(index, pane) {
        ThemeAudio.play("confirm");
        root.select(index, pane === "" ? undefined : pane);
        if (root.carrying) root.drop();
        else root.activate();
    }

    readonly property string footer_text: root.help_open ? "? back · Esc back · q close"
        : root.typing ? "Enter " + (root.carrying ? "drop here" : "go") + " · Tab/Down next · Shift+Tab/Up previous · Esc " + (root.from_search && root.query === "" ? "close" : "clear") + " · ? help"
        : root.swap_key !== "" ? "m swap · Enter swap · hjkl window · Esc cancel · ? help"
        : root.carrying ? "hjkl session · m drop · Enter drop · Esc cancel · ? help"
        : root.marks.length > 0 ? "Space mark · V mark all · m move " + root.marks.length + " · x kill " + root.marks.length + " · hjkl move · Esc clear marks · ? help"
        : "hjkl move · Ctrl+hjkl session · Tab pane · Enter go · m move · x kill · Space mark · / search · f view · ? help · q close"

    readonly property string normal_help: "h/j/k/l move between windows · Arrows move between windows · Ctrl+h/j/k/l or Ctrl+Arrows jump to the neighbouring session · Ctrl+1-9 jump to the nth session, Ctrl+0 the 10th · 1-9 select window by tmux index in this session, type 12 quickly for window 12 · Tab next pane · Shift+Tab previous pane · Enter go to window and pane · m pick up window, or every marked window · x kill window, or every marked window · Space/v mark or unmark window · V mark or unmark all in session · / search windows by name, command, path or session · f toggle filmstrip view · Click go to window or pane"
    readonly property string carry_help: "h/j/k/l choose target window or session · Arrows choose target · Ctrl+h/j/k/l jump to a session · Ctrl+1-9 target the nth session · m drop into the selected session, or swap with the selected window of the same session · Enter drop or swap · f toggle filmstrip view · Click drop or swap · Esc cancel, marks come back"
    readonly property string help_text: root.typing ? "Type to search windows by name, pane command, pane path or session · Enter go to the highlighted window, or drop the carried window on its session · Tab/Down next match · Shift+Tab/Up previous match · Backspace delete, clears when empty · Esc clear search, or close when it is empty"
        : root.carrying ? root.carry_help
        : root.marks.length > 0 ? "Esc clear all marks · " + root.normal_help
        : root.query !== "" ? "Esc clear search · " + root.normal_help
        : root.normal_help

    readonly property string status_text: {
        if (root.typing || root.query !== "") return "/" + root.query + (root.typing ? "_" : "") + "  " + root.match_count + " match" + (root.match_count === 1 ? "" : "es");
        if (root.swap_key !== "") return "SWAP window " + (root.tiles[root.tile_index_of[root.picked[0]]] || { index: "" }).index;
        if (root.carrying) return root.picked.length > 1 ? "MOVE " + root.picked.length + " windows" : "MOVE WINDOW " + (root.tiles[root.tile_index_of[root.picked[0]]] || { index: "" }).index;
        const tile = root.selected_tile;
        if (!tile) return root.loaded ? "no tmux sessions" : "";
        const n = tile.panes.length;
        return (root.marks.length > 0 ? root.marks.length + " marked · " : "") + tile.session_name + " · window " + tile.index + " · " + n + " pane" + (n === 1 ? "" : "s");
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
        id: digit_timer
        property string typed: ""
        interval: 600
    }

    Timer {
        id: reload_timer
        interval: 150
        onTriggered: root.reload()
    }

    // Only the selected window's panes refresh while open; the rest keep the snapshot taken on open.
    Timer {
        id: live_timer
        interval: 1000
        repeat: true
        running: root.visible && root.wanted && root.loaded && Power.on_ac
        onTriggered: {
            if (root.selected_tile && !capture_proc.running) root.capture(root.selected_tile.panes.map(p => p.pane_id));
        }
    }

    // Focus waits for the overlay to drop its exclusive keyboard grab, else the grab's release restores the old window.
    Timer {
        id: focus_timer
        property string address: ""
        interval: 60
        onTriggered: WindowState.focus(focus_timer.address)
    }

    Process {
        id: list_proc
        property bool again: false
        stdout: StdioCollector {
            onStreamFinished: root.apply_model(text)
        }
        onExited: {
            if (!list_proc.again) return;
            list_proc.again = false;
            root.reload();
        }
    }

    Process {
        id: capture_proc
        property var queued: []
        stdout: StdioCollector {
            onStreamFinished: root.apply_captures(text)
        }
        onExited: {
            if (capture_proc.queued.length === 0) return;
            const next = capture_proc.queued;
            capture_proc.queued = [];
            root.capture(next);
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.alpha(Theme.bg_crust, 0.6)
        opacity: root.reveal

        MouseArea {
            anchors.fill: parent
            onClicked: {
                ThemeAudio.play("cancel");
                root.hide_overview();
            }
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
        title: "TMUX"
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
                if (root.typing) root.reset_hit();
            }
            Keys.onPressed: event => {
                const before = root.cursor_key();
                const k = event.key;
                if (root.is_help_key(event)) {
                    root.show_help();
                } else if (k === Qt.Key_Escape) {
                    ThemeAudio.play("cancel");
                    if (root.from_search && root.query === "") root.hide_overview();
                    else root.clear_filter();
                } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                    ThemeAudio.play("confirm");
                    root.accept_hit();
                } else if (k === Qt.Key_Tab || k === Qt.Key_Down) {
                    root.step_hit(1);
                    root.play_if_moved(before);
                } else if (k === Qt.Key_Backtab || k === Qt.Key_Up) {
                    root.step_hit(-1);
                    root.play_if_moved(before);
                } else if (k === Qt.Key_Backspace && filter_input.text === "") {
                    ThemeAudio.play("cancel");
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

                Dither {
                    visible: !root.filmstrip && color.a > 0
                    anchors.fill: parent
                    anchors.margins: 1
                    color: Style.dither
                    radius: Style.radius(8)
                    top_radius: Style.radius(8)
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
                        label: (group.index + 1) + " " + group.modelData.name + (group.modelData.attached > 0 ? " · attached" : "")
                        color: group.holds_selection ? Style.text_primary : Style.section_fg
                    }
                }
            }
        }

        Repeater {
            model: tile_slots

            TmuxTile {
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
                selected_pane: root.current_pane
                picked: !!root.picked_set[tile.key]
                mark: root.mark_numbers[tile.key] || 0
                swap_target: root.swap_key === tile.key
                drop_target: tile.selected && root.can_drop
                dimmed: root.matches !== null && !root.matches[tile.key]
                previews: root.previews
                shown: root.visible

                onTile_clicked: root.tile_clicked(tile.index, "")
                onPane_clicked: pane_id => root.tile_clicked(tile.index, pane_id)

                Behavior on x {
                    enabled: root.animate_moves
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }
        }

        TmuxTile {
            id: big_tile
            readonly property var rect: root.layout.big || ({ x: 0, y: 0, w: 0, h: 0 })
            visible: root.filmstrip && !!root.layout.big
            x: big_tile.rect.x
            y: big_tile.rect.y
            width: big_tile.rect.w
            height: big_tile.rect.h
            entry: root.selected_tile
            selected: true
            selected_pane: root.current_pane
            picked: !!root.selected_tile && !!root.picked_set[root.selected_key]
            mark: root.selected_tile ? root.mark_numbers[root.selected_key] || 0 : 0
            swap_target: root.selected_tile !== null && root.swap_key === root.selected_key
            drop_target: root.can_drop
            previews: root.previews
            shown: root.visible && root.filmstrip

            onTile_clicked: root.tile_clicked(root.selected_index, "")
            onPane_clicked: pane_id => root.tile_clicked(root.selected_index, pane_id)
        }

        SearchList {
            visible: root.typing
            x: frame.body.width - width
            width: root.list_width
            height: frame.body.height
            entries: root.ranked
            current: root.hit_index
            onChosen: index => {
                root.set_hit(index);
                root.accept_hit();
            }
        }

        ScopeAim {
            anchors.fill: parent
            aim: root.help_open ? null : root.aim
            cls: root.aim ? root.aim.cls : ""
            place: root.aim ? root.aim.place : ""
            real: root.aim ? root.aim.real : null
            glide: Power.on_ac && root.reveal === 1
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
