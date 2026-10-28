pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.features.bar
import qs.features.popups
import qs.theme
import "../bar/BarLayout.js" as BarLayout

// The bar editor's state and key handling: which monitor and module are selected, the mode, undo. The windows only draw it.
// Edits go through the pure functions in BarLayout.js and BarSettings.set_state, so the real bars change at once.
Singleton {
    id: root

    // Replaceable so the lifecycle tests can stand in monitors that come and go.
    property var screens: Quickshell.screens
    property var tracked_of: screen => BarSettings.tracked_rule_for(screen)
    property var key_of: screen => BarSettings.monitor_key(screen)
    property var tracked_rules: BarSettings.rules
    property string focused_name: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    property bool lualine: Style.bar_lualine

    property bool active: false
    // "monitor" (pick a bar), "normal", "hidden" (the hidden list, possibly carrying one module) or "visual" (the whole bar).
    property string mode: "monitor"
    // The monitor whose bar is picked or edited, and the only screen that takes the keyboard.
    property string focus_screen: ""
    property string selected: ""
    // The hidden module the cursor is on, and the one picked up (already on the bar, still being placed).
    property string hidden_selected: ""
    property string picked: ""
    property bool help_open: false
    property bool prompt_open: false
    property string prompt_text: ""

    // Whole BarSettings.state snapshots. Restoring one also restores unrelated keys changed since (directory switches).
    property var undo_stack: []
    property var redo_stack: []
    // The state before a pick-up, which Esc returns to, and the redo steps that pick-up cleared, which it gives back.
    property var pick_base: null
    property var pick_redo: []

    // Screens that have a bar, with their geometry for picking by direction.
    readonly property var monitors: {
        const out = [];
        for (const s of root.screens) {
            const tracked = root.tracked_of(s);
            if (tracked && tracked.bar !== false) out.push({ name: s.name, x: s.x, y: s.y, w: s.width, h: s.height });
        }
        return out;
    }

    readonly property var focus_screen_object: root.screens.find(s => s.name === root.focus_screen) || null
    readonly property var tracked: root.focus_screen_object ? root.tracked_of(root.focus_screen_object) : null
    readonly property string screen_key: root.focus_screen_object ? root.key_of(root.focus_screen_object) : ""
    readonly property var edited_rule: root.tracked ? BarLayout.effective(root.tracked, BarSettings.state, root.screen_key) : null
    readonly property var view: BarLayout.layout_of(root.edited_rule)
    readonly property bool vertical: BarLayout.is_vertical(BarLayout.position_of(root.edited_rule))
    // A lualine bar on a row draws its modules by section; on a column it falls back to islands.
    readonly property string position_edge: BarLayout.position_of(root.edited_rule) || "top"
    readonly property string position_source: BarLayout.position_source(root.tracked, BarSettings.state, root.screen_key)
    // False when `x` in VISUAL would change nothing, so the hint does not offer it.
    readonly property bool can_forget: JSON.stringify(BarLayout.forget_position_for_mode(BarSettings.state, root.screen_key)) !== JSON.stringify(BarSettings.state)
    readonly property bool sectioned: root.lualine && !root.vertical
    readonly property var order: BarLayout.nav_order(root.view, root.sectioned)
    readonly property bool sharing: BarLayout.is_sharing(BarSettings.state, root.screen_key)
    readonly property int sharing_count: root.sharing ? root.sharing_screens().length : 0
    readonly property var hidden_list: BarLayout.hidden_entries(BarSettings.rules, BarSettings.state, root.view).filter(BarLayout.is_known_entry)
    // The module the hint bar names: the one under the cursor in the hidden list, else the selected one.
    readonly property string current_name: root.mode === "hidden" && root.picked === "" ? root.hidden_selected : root.selected
    readonly property string mode_label: root.mode === "monitor" ? "MONITOR" : root.mode.toUpperCase()

    // "shared" or "own layout" for a monitor's bar.
    function tag_of(screen_name) {
        const s = root.screens.find(x => x.name === screen_name);
        return s && !BarLayout.is_sharing(BarSettings.state, root.key_of(s)) ? "own layout" : "shared";
    }

    // Height of monitor select's 520 px wide map of a w x h layout: 130 px for a wide one, taller for a tall one, so a
    // portrait monitor's tile stays wide enough for its name and tag.
    function map_height(w, h) {
        return Math.min(320, Math.max(130, 520 * h / w));
    }

    function keyboard_owner(screen_name) {
        return root.active && root.focus_screen === screen_name;
    }

    // Monitors showing the layout the focused one shares.
    function sharing_screens() {
        return root.monitors.filter(m => {
            const s = root.screens.find(x => x.name === m.name);
            return s && BarLayout.is_sharing(BarSettings.state, root.key_of(s));
        }).map(m => m.name);
    }

    // The tracked rules whose own compact applies when the shared one is cleared: the connected sharing monitors', plus
    // every other tracked rule, since a disconnected monitor shares the layout too and its rule cannot be told apart.
    function sharing_rules() {
        const connected = root.sharing_screens().map(name => root.tracked_of(root.screens.find(s => s.name === name)));
        return connected.concat(root.tracked_rules.filter(r => connected.indexOf(r) < 0));
    }

    function open(screen_name) {
        // A popup (Settings included) holds the keyboard; the editor takes it, so the popup goes.
        if (Popups.open_name !== "") Popups.close();
        if (root.monitors.length === 0) return false;
        const wanted = screen_name !== "" ? screen_name : root.focused_name;
        root.undo_stack = [];
        root.redo_stack = [];
        root.pick_base = null;
        root.picked = "";
        root.help_open = false;
        root.prompt_open = false;
        root.focus_screen = root.monitors.some(m => m.name === wanted) ? wanted : root.monitors[0].name;
        root.mode = "normal";
        root.selected = root.order[0] || "";
        root.active = true;
        return true;
    }

    function close() {
        if (root.picked !== "") root.cancel_pick();
        root.active = false;
        root.focus_screen = "";
        root.selected = "";
        root.picked = "";
        root.help_open = false;
        root.prompt_open = false;
        root.undo_stack = [];
        root.redo_stack = [];
        root.pick_base = null;
        root.pick_redo = [];
    }

    function toggle(screen_name) {
        if (root.active) root.close();
        else root.open(screen_name);
    }

    function state_json() {
        return JSON.stringify({ active: root.active, mode: root.mode, focus_screen: root.focus_screen, selected: root.selected, picked: root.picked, sharing: root.sharing, sharing_count: root.sharing_count, position_edge: root.position_edge, position_source: root.position_source, undo: root.undo_stack.length, redo: root.redo_stack.length });
    }

    // Applies an edit as one undo step; an edit that changes nothing is not one.
    function commit(next) {
        if (JSON.stringify(next) === JSON.stringify(BarSettings.state)) return false;
        root.undo_stack = root.undo_stack.concat([BarSettings.state]);
        root.redo_stack = [];
        BarSettings.set_state(next);
        return true;
    }

    function undo() {
        if (root.undo_stack.length === 0) return;
        const back = root.undo_stack[root.undo_stack.length - 1];
        root.undo_stack = root.undo_stack.slice(0, -1);
        root.redo_stack = root.redo_stack.concat([BarSettings.state]);
        BarSettings.set_state(back);
    }

    function redo() {
        if (root.redo_stack.length === 0) return;
        const again = root.redo_stack[root.redo_stack.length - 1];
        root.redo_stack = root.redo_stack.slice(0, -1);
        root.undo_stack = root.undo_stack.concat([BarSettings.state]);
        BarSettings.set_state(again);
    }

    // Keeps the selection on something that exists after any change to the layout, the monitors or the mode.
    function ensure_selection() {
        if (!root.active || root.mode === "monitor") return;
        if (root.mode === "hidden") {
            if (root.picked === "" && root.hidden_list.indexOf(root.hidden_selected) < 0) root.hidden_selected = root.hidden_list[0] || "";
            return;
        }
        if (root.order.indexOf(root.selected) < 0) root.selected = root.order[0] || "";
    }

    // Monitors come and go while the editor is open: a bar that is gone cannot stay picked.
    function reconcile() {
        if (!root.active) return;
        if (root.monitors.length === 0) {
            root.close();
            return;
        }
        if (!root.monitors.some(m => m.name === root.focus_screen)) {
            if (root.picked !== "") root.cancel_pick();
            root.focus_screen = root.monitors[0].name;
            root.mode = "monitor";
            root.help_open = false;
            root.prompt_open = false;
        }
        root.ensure_selection();
    }

    onMonitorsChanged: root.reconcile()
    onOrderChanged: root.ensure_selection()
    onHidden_listChanged: root.ensure_selection()

    // A popup that takes the keyboard, opened under the editor (a keybind or IPC), would contest it, so the editor yields.
    // Looked at a turn later: a hover-opened popup says it takes none only after it is open, and one pinned later asks for it.
    function yield_to_popup() {
        if (root.active && Popups.takes_keyboard && !Popups.keyboard_off) root.close();
    }

    Connections {
        target: Popups
        function onOpen_nameChanged() {
            Qt.callLater(root.yield_to_popup);
        }
        function onKeyboard_offChanged() {
            Qt.callLater(root.yield_to_popup);
        }
    }

    // The monitor nearest in a direction, by where the screens sit: the closest center along that axis, the
    // closest across it breaking ties.
    function pick_monitor(from_name, dx, dy) {
        const from = root.monitors.find(m => m.name === from_name);
        if (!from) return from_name;
        const cx = from.x + from.w / 2;
        const cy = from.y + from.h / 2;
        let best = null;
        let best_score = Infinity;
        for (const m of root.monitors) {
            if (m.name === from_name) continue;
            const mx = m.x + m.w / 2 - cx;
            const my = m.y + m.h / 2 - cy;
            const along = dx !== 0 ? mx * dx : my * dy;
            const across = dx !== 0 ? Math.abs(my) : Math.abs(mx);
            if (along <= 0) continue;
            const score = along + across * 2;
            if (score < best_score) {
                best_score = score;
                best = m.name;
            }
        }
        return best || from_name;
    }

    function select_by(delta) {
        root.selected = BarLayout.nav_step(root.order, root.selected, delta);
    }

    function move_selected(delta) {
        if (root.selected === "") return;
        root.commit(BarLayout.move_step(root.tracked, BarSettings.state, root.screen_key, root.selected, delta, root.sectioned));
    }

    function hide_selected() {
        if (root.selected === "") return;
        const at = root.order.indexOf(root.selected);
        if (!root.commit(BarLayout.hide_entry(root.tracked, BarSettings.state, root.screen_key, root.selected))) return;
        root.selected = root.order[Math.min(at, root.order.length - 1)] || "";
    }

    function open_prompt() {
        const base = root.selected.split(":")[0];
        root.prompt_text = root.selected === "" ? "" : BarLayout.suggest_entry(root.tracked, BarSettings.state, root.screen_key, base);
        root.prompt_open = true;
    }

    function accept_prompt() {
        const text = root.prompt_text.trim();
        if (!BarLayout.valid_entry(text)) return;
        if (root.commit(BarLayout.add_entry(root.tracked, BarSettings.state, root.screen_key, text, root.selected))) root.selected = text;
        root.prompt_open = false;
    }

    // Takes the highlighted hidden module onto the bar to be placed with h/l; Esc returns everything to before.
    function pick_up() {
        const entry = root.hidden_selected;
        if (entry === "") return;
        const base = BarSettings.state;
        const redo = root.redo_stack;
        if (!root.commit(BarLayout.unhide_place(BarSettings.rules, root.tracked, BarSettings.state, root.screen_key, entry))) return;
        root.pick_base = base;
        root.pick_redo = redo;
        root.picked = entry;
        root.selected = entry;
    }

    function place_picked(delta) {
        BarSettings.set_state(BarLayout.move_step(root.tracked, BarSettings.state, root.screen_key, root.picked, delta, root.sectioned));
    }

    function drop_picked() {
        root.selected = root.picked;
        root.picked = "";
        root.pick_base = null;
        root.mode = "normal";
    }

    // The pick-up and the placements leave no undo step behind.
    function cancel_pick() {
        if (root.picked === "") return;
        const entry = root.picked;
        root.undo_stack = root.undo_stack.slice(0, -1);
        root.redo_stack = root.pick_redo;
        BarSettings.set_state(root.pick_base);
        root.pick_base = null;
        root.pick_redo = [];
        root.picked = "";
        root.hidden_selected = entry;
    }

    function forget_position() {
        root.commit(BarLayout.forget_position_for_mode(BarSettings.state, root.screen_key));
    }

    function set_edge(position) {
        root.commit(BarLayout.set_position_for_mode(BarSettings.state, root.screen_key, position));
    }

    // One key, named like "h", "H" (Shift), "Ctrl+r", "Enter", "Esc", "Tab", "Backspace", "?". True when the editor used it,
    // which is every key while it is open: nothing may reach what is under it.
    function press(spec) {
        if (!root.active) return false;
        if (root.prompt_open) {
            root.press_prompt(spec);
            return true;
        }
        // In the add prompt q is a typed letter; everywhere else it closes, cancelling a pick-up in progress.
        if (spec === "q") {
            root.close();
            return true;
        }
        if (root.help_open) {
            if (["?", "Esc", "Backspace"].indexOf(spec) >= 0) root.help_open = false;
            return true;
        }
        if (spec === "?") {
            root.help_open = true;
            return true;
        }
        if (root.mode === "monitor") root.press_monitor(spec);
        else if (root.mode === "normal") root.press_normal(spec);
        else if (root.mode === "hidden") root.press_hidden(spec);
        else if (root.mode === "visual") root.press_visual(spec);
        return true;
    }

    function press_prompt(spec) {
        if (spec === "Esc") root.prompt_open = false;
        else if (spec === "Enter") root.accept_prompt();
        else if (spec === "Backspace") root.prompt_text = root.prompt_text.slice(0, -1);
        else if (spec.length === 1) root.prompt_text += spec;
    }

    readonly property var directions: ({ h: [-1, 0], l: [1, 0], k: [0, -1], j: [0, 1] })

    function press_monitor(spec) {
        const d = root.directions[spec];
        if (d) {
            root.focus_screen = root.pick_monitor(root.focus_screen, d[0], d[1]);
        } else if (spec === "Enter") {
            root.mode = "normal";
            root.selected = root.order[0] || "";
        } else if (spec === "Esc") {
            root.close();
        }
    }

    function press_normal(spec) {
        if (spec === "h" || spec === "l" || (root.vertical && (spec === "j" || spec === "k"))) {
            root.select_by(spec === "h" || spec === "k" ? -1 : 1);
        } else if (spec === "H" || spec === "L" || (root.vertical && (spec === "J" || spec === "K"))) {
            root.move_selected(spec === "H" || spec === "K" ? -1 : 1);
        } else if (spec === "c") {
            root.commit(BarLayout.toggle_compact(root.tracked, BarSettings.state, root.screen_key, root.sharing_rules()));
        } else if (spec === "o") {
            root.commit(BarLayout.toggle_own(root.tracked, BarSettings.state, root.screen_key));
        } else if (spec === "a") {
            root.open_prompt();
        } else if (spec === "x") {
            root.hide_selected();
        } else if (spec === "u") {
            root.undo();
        } else if (spec === "Ctrl+r") {
            root.redo();
        } else if (spec === "Tab") {
            root.mode = "hidden";
            root.hidden_selected = root.hidden_list[0] || "";
        } else if (spec === "V") {
            root.mode = "visual";
        } else if (spec === "Esc") {
            root.mode = "monitor";
        }
    }

    function press_hidden(spec) {
        if (root.picked !== "") {
            if (spec === "h" || spec === "l") root.place_picked(spec === "h" ? -1 : 1);
            else if (spec === "Enter") root.drop_picked();
            else if (spec === "Esc") root.cancel_pick();
            return;
        }
        if (spec === "h" || spec === "l") root.hidden_selected = BarLayout.nav_step(root.hidden_list, root.hidden_selected, spec === "h" ? -1 : 1);
        else if (spec === "Enter") root.pick_up();
        else if (spec === "Esc" || spec === "Tab") {
            root.mode = "normal";
            // A cancelled pick-up leaves the selection on a module that is no longer on the bar.
            root.ensure_selection();
        }
    }

    function press_visual(spec) {
        const edges = { h: "left", j: "bottom", k: "top", l: "right" };
        if (edges[spec]) root.set_edge(edges[spec]);
        else if (spec === "x") root.forget_position();
        else if (spec === "u") root.undo();
        else if (spec === "Ctrl+r") root.redo();
        else if (spec === "Esc" || spec === "Enter") root.mode = "normal";
    }
}
