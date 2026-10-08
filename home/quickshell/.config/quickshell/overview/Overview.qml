// home/quickshell/.config/quickshell/overview/Overview.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../theme"
import "../services"
import "Layout.js" as Layout

// Every monitor's workspaces in one full-screen view on the focused monitor: pick, focus and move windows by key.
OverviewBase {
    id: root

    // Special workspaces instead of regular ones, until toggled back or the overview closes.
    property bool special: false
    // Special workspaces that keep a tile even when Hyprland has dropped them for being empty.
    readonly property var pinned_specials: ["scratchpad"]

    property string selected_address: ""
    property var monitor_slots: []
    // "follow" or "silent" while a carry opened from a bind ends with the overview closing after the drop.
    property string carry_exit: ""
    // Answering Screenshot's pending share request: only shareable windows show, and picking changes nothing.
    property bool share_mode: false
    // Choosing windows to save as a session: every window starts marked, and nothing can be moved or closed.
    property bool save_mode: false
    // The saved session whose windows the save replaces, or "" for a new one.
    property string save_target: ""
    // The name popup is open over the marking.
    property bool naming: false
    property bool save_pending: false
    property string name_error: ""
    // The selection when r handed off to the region selector, restored when Esc there comes back.
    property var share_resume: null
    // s: the selected tile's whole monitor is the pick, until s or Esc goes back to the same tile.
    property bool screen_pick: false

    readonly property var model: root.visible ? root.build(Hyprland.monitors.values, Hyprland.workspaces.values, Hyprland.toplevels.values, root.special, root.share_mode) : ({ groups: [], tiles: [] })
    groups: root.model.groups
    tiles: root.model.tiles

    // Closed windows drop out of marks and the carried set, even ones in the other mode.
    onTiles_synced: {
        const known = {};
        for (const t of Hyprland.toplevels.values) known[t.address] = true;
        if (root.tiles.length === 0) return;
        if (root.marks.some(a => !known[a])) root.marks = root.marks.filter(a => known[a]);
        if (root.picked.some(a => !known[a])) root.picked = root.picked.filter(a => known[a]);
    }

    readonly property var tab_order: root.selected_tile ? root.reading_order(root.selected_tile.windows) : []
    readonly property string current_address: root.tab_order.some(w => w.address === root.selected_address) ? root.selected_address : root.tab_order.length > 0 ? root.tab_order[0].address : ""
    readonly property var picked_toplevel: root.carrying ? WindowState.find(root.picked[0]) : null
    // One window carried inside its own workspace, selection on another window there: m/Enter swaps them.
    readonly property string swap_address: root.picked.length === 1 && !!root.selected_tile && root.selected_tile.windows.some(w => w.address === root.picked[0]) && root.current_address !== root.picked[0] ? root.current_address : ""
    readonly property bool can_drop: root.carrying && root.swap_address === "" && !!root.selected_tile && root.picked.some(a => !root.selected_tile.windows.some(w => w.address === a))
    ranked: root.typing ? root.rank(root.window_entries(), root.query) : []
    readonly property var matches: root.query === "" ? null : root.to_set(root.ranked.map(e => e.address))
    readonly property int save_total: WindowState.windows.filter(t => !!t.workspace).length
    readonly property int window_total: (root.tiles || []).reduce((n, t) => n + t.windows.length, 0)
    // The selected window's place among all windows, tile by tile.
    readonly property int window_at: {
        const tiles = root.tiles || [];
        let n = 0;
        for (let i = 0; i < Math.min(root.selected_index, tiles.length); i++) n += tiles[i].windows.length;
        const at = root.tab_order.findIndex(w => w.address === root.current_address);
        return at < 0 ? 0 : n + at + 1;
    }
    // The selected window (or the whole tile when empty) in body coordinates, for the scope skin.
    readonly property var aim: {
        const tile = root.selected_tile;
        const r = root.filmstrip ? root.layout.big : root.layout.tile_rects[root.selected_index];
        if (!tile) return null;
        const g = root.groups[tile.group];
        if (root.screen_pick) {
            const gr = root.layout.group_rects[tile.group];
            return g && gr && gr.w > 0 ? { x: gr.x, y: gr.y, w: gr.w, h: gr.h, cls: "SCREEN", place: g.name, real: { x: g.x, y: g.y, w: g.w, h: g.h } } : null;
        }
        if (!r || r.w <= 0) return null;
        const w = tile.windows.find(x => x.address === root.current_address);
        const place = (g ? g.name + " : " : "") + tile.name;
        if (!w) return { x: r.x, y: r.y, w: r.w, h: r.h, cls: tile.is_new ? "NEW" : "EMPTY", place: place, real: g ? { x: g.x, y: g.y, w: g.w, h: g.h } : null };
        const cw = r.w - 4;
        const ch = r.h - 4;
        return { x: r.x + 2 + w.rx * cw, y: r.y + 2 + w.ry * ch, w: Math.max(4, w.rw * cw), h: Math.max(4, w.rh * ch), cls: w.label.toUpperCase(), place: place, real: w.real };
    }

    layer_namespace: "quickshell-overview"
    title: root.save_mode ? "SAVE SESSION" : root.share_mode ? "SHARE" : root.special ? "SPECIAL" : "OVERVIEW"
    status_accent: root.screen_pick || root.carrying || root.marks.length > 0 || root.query !== ""
    help_close_desc: root.share_mode ? "cancel share" : root.save_mode ? "close without saving" : "close overview"
    cursor_sub: root.current_address
    group_label: (g, i) => g.name + (g.focused ? " · focused" : "")
    dismiss: () => root.hide_overview()

    // Exclusive focus alone still lets Hyprland run binds; this skips them all so a share pick moves nothing.
    ShortcutInhibitor {
        window: root
        enabled: root.share_mode || root.save_mode
    }

    Connections {
        target: Screenshot

        function onShare_requested(resume) {
            root.show_overview(resume ? "share_resume" : "share", false);
        }

        function onSharingChanged() {
            if (!Screenshot.sharing && root.share_mode) root.hide_overview(true);
        }
    }

    Connections {
        target: SessionStore

        function onSave_requested(target) {
            root.save_target = target;
            root.show_overview("save", false);
        }

        function onSaved(name) {
            if (!root.save_pending) return;
            root.save_pending = false;
            root.hide_overview();
            settings_timer.name = name;
            settings_timer.restart();
        }

        function onFailed(message) {
            if (!root.save_pending) return;
            root.save_pending = false;
            root.name_error = message;
        }
    }

    IpcHandler {
        target: "overview"

        // Marks every window to save as a session; `target_name` is a saved session to replace, or empty for a new one.
        function save_session(target_name: string): string {
            root.save_target = target_name;
            root.show_overview("save", false);
            return "ok";
        }

        function open(): string {
            root.show_overview("", false);
            return "ok";
        }

        function close(): string {
            root.hide_overview();
            return "ok";
        }

        function search(): string {
            root.show_overview("search", false);
            return "ok";
        }

        function move_follow(): string {
            root.show_overview("move", true);
            return "ok";
        }

        function move_silent(): string {
            root.show_overview("move", false);
            return "ok";
        }

        function toggle(): string {
            if (root.wanted) root.hide_overview();
            else root.show_overview("", false);
            return "ok";
        }
    }

    // entry "share" or "share_resume" takes over an open overview, since the request must be answered.
    function show_overview(entry, follow) {
        const sharing = entry === "share" || entry === "share_resume";
        const saving = entry === "save";
        if (sharing && !Screenshot.sharing) return;
        if (saving && Screenshot.sharing) return;
        if (root.wanted && !sharing && !saving) return;
        const mon = root.hold_focused_screen();
        root.refresh();
        slots_proc.running = true;
        root.filmstrip = false;
        const active_ws = Hyprland.activeToplevel ? Hyprland.activeToplevel.workspace : null;
        const on_special = mon ? root.shown_special(mon) || (active_ws && (active_ws.name || "").startsWith("special:") ? active_ws.name : "") : "";
        const resume = entry === "share_resume" ? root.share_resume : null;
        root.share_mode = sharing;
        root.save_mode = saving;
        root.naming = false;
        root.save_pending = false;
        root.name_error = "";
        if (sharing) root.share_resume = null;
        root.special = resume ? resume.special : on_special !== "" && !sharing;
        root.screen_pick = !!resume && resume.screen_pick;
        root.carry_exit = "";
        root.reset_common();
        const ws = Hyprland.focusedWorkspace;
        root.selected_key = root.special ? "sp:" + on_special.slice(8) : ws ? "ws:" + ws.id : "";
        root.selected_address = WindowState.active_address;
        if (resume) {
            root.filmstrip = resume.filmstrip;
            root.selected_key = resume.key;
            root.selected_address = resume.address;
        }
        root.wanted = true;
        root.visible = true;
        if (resume && root.tile_index_of[resume.key] === undefined) root.select_focused_workspace();
        root.reveal_open();
        if (saving) {
            root.marks = WindowState.windows.filter(t => !!t.workspace).map(t => t.address);
        } else if (entry === "search") {
            root.start_filter(true);
        } else if (entry === "move" && WindowState.find(WindowState.active_address)) {
            root.picked = [WindowState.active_address];
            root.picked_from_marks = false;
            root.carry_exit = follow ? "follow" : "silent";
        }
    }

    // Leaving share mode answers the request with a cancel unless keep_share; it hides at once so no
    // thumbnail capture outlives the pick.
    function hide_overview(keep_share) {
        if (!root.wanted) return;
        const was_sharing = root.share_mode;
        root.wanted = false;
        root.share_mode = false;
        root.save_mode = false;
        root.naming = false;
        root.save_pending = false;
        root.screen_pick = false;
        root.conceal(was_sharing);
        if (was_sharing && !keep_share) Screenshot.send_share("");
    }

    function refresh() {
        WindowState.refresh();
        Hyprland.refreshMonitors();
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
            cls: WindowState.class_of(t),
            real: full ? { x: g.x, y: g.y, w: g.w, h: g.h } : { x: at[0], y: at[1], w: size[0], h: size[1] }
        };
    }

    // Monitors with their workspaces in id order, then a fresh workspace slot; special mode lists only special workspaces.
    // Share mode keeps only the windows XDPH can share and drops the fresh slots.
    function build(monitors, workspaces, toplevels, special, share) {
        const groups = [];
        const tiles = [];
        const used = {};
        for (const w of workspaces) used[w.id] = true;
        for (const m of monitors) {
            const size = root.logical_size(m);
            const g = { name: m.name, monitor: m, x: m.x, y: m.y, w: size.w, h: size.h, tiles: [], focused: m.focused };
            const owns = w => w.monitor === m || (!w.monitor && m.focused);
            const list = workspaces.filter(w => owns(w) && (w.name || "").startsWith("special:") === special).sort((a, b) => a.id - b.id);
            const shown_special = root.shown_special(m);
            for (const w of list) {
                const wins = toplevels.filter(t => t.workspace === w && (!share || Screenshot.share_id_of(t.address) !== "")).map(t => root.window_entry(t, g));
                wins.sort((a, b) => (a.floating ? 1 : 0) - (b.floating ? 1 : 0));
                g.tiles.push(tiles.length);
                const name = special ? w.name.slice(8) : w.name || String(w.id);
                const shown = special ? shown_special === w.name : m.activeWorkspace === w;
                tiles.push({ key: (special ? "sp:" + name : "ws:" + w.id), id: w.id, name: name, ws: w, group: groups.length, is_new: false, focused: w.focused, shown_on_monitor: shown, windows: wins });
            }
            if (special) {
                for (const name of m.focused && !share ? root.pinned_specials : []) {
                    if (workspaces.some(w => w.name === "special:" + name)) continue;
                    g.tiles.push(tiles.length);
                    tiles.push({ key: "sp:" + name, id: 0, name: name, ws: null, group: groups.length, is_new: true, focused: false, shown_on_monitor: false, windows: [] });
                }
                if (g.tiles.length > 0) groups.push(g);
                continue;
            }
            if (share) {
                groups.push(g);
                continue;
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

    function clean_title(title, short_class) {
        let t = title || "";
        if (short_class.toLowerCase() === "firefox") t = t.replace(/^XXX\s*/, "");
        const m = /\s+[—-]\s+([^—-]+)$/.exec(t);
        const app = short_class.toLowerCase();
        return m && app !== "" && m[1].trim().toLowerCase().split(/\s+/).pop() === app ? t.slice(0, m.index) : t;
    }

    // Every window, most recent first, minus the carried ones and, in share mode, the unshareable ones.
    function window_entries() {
        const out = [];
        WindowState.windows.forEach((t, recency) => {
            if (!t.workspace || root.picked_set[t.address]) return;
            if (root.share_mode && Screenshot.share_id_of(t.address) === "") return;
            const ipc = t.lastIpcObject || {};
            const short = WindowState.short_class(t);
            const ws_name = t.workspace.name || "";
            const title = root.clean_title(t.title, short);
            out.push({
                address: t.address,
                toplevel: t,
                recency: recency,
                label: short || "window",
                title: title,
                ws_name: ws_name,
                ws_id: t.workspace.id,
                place: ws_name.replace(/^special:/, "special "),
                description: ws_name + " · " + title,
                keywords: [WindowState.class_of(t), ipc.initialClass || "", ws_name, t.title || ""]
            });
        });
        return out;
    }

    // Puts the tile selection on the window, switching between regular and special mode when it lives in the other one.
    select_entry: function (entry) {
        if (!entry) return;
        const is_special = entry.ws_name.startsWith("special:");
        if (is_special !== root.special) {
            root.special = is_special;
            root.stop_digits();
        }
        const at = root.tile_index_of[is_special ? "sp:" + entry.ws_name.slice(8) : "ws:" + entry.ws_id];
        if (at !== undefined) root.select(at, entry.address);
    }

    // An empty query starts on the window before the current one when searching, else on the selected window.
    reset_hit: function () {
        const list = root.ranked;
        let at = 0;
        if (root.query === "") at = root.from_search ? (list.length >= 2 && list[0].address === WindowState.active_address ? 1 : 0) : Math.max(0, list.findIndex(e => e.address === root.current_address));
        root.set_hit(at);
    }

    accept_hit: function () {
        const entry = root.hit_entry;
        if (!entry) return;
        root.select_entry(entry);
        root.clear_filter();
        if (root.share_mode) root.share_window(entry.address);
        else if (root.carrying) root.drop();
        else root.activate_address(entry.address);
    }

    select: function (index, address) {
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

    filmstrip_vertical: function (dy) {
        const from = root.selected_index;
        let to = -1;
        const band_order = Layout.flat(Layout.bands(root.groups));
        const tile = root.tiles[from];
        const g = band_order.indexOf(tile.group) + dy;
        if (g >= 0 && g < band_order.length) {
            const target = root.groups[band_order[g]].tiles;
            to = target[Math.min(root.groups[tile.group].tiles.indexOf(from), target.length - 1)];
        }
        if (to !== undefined && to >= 0) root.select(to);
    }

    // Lands on the workspace the neighbouring monitor shows, or its first tile.
    function move_monitor(dx, dy) {
        const tile = root.selected_tile;
        if (!tile) return;
        const to = Layout.neighbor(root.groups, tile.group, dx, dy);
        if (to < 0) return;
        const target = root.groups[to].tiles;
        root.select(target.find(i => root.tiles[i].shown_on_monitor) ?? target[0]);
    }

    // Slot n is the monitor SUPER+CTRL+n focuses.
    function jump_monitor(slot) {
        const g = root.groups.findIndex(g => g.name === root.monitor_slots[slot - 1]);
        if (g < 0) return;
        const target = root.groups[g].tiles;
        root.select(target.find(i => root.tiles[i].shown_on_monitor) ?? target[0]);
    }

    function cycle_window(delta) {
        const order = root.tab_order;
        if (order.length === 0) return;
        const at = order.findIndex(w => w.address === root.current_address);
        root.selected_address = order[(at + delta + order.length) % order.length].address;
    }

    // Special mode has no usable ids, so digits count tiles in hjkl order there.
    jump: function (id) {
        const i = root.special ? (id >= 1 && id <= root.nav_order.length ? root.nav_order[id - 1] : -1) : root.tiles.findIndex(t => !t.is_new && t.id === id);
        if (i >= 0) root.select(i);
        return i >= 0;
    }

    function shown_special(monitor) {
        return ((monitor.lastIpcObject || {}).specialWorkspace || {}).name || "";
    }

    function quoted(text) {
        return "'" + text.replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'";
    }

    function focus_workspace(tile) {
        if (root.special) {
            if (tile.shown_on_monitor) return;
            special_timer.name = tile.name;
            special_timer.restart();
            return;
        }
        if (tile.is_new) {
            const g = root.groups[tile.group];
            Hyprland.dispatch("hl.dsp.focus({ monitor = '" + g.name + "' })");
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + tile.id + " })");
            return;
        }
        const target = WindowState.workspace_selector(tile.id);
        if (target !== "") Hyprland.dispatch("hl.dsp.focus({ workspace = " + target + " })");
    }

    // Selection lands on the active window's workspace when shown, else the first tile.
    // Regular workspaces, on the focused one: where a share pick lands when its tile or special list is gone.
    function select_focused_workspace() {
        root.special = false;
        const ws = Hyprland.focusedWorkspace;
        root.selected_key = ws ? "ws:" + ws.id : "";
    }

    function toggle_special() {
        root.special = !root.special;
        root.stop_digits();
        const here = root.tiles.findIndex(t => t.windows.some(w => w.address === WindowState.active_address));
        if (here >= 0) {
            root.select(here, WindowState.active_address);
        } else if (root.special) {
            if (root.nav_order.length > 0) root.select(root.nav_order[0]);
        } else {
            const ws = Hyprland.focusedWorkspace;
            root.selected_key = ws ? "ws:" + ws.id : "";
        }
    }

    activate: function () {
        const tile = root.selected_tile;
        if (!tile) return;
        const address = root.current_address;
        if (address === "") {
            root.focus_workspace(tile);
            root.hide_overview();
            return;
        }
        root.activate_address(address);
    }

    function activate_address(address) {
        // The first focus warps the cursor onto the window, so follow_mouse lands there when the overview unmaps.
        WindowState.focus(address);
        root.hide_overview();
        root.focus_later(address);
    }

    function share_window(address) {
        const id = Screenshot.share_id_of(address);
        if (id === "") return;
        root.hide_overview(true);
        Screenshot.send_share("window:" + id);
    }

    // The selected workspace's monitor, whole with s or a region of it with r.
    function share_monitor(region) {
        const g = root.selected_tile ? root.groups[root.selected_tile.group] : null;
        if (!g) return;
        if (region) root.share_resume = { key: root.selected_key, address: root.current_address, filmstrip: root.filmstrip, special: root.special, screen_pick: root.screen_pick };
        root.hide_overview(true);
        if (region) Screenshot.share_region(g.name);
        else Screenshot.send_share("screen:" + g.name);
    }

    // The picked monitor: shared, or the carried windows dropped on its visible workspace, or focused.
    function screen_confirm(drop_only) {
        const g = root.selected_tile ? root.groups[root.selected_tile.group] : null;
        if (!g) return;
        if (root.share_mode) return root.share_monitor(false);
        if (!root.carrying) {
            if (drop_only) return;
            Hyprland.dispatch("hl.dsp.focus({ monitor = '" + g.name + "' })");
            root.hide_overview();
            monitor_timer.name = g.name;
            monitor_timer.restart();
            return;
        }
        root.screen_pick = false;
        root.special = false;
        const group = root.groups.find(x => x.name === g.name);
        const at = group ? group.tiles.find(i => root.tiles[i].shown_on_monitor) : undefined;
        if (at === undefined) return;
        root.select(at, root.picked[0]);
        root.drop();
    }

    // Directions step between monitors; ?, f and q fall through to the usual handling, the rest is swallowed.
    function handle_screen_key(event) {
        const k = event.key;
        const dir = root.direction_of(k);
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            ThemeAudio.play("confirm");
            root.screen_confirm(false);
        } else if (k === Qt.Key_M && root.carrying) {
            ThemeAudio.play("confirm");
            root.screen_confirm(true);
        } else if (k === Qt.Key_R && root.share_mode) {
            ThemeAudio.play("confirm");
            root.share_monitor(true);
        } else if (k === Qt.Key_Escape || k === Qt.Key_S) {
            ThemeAudio.play("cancel");
            root.screen_pick = false;
        } else if (dir) {
            const before = root.cursor_key();
            root.move_monitor(dir[0], dir[1]);
            root.play_if_moved(before);
        } else if (root.is_help_key(event) || k === Qt.Key_F || k === Qt.Key_Q) {
            return false;
        }
        return true;
    }

    // A click on the picked monitor confirms it; a click on another monitor moves the pick there.
    function screen_clicked(group, index) {
        const g = root.groups[group];
        if (!g) return;
        if (root.selected_tile && root.selected_tile.group === group) {
            ThemeAudio.play("confirm");
            root.screen_confirm(false);
            return;
        }
        ThemeAudio.play("cursor");
        root.select(index ?? g.tiles.find(i => root.tiles[i].shown_on_monitor) ?? g.tiles[0]);
    }

    function handle_share_key(event) {
        const k = event.key;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (root.current_address === "") return true;
            ThemeAudio.play("confirm");
            root.share_window(root.current_address);
        } else if (k === Qt.Key_R) {
            ThemeAudio.play("confirm");
            root.share_monitor(true);
        } else if (k !== Qt.Key_M && k !== Qt.Key_X && k !== Qt.Key_V && k !== Qt.Key_Space) {
            return false;
        }
        return true;
    }

    function start_naming() {
        if (root.alive(root.marks).length === 0) return;
        root.naming = true;
        root.name_error = "";
        name_input.text = root.save_target !== "" ? root.save_target : SessionStore.default_name();
        name_input.forceActiveFocus();
        name_input.selectAll();
    }

    function stop_naming() {
        // The popup field is inside a focus scope: unless it gives up its scoped focus, focus_keys hands it straight back and keys go nowhere.
        name_input.focus = false;
        root.naming = false;
        root.name_error = "";
        root.focus_keys();
    }

    function confirm_save() {
        const name = name_input.text.trim();
        const problem = SessionStore.name_problem(name, root.save_target);
        if (root.save_pending) return;
        if (problem !== "") {
            root.name_error = problem;
            return;
        }
        root.save_pending = true;
        root.name_error = "";
        SessionStore.save_capture(root.alive(root.marks), name, root.save_target);
    }

    // Marking keys pass through to the shared handling; anything that would move, close or focus a window is swallowed.
    function handle_save_key(event) {
        const k = event.key;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            ThemeAudio.play("confirm");
            root.start_naming();
        } else if (k === Qt.Key_Escape) {
            ThemeAudio.play("cancel");
            root.hide_overview();
        } else if (k !== Qt.Key_M && k !== Qt.Key_X && k !== Qt.Key_S && k !== Qt.Key_Slash && event.text !== "/") {
            return false;
        }
        return true;
    }

    function alive(list) {
        return list.filter(a => WindowState.find(a) !== null);
    }

    function mark_address(a) {
        if (a === "") return;
        root.marks = root.marks.indexOf(a) >= 0 ? root.marks.filter(m => m !== a) : root.marks.concat([a]);
    }

    toggle_mark: function () {
        root.mark_address(root.current_address);
    }

    // Marks every window in the selected workspace, or unmarks them all when they already are.
    toggle_mark_all: function () {
        const here = root.tab_order.map(w => w.address);
        if (here.length === 0) return;
        const all = here.every(a => root.marks.indexOf(a) >= 0);
        root.marks = all ? root.marks.filter(m => here.indexOf(m) < 0) : root.marks.concat(here.filter(a => root.marks.indexOf(a) < 0));
    }

    // Closes every marked window, or the selected one; selection steps to the next window.
    close_selected: function () {
        const marked = root.alive(root.marks);
        const doomed = marked.length > 0 ? marked : root.current_address !== "" ? [root.current_address] : [];
        if (doomed.length === 0) return;
        const at = root.tab_order.findIndex(w => w.address === root.current_address);
        const left = root.tab_order.filter(w => doomed.indexOf(w.address) < 0);
        const next = left.find(w => root.tab_order.indexOf(w) > at) || left[left.length - 1];
        root.selected_address = next ? next.address : "";
        root.marks = [];
        for (const a of doomed) WindowState.close(a);
        refresh_timer.restart();
    }

    pick: function () {
        const marked = root.alive(root.marks);
        if (marked.length > 0) {
            root.picked = marked;
            root.picked_from_marks = true;
            root.marks = [];
            root.carry_exit = "";
        } else if (root.current_address !== "") {
            root.picked = [root.current_address];
            root.picked_from_marks = false;
            root.carry_exit = "";
        }
    }

    cancel_pick: function () {
        root.carry_exit = "";
        if (root.picked_from_marks) root.marks = root.alive(root.picked);
        root.picked = [];
    }

    // Swaps inside a workspace, else moves every carried window there; a fresh slot is then sent to its monitor.
    drop: function () {
        const tile = root.selected_tile;
        const carried = root.alive(root.picked);
        const swap_with = root.swap_address;
        const moving = tile ? carried.filter(a => !tile.windows.some(w => w.address === a)) : [];
        if (swap_with === "" && moving.length === 0) {
            root.cancel_pick();
            return;
        }
        root.picked = [];
        const exit = root.carry_exit;
        root.carry_exit = "";
        if (swap_with !== "") {
            WindowState.swap(carried[0], swap_with);
            root.selected_address = carried[0];
            refresh_timer.restart();
            if (exit !== "") root.hide_overview();
            return;
        }
        for (const a of moving) {
            if (root.special) Hyprland.dispatch("hl.dsp.window.move({ window = " + WindowState.selector(a) + ", workspace = " + root.quoted("special:" + tile.name) + ", follow = false })");
            else WindowState.move_to_workspace(a, tile.id, false);
        }
        if (tile.is_new && !root.special) Hyprland.dispatch("hl.dsp.workspace.move({ workspace = " + tile.id + ", monitor = '" + root.groups[tile.group].name + "' })");
        root.selected_key = root.special ? tile.key : "ws:" + tile.id;
        root.selected_address = moving[0];
        refresh_timer.restart();
        if (exit === "") return;
        root.hide_overview();
        if (exit === "follow") root.focus_later(moving[0]);
    }

    pre_key: function (event) {
        const before = root.cursor_key();
        const k = event.key;
        if (event.modifiers & Qt.ControlModifier) {
            const dir = root.direction_of(k);
            if (dir) root.move_monitor(dir[0], dir[1]);
            else if (k >= Qt.Key_0 && k <= Qt.Key_9) root.jump_monitor(k === Qt.Key_0 ? 10 : k - Qt.Key_0);
            else return "stop";
            root.play_if_moved(before);
            return "done";
        }
        if (root.screen_pick && root.handle_screen_key(event)) return "done";
        if (root.share_mode && root.handle_share_key(event)) return "done";
        if (root.save_mode && root.handle_save_key(event)) return "done";
        return "";
    }

    extra_key: function (event, before) {
        const k = event.key;
        if (k === Qt.Key_BracketRight || k === Qt.Key_BracketLeft) {
            root.cycle_window(k === Qt.Key_BracketRight ? 1 : -1);
            root.play_if_moved(before);
        } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            root.toggle_special();
            if (root.special && root.tiles.length === 0) root.select_focused_workspace();
            root.play_if_moved(before);
        } else if (k === Qt.Key_S) {
            ThemeAudio.play("cursor");
            root.screen_pick = true;
        } else {
            return false;
        }
        return true;
    }

    // A click on a tile's background focuses the workspace itself rather than one of its windows.
    // In share mode a window click shares it and a background click only selects.
    function tile_clicked(index, address) {
        if (root.save_mode) {
            ThemeAudio.play(address === "" ? "cursor" : "confirm");
            root.select(index, address);
            root.mark_address(address);
            return;
        }
        if (root.screen_pick) return root.screen_clicked(root.tiles[index] ? root.tiles[index].group : -1, index);
        ThemeAudio.play(root.share_mode && address === "" ? "cursor" : "confirm");
        root.select(index, address);
        if (root.share_mode) {
            if (address !== "") root.share_window(address);
        } else if (root.carrying) {
            root.drop();
        } else if (address === "" && root.selected_tile) {
            root.focus_workspace(root.selected_tile);
            root.hide_overview();
        } else {
            root.activate();
        }
    }

    footer_text: root.help_open ? "? back · Esc back · q " + (root.share_mode ? "cancel share" : root.save_mode ? "close without saving" : "close")
        : root.save_mode ? (root.naming ? "Enter save · Esc back to marking" : "Space mark · V mark all here · Enter name and save · hjkl move · ]/[ window · Tab special · f view · ? help · Esc cancel")
        : root.typing ? "Enter " + (root.share_mode ? "share" : root.carrying ? "drop here" : "focus") + " · Tab/Down next · Shift+Tab/Up previous · Esc " + (root.from_search && root.query === "" ? "close" : "clear") + " · ? help"
        : root.screen_pick ? (root.share_mode ? "Enter share screen · hjkl/Ctrl+hjkl/Ctrl+1-9 monitor · r region · s/Esc back · f view · ? help · q cancel"
            : (root.carrying ? "m/Enter drop on screen" : "Enter focus screen") + " · hjkl/Ctrl+hjkl/Ctrl+1-9 monitor · s/Esc back · f view · ? help · q close")
        : root.share_mode ? "hjkl move · Ctrl+hjkl/1-9 monitor · ]/[ window · Enter share window · s screen · r region · Tab special · / search · f view · ? help · Esc cancel"
        : root.swap_address !== "" ? "m swap · Enter swap · ]/[ other window · hjkl workspace · Esc cancel · ? help"
        : root.carrying ? "hjkl workspace · Ctrl+hjkl/1-9 monitor · ]/[ window · s screen · Tab special · m drop · Enter drop · Esc cancel · ? help"
        : root.marks.length > 0 ? "Space mark · V mark all · m move " + root.marks.length + " · x close " + root.marks.length + " · hjkl move · Esc clear marks · ? help"
        : "hjkl move · Ctrl+hjkl/1-9 monitor · ]/[ window · Enter focus · m move · x close · Space mark · / search · f view · s screen · Tab special · ? help · q close"

    readonly property string normal_help: "h/j/k/l move between workspaces · Arrows move between workspaces · Ctrl+h/j/k/l or Ctrl+Arrows jump to the next monitor that way · Ctrl+1-9 jump to that monitor number, as SUPER+Ctrl+1-9 counts them · ] next window · [ previous window · Enter focus window, or the workspace if empty · m pick up window, or every marked window · x close window, or every marked window · Space/v mark or unmark window · V mark or unmark all in workspace · / search windows by class, title or workspace · 1-9 select workspace by id, type 12 quickly for workspace 12, or the nth special workspace · s pick the whole monitor of the selected workspace, Enter then focuses it · Tab/Shift+Tab toggle special workspaces · f toggle filmstrip view, j/k there jump monitors · Click focus window or workspace"
    readonly property string carry_help: "h/j/k/l choose target workspace · Arrows choose target workspace · Ctrl+h/j/k/l choose target monitor · Ctrl+1-9 target monitor by number · 1-9 target workspace by id, type 12 quickly for workspace 12 · Tab/Shift+Tab toggle special workspaces · s pick a whole monitor, m/Enter then drop on its visible workspace · ]/[ choose a window in the same workspace to swap with ·m drop there, or swap with the SWAP window · Enter drop there, or swap · f toggle filmstrip view · Click drop on workspace · Esc cancel, marks come back"
    readonly property string screen_moves: "h/j/k/l, Arrows, Ctrl+h/j/k/l or Ctrl+Arrows pick the next monitor that way · Ctrl+1-9 pick that monitor number"
    readonly property string screen_help: root.share_mode ? "The whole monitor is the pick · Enter share it · Click share it, or click another monitor to pick that one · " + root.screen_moves + " · r share a region of this monitor instead, Esc there comes back here · s/Esc back to window selection · f toggle filmstrip view · q cancel the share"
        : "The whole monitor is the pick · " + (root.carrying ? "m/Enter drop the carried windows on its visible workspace · Click drop them there" : "Enter focus it and close · Click focus it") + ", or click another monitor to pick that one · " + root.screen_moves + " · s/Esc back to the selected workspace · f toggle filmstrip view · q close"
    readonly property string save_help: "Every window starts marked, and Enter saves the marked ones as a session · Space/v mark or unmark window · V mark or unmark all in workspace · Enter name the session, then Enter again to save it · Nothing is moved, closed or focused here · h/j/k/l move between workspaces · Arrows move between workspaces · Ctrl+h/j/k/l or Ctrl+Arrows jump to the next monitor that way · Ctrl+1-9 jump to that monitor number · ] next window · [ previous window · 1-9 select workspace by id, or the nth special workspace · Tab/Shift+Tab toggle special workspaces · f toggle filmstrip view · Click mark or unmark window · Esc/q close without saving"
    readonly property string share_help: "Only windows the share can capture are shown · h/j/k/l move between workspaces · Arrows move between workspaces · Ctrl+h/j/k/l or Ctrl+Arrows jump to the next monitor that way · Ctrl+1-9 jump to that monitor number · ] next window · [ previous window · Enter share the selected window · Click share a window · s pick the whole monitor of the selected workspace, Enter then shares it · r share a region of that monitor, Esc there comes back here · Tab/Shift+Tab toggle special workspaces ·/ search shareable windows by class, title or workspace · 1-9 select workspace by id, or the nth special workspace · f toggle filmstrip view, j/k there jump monitors · Esc/q cancel the share"
    help_text: root.save_mode ? root.save_help
        : root.typing ? "Type to search " + (root.share_mode ? "shareable " : "") + "windows by class, title or workspace · Enter " + (root.share_mode ? "share the highlighted window" : "focus the highlighted window, or drop the carried window on its workspace") + " · Tab/Down next match · Shift+Tab/Up previous match · Backspace delete, clears when empty · Esc clear search, or close when it is empty"
        : root.screen_pick ? root.screen_help
        : root.share_mode ? (root.query !== "" ? "Esc clear search · " : "") + root.share_help
        : root.carrying ? root.carry_help
        : root.marks.length > 0 ? "Esc clear all marks · " + root.normal_help
        : root.query !== "" ? "Esc clear search · " + root.normal_help
        : root.normal_help

    status_text: {
        if (root.typing || root.query !== "") return "/" + root.query + (root.typing ? "_" : "") + "  " + root.match_count + " match" + (root.match_count === 1 ? "" : "es");
        if (root.save_mode) return (root.save_target !== "" ? "UPDATE " + root.save_target.toUpperCase() : "SAVE SESSION") + " · " + root.marks.length + " of " + root.save_total + " windows marked";
        const lead = root.picked_toplevel ? WindowState.short_class(root.picked_toplevel) : "window";
        const picked_tile = root.selected_tile;
        if (root.screen_pick && picked_tile && root.groups[picked_tile.group]) return (root.carrying ? "MOVE " + (root.picked.length > 1 ? root.picked.length + " windows" : lead.toUpperCase()) + " to " : "SCREEN ") + root.groups[picked_tile.group].name + " · whole monitor";
        if (root.swap_address !== "") {
            const other = WindowState.find(root.swap_address);
            return ("SWAP " + lead + " with " + (other ? WindowState.short_class(other) : "window")).toUpperCase();
        }
        if (root.carrying) return root.picked.length > 1 ? "MOVE " + root.picked.length + " windows" : "MOVE " + lead.toUpperCase();
        const tile = root.selected_tile;
        if (!tile) return root.special ? "no special workspaces" : "";
        const mon = root.groups[tile.group] ? root.groups[tile.group].name : "";
        return (root.marks.length > 0 ? root.marks.length + " marked · " : "") + mon + " · " + (tile.is_new ? (root.special ? "empty special " : "new workspace ") + tile.name : (root.special ? "special " : "workspace ") + tile.name + " · " + tile.windows.length + " window" + (tile.windows.length === 1 ? "" : "s"));
    }

    // Hyprland owns the slot order, and hyprctl eval prints nothing back, so the slots go through a file.
    Process {
        id: slots_proc
        command: ["sh", "-c", "f=\"$XDG_RUNTIME_DIR/qs-monitor-slots\"; hyprctl eval \"local W = require('lib.workspaces'); local t = {}; for i = 1, 10 do t[i] = W.get_monitor_for_slot(i) or '-' end; local f = io.open('$f', 'w'); f:write(table.concat(t, ' ')); f:close()\" >/dev/null && cat \"$f\""]
        stdout: StdioCollector {
            onStreamFinished: root.monitor_slots = text.trim().split(/\s+/)
        }
    }

    // Opens Settings once the overview has dropped its exclusive keyboard grab.
    Timer {
        id: settings_timer
        property string name: ""
        interval: 80
        onTriggered: {
            SettingsNav.requested_session = settings_timer.name;
            SettingsNav.open("sessions");
        }
    }

    Timer {
        id: refresh_timer
        interval: 120
        onTriggered: root.refresh()
    }

    // Focus waits for the overview to drop its exclusive keyboard grab, else the grab's release restores the old window.
    Timer {
        id: special_timer
        property string name: ""
        interval: 60
        onTriggered: Hyprland.dispatch("hl.dsp.workspace.toggle_special(" + root.quoted(special_timer.name) + ")")
    }

    Timer {
        id: monitor_timer
        property string name: ""
        interval: 60
        onTriggered: Hyprland.dispatch("hl.dsp.focus({ monitor = '" + monitor_timer.name + "' })")
    }

    Connections {
        target: Hyprland
        enabled: root.visible

        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode", "fullscreen", "monitoradded", "monitorremoved", "moveworkspace", "moveworkspacev2"].indexOf(event.name) >= 0) refresh_timer.restart();
        }
    }

    under_tiles: Repeater {
        model: root.groups

        Item {
            id: group
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

            // The screen pick: the whole monitor framed like a selected window.
            Rectangle {
                visible: root.screen_pick && group.holds_selection
                anchors.fill: parent
                radius: Style.radius(8)
                color: Qt.alpha(Style.caret_color, 0.08)
                border.width: 2
                border.color: Style.caret_color

                CornerBrackets {
                    anchors.fill: parent
                    color: Style.selection_brackets
                    inset: 3
                    arm: Math.min(16, parent.width / 4)
                    all_corners: true
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.screen_pick
                onClicked: root.screen_clicked(group.index)
            }
        }
    }

    Repeater {
        model: root.tile_slots

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
            visible: tile.rect.w > 0 && tile.x + tile.width > 0 && tile.x < root.body.width
            entry: tile.modelData
            selected: tile.index === root.selected_index && !root.screen_pick
            selected_address: root.screen_pick ? "" : root.current_address
            picked: root.picked_set
            picked_toplevel: root.picked_toplevel
            picked_count: root.picked.length
            marks: root.mark_numbers
            swap_address: tile.selected ? root.swap_address : ""
            drop_target: tile.selected && root.can_drop
            matches: root.matches
            shown: root.visible
            live: tile.index === root.selected_index && !root.filmstrip

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
        selected: !root.screen_pick
        selected_address: root.screen_pick ? "" : root.current_address
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

    ScopeAim {
        anchors.fill: parent
        aim: root.help_open ? null : root.aim
        cls: root.aim ? root.aim.cls : ""
        place: root.aim ? root.aim.place : ""
        real: root.aim ? root.aim.real : null
        glide: Power.on_ac && root.reveal === 1
    }

    AmmoCounter {
        visible: Style.ammo_counter && root.window_total > 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        index: root.window_at
        total: root.window_total
    }

    LockAim {
        anchors.fill: parent
        aim: root.help_open ? null : root.aim
        animate: Power.on_ac && root.reveal === 1
    }

    // Names the session being saved; Enter saves and Esc goes back to marking.
    Item {
        id: name_popup
        visible: root.naming
        anchors.fill: parent
        z: 20

        MouseArea {
            anchors.fill: parent
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.bg_crust, 0.6)
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.px(40), Style.px(440))
            height: name_column.implicitHeight + Style.px(28)
            radius: Style.radius(8)
            color: Theme.bg_mantle
            border.width: 1
            border.color: Style.caret_color

            Column {
                id: name_column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.px(14)
                spacing: Style.px(8)

                Text {
                    text: root.save_target !== "" ? "Update session" : "Name this session"
                    color: Style.text_primary
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-1)
                }

                Rectangle {
                    width: parent.width
                    height: Style.px(30)
                    radius: 6
                    color: "transparent"
                    border.width: 1
                    border.color: root.name_error !== "" ? Style.text_primary : Style.text_accent

                    TextInput {
                        id: name_input
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        maximumLength: 64
                        clip: true
                        color: Style.text_fg
                        selectionColor: Style.selection_bg
                        selectedTextColor: Style.selection_inverse ? Style.selection_fg : Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size
                        onTextEdited: root.name_error = ""

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                ThemeAudio.play("cancel");
                                root.stop_naming();
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                ThemeAudio.play("confirm");
                                root.confirm_save();
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_U) {
                                name_input.text = "";
                            } else {
                                return;
                            }
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: root.name_error !== "" ? root.name_error : root.save_pending ? "Saving..." : root.marks.length + " window" + (root.marks.length === 1 ? "" : "s") + " · Enter save · Esc back to marking"
                    wrapMode: Text.WordWrap
                    color: root.name_error !== "" ? Style.text_primary : Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                }
            }
        }
    }
}
