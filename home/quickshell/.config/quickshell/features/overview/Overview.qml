pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.core
import qs.ui.effects
import qs.ui.frames
import qs.ui.menu
import qs.theme
import qs.features.popups
import qs.features.popups.frames
import qs.features.bar
import qs.features.settings
import qs.features.screenshot
import "Layout.js" as Layout
import "Voice.js" as Voice
import "../../core/Fuzzy.js" as Fuzzy
import "../../core/WindowEntries.js" as WindowEntries
import qs.features.voice
import qs.features.audio
import qs.features.windows

// Every monitor's workspaces in one full-screen view on the focused monitor: pick, focus and move windows by key.
PanelWindow {
    id: root

    property bool wanted: false
    property string held_screen_name: ""
    // The filmstrip view instead of the mini-map, until the overview closes.
    property bool filmstrip: false
    property real reveal: 0

    property string selected_key: ""
    // Carried items, and the marks they came from so Esc can put them back.
    property var picked: []
    property bool picked_from_marks: false
    property var marks: []
    property bool typing: false
    property bool help_open: false
    property string query: ""
    property int hit: 0
    property bool from_search: false

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
    // w and W: the selected workspace is being sent to a monitor ("monitor", picked like s does) or swapped with another
    // ("swap"); ws_source is its tile key.
    property string ws_mode: ""
    property string ws_source: ""
    readonly property string ws_name: (root.tiles.find(t => t.key === root.ws_source) || { name: "" }).name
    onScreen_pickChanged: if (!root.screen_pick && root.ws_mode === "monitor") root.end_ws_mode()

    // Numbers show on every window while voxcmd has an overview voice session open.
    readonly property bool voice_on: VoxSessionState.active && VoxSessionState.kind === "overview"
    readonly property string voice_dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/voxcmd"
    // What voxcmd reads of this overview, rewritten whenever it changes; the shape is in `features/overview/README.md`.
    readonly property var voice_snapshot: root.wanted ? Voice.snapshot({ groups: root.groups, tiles: root.tiles, marks: root.marks, special: root.special, slots: root.monitor_slots, nav_order: root.nav_order }) : ({ version: 1, open: false })
    readonly property var window_numbers: Voice.window_numbers(root.voice_snapshot)
    onVoice_snapshotChanged: voice_write_timer.restart()
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.voice_dir])

    readonly property var model: root.visible ? root.build(Hyprland.monitors.values, Hyprland.workspaces.values, Hyprland.toplevels.values, root.special, root.share_mode) : ({ groups: [], tiles: [] })
    readonly property var groups: root.model.groups
    readonly property var tiles: root.model.tiles
    readonly property ListModel tile_slots: ListModel {}
    readonly property var tile_index_of: {
        const out = {};
        root.tiles.forEach((t, i) => out[t.key] = i);
        return out;
    }
    readonly property int selected_index: Math.max(0, root.tiles.findIndex(t => t.key === root.selected_key))
    readonly property var selected_tile: root.tiles[root.selected_index] || null
    readonly property bool carrying: root.picked.length > 0
    readonly property var picked_set: root.to_set(root.picked)
    readonly property var mark_numbers: {
        const out = {};
        root.marks.forEach((k, i) => out[k] = i + 1);
        return out;
    }
    readonly property var nav_order: Layout.flat(Layout.flat(Layout.bands(root.groups)).map(g => root.groups[g].tiles))

    readonly property var metrics: ({
        gap: Style.px(10),
        pad: Style.px(10),
        label: Style.fs(-3) + Style.px(12),
        group_gap: Style.px(22),
        strip: Style.px(150)
    })
    readonly property real list_width: root.typing ? Math.min(Style.px(460), frame.body.width * 0.34) : 0
    readonly property var layout: Layout.compute(root.filmstrip, root.groups, root.tiles, frame.body.width - root.list_width, frame.body.height, root.metrics, root.selected_index)
    readonly property bool animate_moves: root.filmstrip && PowerSource.on_ac && root.reveal === 1

    // Closed windows drop out of marks and the carried set, even ones in the other mode.
    onTilesChanged: {
        Layout.sync_keys(root.tile_slots, root.tiles.map(t => t.key));
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
    readonly property var ranked: root.typing ? root.rank(root.window_entries(), root.query) : []
    readonly property int hit_index: Math.min(root.hit, root.ranked.length - 1)
    readonly property var hit_entry: root.ranked[root.hit_index] || null
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
        target: Sessions

        function onSave_requested(target) {
            root.begin_save(target);
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

    // Opens in save mode; `target_name` is a saved session to replace, or empty for a new one.
    function begin_save(target_name) {
        root.save_target = target_name;
        root.show_overview("save", false);
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
        root.end_ws_mode();
        root.picked = [];
        root.from_search = false;
        root.marks = [];
        root.help_open = false;
        digit_timer.stop();
        root.clear_filter();
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
        root.end_ws_mode();
        root.conceal(was_sharing);
        if (was_sharing && !keep_share) Screenshot.send_share("");
    }

    function hold_focused_screen() {
        Popups.close();
        const mon = Hyprland.focusedMonitor;
        const target = (mon && Quickshell.screens.find(s => s.name === mon.name)) || Quickshell.screens[0];
        root.held_screen_name = target ? target.name : "";
        return mon;
    }

    function reveal_open() {
        reveal_anim.stop();
        if (PowerSource.on_ac) {
            reveal_anim.to = 1;
            reveal_anim.start();
        } else {
            root.reveal = 1;
        }
        keys.forceActiveFocus();
    }

    // Call after clearing wanted; immediate hides at once instead of fading.
    function conceal(immediate) {
        root.typing = false;
        root.help_open = false;
        reveal_anim.stop();
        if (immediate) {
            root.reveal = 0;
            root.visible = false;
        } else if (PowerSource.on_ac && root.visible) {
            reveal_anim.to = 0;
            reveal_anim.start();
        } else {
            root.reveal = 0;
            root.visible = false;
        }
    }

    function focus_later(address) {
        focus_timer.address = address;
        focus_timer.restart();
    }

    function reading_order(items) {
        return items.slice().sort((a, b) => a.ry - b.ry || a.rx - b.rx);
    }

    function to_set(list) {
        const out = {};
        for (const k of list) out[k] = true;
        return out;
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

    function set_hit(i) {
        root.hit = i;
        root.select_entry(root.hit_entry);
    }

    function step_hit(delta) {
        const n = root.ranked.length;
        if (n > 0) root.set_hit((root.hit_index + delta + n) % n);
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

    function direction_of(k) {
        if (k === Qt.Key_H || k === Qt.Key_Left) return [-1, 0];
        if (k === Qt.Key_L || k === Qt.Key_Right) return [1, 0];
        if (k === Qt.Key_K || k === Qt.Key_Up) return [0, -1];
        if (k === Qt.Key_J || k === Qt.Key_Down) return [0, 1];
        return null;
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
                root.filmstrip_vertical(dy);
                return;
            }
        } else {
            to = Layout.neighbor(root.layout.tile_rects, from, dx, dy);
        }
        if (to !== undefined && to >= 0) root.select(to);
    }

    function cursor_key() {
        return root.selected_key + "|" + root.current_address;
    }

    function play_if_moved(before) {
        if (root.cursor_key() !== before) ThemeAudio.play("cursor");
    }

    // Digits typed in quick succession name one target, so 1 then 2 lands on 12 when it exists.
    function type_digit(d) {
        const before = root.cursor_key();
        const joined = digit_timer.running ? digit_timer.typed + d : "";
        if (joined !== "" && root.jump(parseInt(joined))) {
            digit_timer.typed = joined;
        } else if (d !== "0") {
            root.jump(parseInt(d));
            digit_timer.typed = d;
        } else {
            return;
        }
        root.play_if_moved(before);
        digit_timer.restart();
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

    // Every window, most recent first, minus the carried ones and, in share mode, the unshareable ones.
    function window_entries() {
        return WindowState.entries().filter(e => !root.picked_set[e.address] && !(root.share_mode && Screenshot.share_id_of(e.address) === ""));
    }

    // Puts the tile selection on the window, switching between regular and special mode when it lives in the other one.
    function select_entry(entry) {
        if (!entry) return;
        const is_special = entry.ws_name.startsWith("special:");
        if (is_special !== root.special) {
            root.special = is_special;
            digit_timer.stop();
        }
        const at = root.tile_index_of[is_special ? "sp:" + entry.ws_name.slice(8) : "ws:" + entry.ws_id];
        if (at !== undefined) root.select(at, entry.address);
    }

    // An empty query starts on the window before the current one when searching, else on the selected window.
    function reset_hit() {
        const list = root.ranked;
        let at = 0;
        if (root.query === "") at = root.from_search ? WindowEntries.previous_index(list, WindowState.active_address) : Math.max(0, list.findIndex(e => e.address === root.current_address));
        root.set_hit(at);
    }

    function accept_hit() {
        const entry = root.hit_entry;
        if (!entry) return;
        root.select_entry(entry);
        root.clear_filter();
        if (root.share_mode) root.share_window(entry.address);
        else if (root.carrying) root.drop();
        else root.activate_address(entry.address);
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

    function filmstrip_vertical(dy) {
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
    function jump(id) {
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
        digit_timer.stop();
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

    function activate() {
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
        if (root.ws_mode === "monitor") return root.confirm_ws_mode();
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
        } else if (k === Qt.Key_Escape || k === Qt.Key_S || (k === Qt.Key_W && root.ws_mode === "monitor")) {
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
        name_popup.open(root.save_target !== "" ? root.save_target : Sessions.default_name());
    }

    function stop_naming() {
        name_popup.release();
        root.naming = false;
        root.name_error = "";
        keys.forceActiveFocus();
    }

    function confirm_save() {
        const name = name_popup.name;
        const problem = Sessions.name_problem(name, root.save_target);
        if (root.save_pending) return;
        if (problem !== "") {
            root.name_error = problem;
            return;
        }
        root.save_pending = true;
        root.name_error = "";
        Sessions.save_capture(root.alive(root.marks), name, root.save_target);
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

    function toggle_mark() {
        root.mark_address(root.current_address);
    }

    // Marks every window in the selected workspace, or unmarks them all when they already are.
    function toggle_mark_all() {
        const here = root.tab_order.map(w => w.address);
        if (here.length === 0) return;
        const all = here.every(a => root.marks.indexOf(a) >= 0);
        root.marks = all ? root.marks.filter(m => here.indexOf(m) < 0) : root.marks.concat(here.filter(a => root.marks.indexOf(a) < 0));
    }

    // Closes every marked window, or the selected one; selection steps to the next window.
    function close_selected() {
        const marked = root.alive(root.marks);
        const doomed = marked.length > 0 ? marked : root.current_address !== "" ? [root.current_address] : [];
        if (doomed.length === 0) return;
        const at = root.tab_order.findIndex(w => w.address === root.current_address);
        const left = root.tab_order.filter(w => doomed.indexOf(w.address) < 0);
        const next = left.find(w => root.tab_order.indexOf(w) > at) || left[left.length - 1];
        root.selected_address = next ? next.address : "";
        root.marks = [];
        root.close_windows(doomed);
    }

    function close_windows(addresses) {
        for (const a of addresses) WindowState.close(a);
        refresh_timer.restart();
    }

    function pick() {
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

    function cancel_pick() {
        root.carry_exit = "";
        if (root.picked_from_marks) root.marks = root.alive(root.picked);
        root.picked = [];
    }

    // Swaps inside a workspace, else moves every carried window there; a fresh slot is then sent to its monitor.
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
        const exit = root.carry_exit;
        root.carry_exit = "";
        if (swap_with !== "") {
            WindowState.swap(carried[0], swap_with);
            root.selected_address = carried[0];
            refresh_timer.restart();
            if (exit !== "") root.hide_overview();
            return;
        }
        for (const a of moving) root.move_window(a, root.special ? "sp:" + tile.name : String(tile.id));
        if (tile.is_new && !root.special) Hyprland.dispatch("hl.dsp.workspace.move({ workspace = " + tile.id + ", monitor = '" + root.groups[tile.group].name + "' })");
        root.selected_key = root.special ? tile.key : "ws:" + tile.id;
        root.selected_address = moving[0];
        refresh_timer.restart();
        if (exit === "") return;
        root.hide_overview();
        if (exit === "follow") root.focus_later(moving[0]);
    }

    // ref is a regular workspace id, which Hyprland creates when it does not exist yet, or "sp:<name>" for a special one.
    function move_window(address, ref) {
        if (ref.startsWith("sp:")) Hyprland.dispatch("hl.dsp.window.move({ window = " + WindowState.selector(address) + ", workspace = " + root.quoted("special:" + ref.slice(3)) + ", follow = false })");
        else WindowState.move_to_workspace(address, parseInt(ref), false);
    }

    function windows_on(ref) {
        const special = ref.startsWith("sp:");
        const id = parseInt(ref);
        return WindowState.windows.filter(t => t.workspace && (special ? t.workspace.name === "special:" + ref.slice(3) : t.workspace.id === id)).map(t => t.address);
    }

    function move_workspace_to_monitor(id, monitor_name) {
        Hyprland.dispatch("hl.dsp.workspace.move({ workspace = " + id + ", monitor = " + root.quoted(monitor_name) + " })");
        refresh_timer.restart();
    }

    // Every window of one workspace trades places with every window of the other, wherever the two are shown.
    function swap_workspaces(ref_a, ref_b) {
        const in_a = root.windows_on(ref_a);
        const in_b = root.windows_on(ref_b);
        for (const a of in_a) root.move_window(a, ref_b);
        for (const a of in_b) root.move_window(a, ref_a);
        refresh_timer.restart();
    }

    function start_ws_mode(mode) {
        const tile = root.selected_tile;
        if (!tile || tile.is_new || root.special || root.share_mode || root.save_mode || root.carrying) return;
        root.ws_mode = mode;
        root.ws_source = tile.key;
        if (mode === "monitor") root.screen_pick = true;
        ThemeAudio.play("cursor");
    }

    function end_ws_mode() {
        root.ws_mode = "";
        root.ws_source = "";
    }

    // Sends the source workspace to the picked monitor, or swaps it with the selected workspace.
    function confirm_ws_mode() {
        const mode = root.ws_mode;
        const source = root.tiles.find(t => t.key === root.ws_source);
        const target = root.selected_tile;
        if (source && target) {
            if (mode === "monitor" && root.groups[target.group] && target.group !== source.group) root.move_workspace_to_monitor(source.id, root.groups[target.group].name);
            else if (mode === "swap" && target.key !== source.key && !target.is_new) root.swap_workspaces(String(source.id), String(target.id));
            root.selected_key = source.key;
        }
        root.screen_pick = false;
        root.end_ws_mode();
    }

    // Selection keys pass through to the shared handling; anything that would act on windows or switch modes is swallowed.
    function handle_swap_key(event) {
        const k = event.key;
        const shifted_w = k === Qt.Key_W && (event.modifiers & Qt.ShiftModifier);
        if (k === Qt.Key_Return || k === Qt.Key_Enter || shifted_w) {
            ThemeAudio.play("confirm");
            root.confirm_ws_mode();
        } else if (k === Qt.Key_Escape) {
            ThemeAudio.play("cancel");
            root.end_ws_mode();
        } else if (k === Qt.Key_M || k === Qt.Key_X || k === Qt.Key_V || k === Qt.Key_Space || k === Qt.Key_S || k === Qt.Key_W || k === Qt.Key_Tab || k === Qt.Key_Backtab || k === Qt.Key_Slash || event.text === "/") {
            return true;
        } else {
            return false;
        }
        return true;
    }

    // Addresses of windows on screen, in the order given; none when any is unknown.
    function shown_windows(addresses) {
        const known = {};
        for (const t of root.tiles) for (const w of t.windows) known[w.address] = true;
        return addresses.every(a => known[a]) ? addresses : null;
    }

    // The voice entry: each verb calls what its key calls. Window arguments are addresses; with none, a verb acts on the marks, or the selected window when nothing is marked, like the keys.
    function voice_act(verb, text) {
        if (!root.wanted) return "error: the overview is closed";
        const args = text.split(" ").filter(a => a !== "");
        // These verbs lead with a workspace (or, for send, a monitor) before any window addresses.
        const verbs_with_ref = ["move", "send", "workspace", "workspace_to_monitor", "swap_workspaces"];
        // References arrive percent-encoded (voxcmd): a special workspace's name may hold the spaces this split uses.
        const ref = verbs_with_ref.indexOf(verb) >= 0 ? decodeURIComponent(args.shift() || "") : "";
        const monitor = verb === "send" || verb === "workspace_to_monitor" ? (verb === "send" ? ref : args.shift()) : "";
        const explicit = root.shown_windows(args);
        if (!explicit && ["mark", "unmark", "move", "send", "close", "focus"].indexOf(verb) >= 0) return "error: unknown window";
        // Like x and m: the marks, or the selected window when nothing is marked.
        const marked = root.alive(root.marks);
        const targets = args.length > 0 ? explicit : marked.length > 0 ? marked : root.current_address !== "" ? [root.current_address] : [];
        if (verb === "mark") {
            root.marks = root.marks.concat(targets.filter(a => root.marks.indexOf(a) < 0));
        } else if (verb === "unmark") {
            root.marks = root.marks.filter(a => targets.indexOf(a) < 0);
        } else if (verb === "clear") {
            root.marks = [];
        } else if (verb === "move" || verb === "send") {
            if (targets.length === 0) return "error: no windows";
            let destination = ref;
            if (verb === "send") {
                const m = Hyprland.monitors.values.find(x => x.name === monitor);
                if (!m || !m.activeWorkspace) return "error: unknown monitor";
                destination = String(m.activeWorkspace.id);
            } else if (!/^(\d+|sp:.+)$/.test(destination || "")) {
                return "error: unknown workspace";
            }
            for (const a of targets) root.move_window(a, destination);
            root.marks = root.marks.filter(a => targets.indexOf(a) < 0);
            refresh_timer.restart();
        } else if (verb === "close") {
            if (targets.length === 0) return "error: no windows";
            root.marks = root.marks.filter(a => targets.indexOf(a) < 0);
            root.close_windows(targets);
        } else if (verb === "focus") {
            if (args.length !== 1) return "error: one window";
            root.activate_address(args[0]);
        } else if (verb === "workspace") {
            const tile = root.tiles.find(t => !t.is_new && t.key === (ref.startsWith("sp:") ? ref : "ws:" + ref));
            if (!tile && !/^\d+$/.test(ref || "")) return "error: unknown workspace";
            root.focus_workspace(tile || { is_new: false, id: parseInt(ref), name: ref });
            root.hide_overview();
        } else if (verb === "workspace_to_monitor") {
            if (!/^\d+$/.test(ref || "") || !Hyprland.monitors.values.some(x => x.name === monitor)) return "error: unknown workspace or monitor";
            root.move_workspace_to_monitor(ref, monitor);
        } else if (verb === "swap_workspaces") {
            const other = decodeURIComponent(args[0] || "");
            if (!/^(\d+|sp:.+)$/.test(ref || "") || !/^(\d+|sp:.+)$/.test(other || "")) return "error: unknown workspace";
            root.swap_workspaces(ref, other);
        } else if (verb === "close_overview") {
            root.hide_overview();
        } else {
            return "error: unknown verb " + verb;
        }
        return "ok";
    }

    function handle_key(event) {
        const before = root.cursor_key();
        const k = event.key;
        if (event.modifiers & Qt.AltModifier) return;
        if (event.modifiers & Qt.ControlModifier) {
            const dir = root.direction_of(k);
            if (dir) root.move_monitor(dir[0], dir[1]);
            else if (k >= Qt.Key_0 && k <= Qt.Key_9) root.jump_monitor(k === Qt.Key_0 ? 10 : k - Qt.Key_0);
            else return;
            root.play_if_moved(before);
            event.accepted = true;
            return;
        }
        // Each mode takes the keys it owns first; the rest fall through to the normal keys below.
        if ((root.ws_mode === "swap" && root.handle_swap_key(event)) || (root.screen_pick && root.handle_screen_key(event)) || (root.share_mode && root.handle_share_key(event)) || (root.save_mode && root.handle_save_key(event))) {
            event.accepted = true;
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
        } else if (root.direction_of(k)) {
            const dir = root.direction_of(k);
            root.move(dir[0], dir[1]);
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
            root.close_selected();
            ThemeAudio.play("confirm");
        } else if (k === Qt.Key_F) {
            root.filmstrip = !root.filmstrip;
        } else if (k === Qt.Key_Slash || event.text === "/") {
            root.start_filter(false);
        } else if (k >= Qt.Key_0 && k <= Qt.Key_9) {
            root.type_digit(String(k - Qt.Key_0));
        } else if (k === Qt.Key_BracketRight || k === Qt.Key_BracketLeft) {
            root.cycle_window(k === Qt.Key_BracketRight ? 1 : -1);
            root.play_if_moved(before);
        } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            root.toggle_special();
            if (root.special && root.tiles.length === 0) root.select_focused_workspace();
            root.play_if_moved(before);
        } else if (k === Qt.Key_S) {
            ThemeAudio.play("cursor");
            root.screen_pick = true;
        } else if (k === Qt.Key_W) {
            root.start_ws_mode((event.modifiers & Qt.ShiftModifier) ? "swap" : "monitor");
        } else {
            return;
        }
        event.accepted = true;
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

    readonly property string footer_text: root.help_open ? "? back · Esc back · q " + (root.share_mode ? "cancel share" : root.save_mode ? "close without saving" : "close")
        : root.save_mode ? (root.naming ? "Enter save · Esc back to marking" : "Space mark · V mark all here · Enter name and save · hjkl move · ]/[ window · Tab special · f view · ? help · Esc cancel")
        : root.typing ? "Enter " + (root.share_mode ? "share" : root.carrying ? "drop here" : "focus") + " · Tab/Down next · Shift+Tab/Up previous · Esc " + (root.from_search && root.query === "" ? "close" : "clear") + " · ? help"
        : root.ws_mode === "monitor" ? "Enter send workspace " + root.ws_name + " to this monitor · hjkl/Ctrl+hjkl/Ctrl+1-9 monitor · w/s/Esc back · ? help · q close"
        : root.ws_mode === "swap" ? "Enter/W swap workspace " + root.ws_name + " with this one · hjkl workspace · Ctrl+hjkl/1-9 monitor · Esc cancel · ? help · q close"
        : root.screen_pick ? (root.share_mode ? "Enter share screen · hjkl/Ctrl+hjkl/Ctrl+1-9 monitor · r region · s/Esc back · f view · ? help · q cancel"
            : (root.carrying ? "m/Enter drop on screen" : "Enter focus screen") + " · hjkl/Ctrl+hjkl/Ctrl+1-9 monitor · s/Esc back · f view · ? help · q close")
        : root.share_mode ? "hjkl move · Ctrl+hjkl/1-9 monitor · ]/[ window · Enter share window · s screen · r region · Tab special · / search · f view · ? help · Esc cancel"
        : root.swap_address !== "" ? "m swap · Enter swap · ]/[ other window · hjkl workspace · Esc cancel · ? help"
        : root.carrying ? "hjkl workspace · Ctrl+hjkl/1-9 monitor · ]/[ window · s screen · Tab special · m drop · Enter drop · Esc cancel · ? help"
        : root.marks.length > 0 ? "Space mark · V mark all · m move " + root.marks.length + " · x close " + root.marks.length + " · hjkl move · Esc clear marks · ? help"
        : "hjkl move · Ctrl+hjkl/1-9 monitor · ]/[ window · Enter focus · m move · x close · Space mark · / search · f view · s screen · Tab special · w workspace to monitor · W swap workspaces · ? help · q close"

    readonly property string normal_help: "h/j/k/l move between workspaces · Arrows move between workspaces · Ctrl+h/j/k/l or Ctrl+Arrows jump to the next monitor that way · Ctrl+1-9 jump to that monitor number, as SUPER+Ctrl+1-9 counts them · ] next window · [ previous window · Enter focus window, or the workspace if empty · m pick up window, or every marked window · x close window, or every marked window · Space/v mark or unmark window · V mark or unmark all in workspace · / search windows by class, title or workspace · 1-9 select workspace by id, type 12 quickly for workspace 12, or the nth special workspace · s pick the whole monitor of the selected workspace, Enter then focuses it · w send the selected workspace to a monitor, picked like s, Enter confirms · W swap the selected workspace's windows with another workspace's, pick it with h/j/k/l, Enter confirms · Tab/Shift+Tab toggle special workspaces · f toggle filmstrip view, j/k there jump monitors · Click focus window or workspace"
    readonly property string carry_help: "h/j/k/l choose target workspace · Arrows choose target workspace · Ctrl+h/j/k/l choose target monitor · Ctrl+1-9 target monitor by number · 1-9 target workspace by id, type 12 quickly for workspace 12 · Tab/Shift+Tab toggle special workspaces · s pick a whole monitor, m/Enter then drop on its visible workspace · ]/[ choose a window in the same workspace to swap with ·m drop there, or swap with the SWAP window · Enter drop there, or swap · f toggle filmstrip view · Click drop on workspace · Esc cancel, marks come back"
    readonly property string screen_moves: "h/j/k/l, Arrows, Ctrl+h/j/k/l or Ctrl+Arrows pick the next monitor that way · Ctrl+1-9 pick that monitor number"
    readonly property string screen_help: root.share_mode ? "The whole monitor is the pick · Enter share it · Click share it, or click another monitor to pick that one · " + root.screen_moves + " · r share a region of this monitor instead, Esc there comes back here · s/Esc back to window selection · f toggle filmstrip view · q cancel the share"
        : "The whole monitor is the pick · " + (root.carrying ? "m/Enter drop the carried windows on its visible workspace · Click drop them there" : "Enter focus it and close · Click focus it") + ", or click another monitor to pick that one · " + root.screen_moves + " · s/Esc back to the selected workspace · f toggle filmstrip view · q close"
    readonly property string save_help: "Every window starts marked, and Enter saves the marked ones as a session · Space/v mark or unmark window · V mark or unmark all in workspace · Enter name the session, then Enter again to save it · Nothing is moved, closed or focused here · h/j/k/l move between workspaces · Arrows move between workspaces · Ctrl+h/j/k/l or Ctrl+Arrows jump to the next monitor that way · Ctrl+1-9 jump to that monitor number · ] next window · [ previous window · 1-9 select workspace by id, or the nth special workspace · Tab/Shift+Tab toggle special workspaces · f toggle filmstrip view · Click mark or unmark window · Esc/q close without saving"
    readonly property string share_help: "Only windows the share can capture are shown · h/j/k/l move between workspaces · Arrows move between workspaces · Ctrl+h/j/k/l or Ctrl+Arrows jump to the next monitor that way · Ctrl+1-9 jump to that monitor number · ] next window · [ previous window · Enter share the selected window · Click share a window · s pick the whole monitor of the selected workspace, Enter then shares it · r share a region of that monitor, Esc there comes back here · Tab/Shift+Tab toggle special workspaces ·/ search shareable windows by class, title or workspace · 1-9 select workspace by id, or the nth special workspace · f toggle filmstrip view, j/k there jump monitors · Esc/q cancel the share"
    readonly property string ws_help: root.ws_mode === "monitor" ? "Sending workspace " + root.ws_name + " to a monitor · " + root.screen_moves + " · Enter/w send it to the picked monitor · s/Esc cancel · f toggle filmstrip view · q close"
        : "Swapping workspace " + root.ws_name + " with another · h/j/k/l, Arrows, Ctrl+h/j/k/l or Ctrl+1-9 move to the other workspace · 1-9 select workspace by id · ]/[ window · f toggle filmstrip view · Enter/W swap the two workspaces' windows · Esc cancel · q close"
    readonly property string help_text: root.save_mode ? root.save_help
        : root.ws_mode !== "" ? root.ws_help
        : root.typing ? "Type to search " + (root.share_mode ? "shareable " : "") + "windows by class, title or workspace · Enter " + (root.share_mode ? "share the highlighted window" : "focus the highlighted window, or drop the carried window on its workspace") + " · Tab/Down next match · Shift+Tab/Up previous match · Backspace delete, clears when empty · Esc clear search, or close when it is empty"
        : root.screen_pick ? root.screen_help
        : root.share_mode ? (root.query !== "" ? "Esc clear search · " : "") + root.share_help
        : root.carrying ? root.carry_help
        : root.marks.length > 0 ? "Esc clear all marks · " + root.normal_help
        : root.query !== "" ? "Esc clear search · " + root.normal_help
        : root.normal_help

    readonly property string status_text: {
        if (root.typing || root.query !== "") return "/" + root.query + (root.typing ? "_" : "") + "  " + root.ranked.length + " match" + (root.ranked.length === 1 ? "" : "es");
        if (root.ws_mode === "monitor" && root.selected_tile && root.groups[root.selected_tile.group]) return "SEND WORKSPACE " + root.ws_name + " to " + root.groups[root.selected_tile.group].name;
        if (root.ws_mode === "swap" && root.selected_tile) return "SWAP WORKSPACE " + root.ws_name + " with " + (root.selected_tile.key === root.ws_source ? "..." : root.selected_tile.name);
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

    FileView {
        id: voice_file
        path: root.voice_dir + "/overview.json"
        printErrors: false
    }

    // Debounced, so a burst of model changes writes once.
    Timer {
        id: voice_write_timer
        interval: 60
        onTriggered: voice_file.setText(JSON.stringify(root.voice_snapshot))
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

    // Focus waits for the overlay to drop its exclusive keyboard grab, else the grab's release restores the old window.
    Timer {
        id: focus_timer
        property string address: ""
        interval: 60
        onTriggered: WindowState.focus(focus_timer.address)
    }

    // With the screen frame on, the layer is the frame's hole, whose corners are cut in the frame's own profile. The
    // scrim and panel are masked to that outline so the frame's corners show through instead of being painted over.
    readonly property var hole_outline: Style.screen_frame_on && root.screen ? ScreenFrames.hole_outline(root.screen) : []
    readonly property bool corners_cut: root.hole_outline.length > 0 && Style.screen_frame_profile !== null && Style.screen_frame_profile.corner !== "square" && Style.screen_frame_profile.radius > 0

    Item {
        id: hole_mask
        anchors.fill: parent
        visible: false
        layer.enabled: root.corners_cut

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: "black"
                PathPolyline { path: root.hole_outline }
            }
        }
    }

    Item {
        anchors.fill: parent
        layer.enabled: root.corners_cut
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: hole_mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
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
            hole_cut: root.corners_cut
            // With the screen frame on the layer is the frame's hole, so the panel meets its edge like a drawer does.
            x: Style.screen_frame_on ? 0 : Style.px(36)
            y: Style.screen_frame_on ? 0 : Style.px(30)
            width: parent.width - x * 2
            height: parent.height - y * 2
            opacity: root.reveal
            scale: 0.97 + 0.03 * root.reveal
            title: root.save_mode ? "SAVE SESSION" : root.share_mode ? "SHARE" : root.special ? "SPECIAL" : "OVERVIEW"
            status: root.status_text
            status_color: root.screen_pick || root.carrying || root.marks.length > 0 || root.query !== "" ? Style.text_accent : Style.text_muted
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

            // One monitor's group: its panel and label, and in a screen pick its whole-monitor frame and click target.
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
                            label: group.modelData.name + (group.modelData.focused ? " · focused" : "")
                            color: group.holds_selection ? Style.text_primary : Style.section_fg
                        }
                    }

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
                    visible: tile.rect.w > 0 && tile.x + tile.width > 0 && tile.x < frame.body.width
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
                    numbers: root.window_numbers
                    show_numbers: root.voice_on
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
                numbers: root.window_numbers
                show_numbers: root.voice_on
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
                glide: PowerSource.on_ac && root.reveal === 1
            }

            AmmoCounter {
                visible: Style.overview_skin === "goldeneye" && root.window_total > 0
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                index: root.window_at
                total: root.window_total
            }

            LockAim {
                anchors.fill: parent
                aim: root.help_open ? null : root.aim
                animate: PowerSource.on_ac && root.reveal === 1
            }

            SessionNamePopup {
                id: name_popup
                visible: root.naming
                anchors.fill: parent
                updating: root.save_target !== ""
                error_text: root.name_error
                pending: root.save_pending
                window_count: root.marks.length
                onEdited: root.name_error = ""
                onCancelled: root.stop_naming()
                onConfirmed: root.confirm_save()
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

            // The full key list for the current mode, drawn over the tiles.
            Rectangle {
                visible: root.help_open
                anchors.fill: parent
                color: Style.frame_color.a > 0.5 ? Style.frame_color : Theme.bg_crust

                KeyHelp {
                    id: key_help
                    anchors.fill: parent
                    text: root.help_text
                    general: [{ key: "?", desc: "back" }, { key: "Esc", desc: "back" }, { key: "q", desc: root.share_mode ? "cancel share" : root.save_mode ? "close without saving" : "close overview" }]
                    onBack: root.hide_help()
                    onClose_requested: root.hide_overview()
                }
            }
        }
    }
}
