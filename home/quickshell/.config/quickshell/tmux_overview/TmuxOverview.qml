// home/quickshell/.config/quickshell/tmux_overview/TmuxOverview.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"
import "../services"
import "../overview"
import "../overview/Layout.js" as Layout
import "TmuxData.js" as TmuxData
import "Ansi.js" as Ansi

// Every tmux session and window in one full-screen view: jump to, move, swap and kill windows by key.
OverviewBase {
    id: root

    property var model: ({ groups: [], tiles: [], clients: [] })
    property bool loaded: false
    // pane_id -> rich text, and the raw capture it came from.
    property var previews: ({})
    property var raw_captures: ({})

    property string selected_pane: ""

    groups: root.model.groups
    tiles: root.model.tiles
    readonly property var clients: root.model.clients
    readonly property var tab_order: root.selected_tile ? root.reading_order(root.selected_tile.panes) : []
    readonly property var current_pane_entry: root.tab_order.find(p => p.pane_id === root.selected_pane) || root.tab_order.find(p => p.active) || root.tab_order[0] || null
    readonly property string current_pane: root.current_pane_entry ? root.current_pane_entry.pane_id : ""
    // One window carried inside its own session, selection on another window there: m/Enter swaps them.
    readonly property string swap_key: root.picked.length === 1 && !!root.selected_tile && root.selected_tile.key !== root.picked[0] && root.session_of(root.picked[0]) === root.selected_tile.session_id ? root.selected_tile.key : ""
    readonly property bool can_drop: root.carrying && root.swap_key === "" && !!root.selected_tile && root.picked.some(k => root.session_of(k) !== root.selected_tile.session_id)
    ranked: root.typing ? root.rank(TmuxData.search_entries(root.tiles, Quickshell.env("HOME") || "", root.picked_set), root.query) : []
    readonly property var matches: root.query === "" ? null : root.to_set(root.ranked.map(e => e.key))
    readonly property var ansi_palette: [Theme.black, Theme.red, Theme.green, Theme.yellow, Theme.blue, Theme.magenta, Theme.cyan, Theme.white, Theme.bright_black, Theme.bright_red, Theme.bright_green, Theme.bright_yellow, Theme.bright_blue, Theme.bright_magenta, Theme.bright_cyan, Theme.bright_white].map(c => String(c))
    readonly property string term_name: (DefaultApps.app_value("term") || Quickshell.env("TERMINAL") || "kitty").toLowerCase()
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

    onTiles_synced: {
        if (!root.loaded) return;
        if (root.marks.some(k => root.tile_index_of[k] === undefined)) root.marks = root.marks.filter(k => root.tile_index_of[k] !== undefined);
        if (root.picked.some(k => root.tile_index_of[k] === undefined)) root.picked = root.picked.filter(k => root.tile_index_of[k] !== undefined);
        if (root.tiles.length > 0 && root.tile_index_of[root.selected_key] === undefined) root.select(Math.min(root.selected_index, root.tiles.length - 1));
    }

    layer_namespace: "quickshell-tmux-overview"
    title: "TMUX"
    cursor_sub: root.current_pane
    zero_digit_jumps: true
    group_label: (g, i) => (i + 1) + " " + g.name + (g.attached > 0 ? " · attached" : "")
    dismiss: () => root.hide_overview()
    filmstrip_vertical: dy => root.move_session(0, dy)

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
        root.hold_focused_screen();
        WindowState.refresh();
        root.filmstrip = false;
        root.loaded = false;
        root.model = { groups: [], tiles: [], clients: [] };
        root.previews = {};
        root.raw_captures = {};
        root.selected_key = "";
        root.selected_pane = "";
        root.reset_common();
        root.wanted = true;
        root.visible = true;
        root.reveal_open();
        root.reload();
    }

    function hide_overview() {
        if (!root.wanted) return;
        root.wanted = false;
        root.conceal(false);
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

    function session_of(key) {
        const t = root.tiles[root.tile_index_of[key]];
        return t ? t.session_id : "";
    }

    select_entry: function (entry) {
        const at = entry ? root.tile_index_of[entry.key] : undefined;
        if (at !== undefined) root.select(at);
    }

    // An empty query starts on the window before the latest client's when searching, else on the selected window.
    reset_hit: function () {
        const list = root.ranked;
        const latest = TmuxData.latest_client(root.clients);
        const group = latest ? root.groups.find(g => g.id === latest.session_id) : null;
        const current = group ? root.tiles[group.active_tile] : null;
        let at = 0;
        if (root.query === "") at = root.from_search ? (list.length >= 2 && current && list[0].key === current.key ? 1 : 0) : Math.max(0, list.findIndex(e => e.key === root.selected_key));
        root.set_hit(at);
    }

    accept_hit: function () {
        const entry = root.hit_entry;
        if (!entry) return;
        root.select_entry(entry);
        root.clear_filter();
        if (root.carrying) root.drop();
        else root.activate();
    }

    select: function (index, pane) {
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

    jump: function (window_index) {
        const group = root.selected_tile ? root.selected_tile.group : -1;
        const i = root.tiles.findIndex(t => t.group === group && t.index === window_index);
        if (i >= 0) root.select(i);
        return i >= 0;
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

    // Focus waits for the exclusive keyboard grab to drop, see focus_later.
    activate: function () {
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
        root.focus_later(address);
    }

    function alive(list) {
        return list.filter(k => root.tile_index_of[k] !== undefined);
    }

    toggle_mark: function () {
        const k = root.selected_key;
        if (!root.selected_tile) return;
        root.marks = root.marks.indexOf(k) >= 0 ? root.marks.filter(m => m !== k) : root.marks.concat([k]);
    }

    // Marks every window in the selected session, or unmarks them all when they already are.
    toggle_mark_all: function () {
        if (!root.selected_tile) return;
        const here = root.groups[root.selected_tile.group].tiles.map(i => root.tiles[i].key);
        const all = here.every(k => root.marks.indexOf(k) >= 0);
        root.marks = all ? root.marks.filter(m => here.indexOf(m) < 0) : root.marks.concat(here.filter(k => root.marks.indexOf(k) < 0));
    }

    // Kills every marked window, or the selected one; selection steps to the next window in the session.
    close_selected: function () {
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

    pick: function () {
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

    cancel_pick: function () {
        if (root.picked_from_marks) root.marks = root.alive(root.picked);
        root.picked = [];
    }

    // Swaps inside a session, else moves every carried window into the selected session.
    drop: function () {
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

    pre_key: function (event) {
        if (!(event.modifiers & Qt.ControlModifier)) return "";
        const before = root.cursor_key();
        const k = event.key;
        if (k === Qt.Key_H || k === Qt.Key_Left) root.move_session(-1, 0);
        else if (k === Qt.Key_L || k === Qt.Key_Right) root.move_session(1, 0);
        else if (k === Qt.Key_K || k === Qt.Key_Up) root.move_session(0, -1);
        else if (k === Qt.Key_J || k === Qt.Key_Down) root.move_session(0, 1);
        else if (k >= Qt.Key_0 && k <= Qt.Key_9) root.select_session(k === Qt.Key_0 ? 9 : k - Qt.Key_1);
        else return "stop";
        root.play_if_moved(before);
        return "done";
    }

    extra_key: function (event, before) {
        const k = event.key;
        if (k === Qt.Key_Tab) root.cycle_pane(1);
        else if (k === Qt.Key_Backtab) root.cycle_pane(-1);
        else return false;
        root.play_if_moved(before);
        return true;
    }

    // A click on a pane selects it and goes there; a click on the tile itself goes to its active pane.
    function tile_clicked(index, pane) {
        ThemeAudio.play("confirm");
        root.select(index, pane === "" ? undefined : pane);
        if (root.carrying) root.drop();
        else root.activate();
    }

    footer_text: root.help_open ? "? back · Esc back · q close"
        : root.typing ? "Enter " + (root.carrying ? "drop here" : "go") + " · Tab/Down next · Shift+Tab/Up previous · Esc " + (root.from_search && root.query === "" ? "close" : "clear") + " · ? help"
        : root.swap_key !== "" ? "m swap · Enter swap · hjkl window · Esc cancel · ? help"
        : root.carrying ? "hjkl session · m drop · Enter drop · Esc cancel · ? help"
        : root.marks.length > 0 ? "Space mark · V mark all · m move " + root.marks.length + " · x kill " + root.marks.length + " · hjkl move · Esc clear marks · ? help"
        : "hjkl move · Ctrl+hjkl session · Tab pane · Enter go · m move · x kill · Space mark · / search · f view · ? help · q close"

    readonly property string normal_help: "h/j/k/l move between windows · Arrows move between windows · Ctrl+h/j/k/l or Ctrl+Arrows jump to the neighbouring session · Ctrl+1-9 jump to the nth session, Ctrl+0 the 10th · 1-9 select window by tmux index in this session, type 12 quickly for window 12 · Tab next pane · Shift+Tab previous pane · Enter go to window and pane · m pick up window, or every marked window · x kill window, or every marked window · Space/v mark or unmark window · V mark or unmark all in session · / search windows by name, command, path or session · f toggle filmstrip view · Click go to window or pane"
    readonly property string carry_help: "h/j/k/l choose target window or session · Arrows choose target · Ctrl+h/j/k/l jump to a session · Ctrl+1-9 target the nth session · m drop into the selected session, or swap with the selected window of the same session · Enter drop or swap · f toggle filmstrip view · Click drop or swap · Esc cancel, marks come back"
    help_text: root.typing ? "Type to search windows by name, pane command, pane path or session · Enter go to the highlighted window, or drop the carried window on its session · Tab/Down next match · Shift+Tab/Up previous match · Backspace delete, clears when empty · Esc clear search, or close when it is empty"
        : root.carrying ? root.carry_help
        : root.marks.length > 0 ? "Esc clear all marks · " + root.normal_help
        : root.query !== "" ? "Esc clear search · " + root.normal_help
        : root.normal_help

    status_text: {
        if (root.typing || root.query !== "") return "/" + root.query + (root.typing ? "_" : "") + "  " + root.match_count + " match" + (root.match_count === 1 ? "" : "es");
        if (root.swap_key !== "") return "SWAP window " + (root.tiles[root.tile_index_of[root.picked[0]]] || { index: "" }).index;
        if (root.carrying) return root.picked.length > 1 ? "MOVE " + root.picked.length + " windows" : "MOVE WINDOW " + (root.tiles[root.tile_index_of[root.picked[0]]] || { index: "" }).index;
        const tile = root.selected_tile;
        if (!tile) return root.loaded ? "no tmux sessions" : "";
        const n = tile.panes.length;
        return (root.marks.length > 0 ? root.marks.length + " marked · " : "") + tile.session_name + " · window " + tile.index + " · " + n + " pane" + (n === 1 ? "" : "s");
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

    Repeater {
        model: root.tile_slots

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
            visible: tile.rect.w > 0 && tile.x + tile.width > 0 && tile.x < root.body.width
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

    overlay: ScopeAim {
        anchors.fill: parent
        aim: root.help_open ? null : root.aim
        cls: root.aim ? root.aim.cls : ""
        place: root.aim ? root.aim.place : ""
        real: root.aim ? root.aim.real : null
        glide: Power.on_ac && root.reveal === 1
    }
}
