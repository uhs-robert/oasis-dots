import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.features.bar
import qs.features.bar_editor
import qs.features.popups
import "features/bar/BarLayout.js" as BarLayout
import "features/bar_editor/HintData.js" as HintData

// Harness shell for run.py: runs the scenario named by $SCENARIO inside a copy of the real bar config, so the real
// BarSettings (and the editor) are what is tested. The result goes to result.json under $XDG_STATE_HOME, then qs quits.
ShellRoot {
    id: root

    readonly property string scenario: Quickshell.env("SCENARIO")
    property var result: ({})
    property real started: 0
    property var done_steps: ({})
    // Every value BarSettings.state took, as the counter k in shared.order[0], in order.
    property var observed: []

    function counter_of(state) {
        const first = state.shared.order[0];
        return first ? parseInt(first.slice(1)) : 0;
    }

    function set_counter(k) {
        const next = JSON.parse(JSON.stringify(BarSettings.state));
        next.shared.order = ["n" + k].concat(Array.from({ length: 400 }, (_, i) => "pad" + i));
        BarSettings.set_state(next);
    }

    function outside_write(path, text) {
        Quickshell.execDetached(["sh", "-c", "printf %s \"$2\" > \"$1.ext\" && mv \"$1.ext\" \"$1\"", "sh", path, text]);
    }

    readonly property string bars_path: Quickshell.env("XDG_STATE_HOME") + "/quickshell/bars.json"

    function spaced(gap_ms, count) {
        return Array.from({ length: count }, (_, i) => [100 + i * gap_ms, () => root.set_counter(i + 1)]);
    }


    // The editor's lifecycle runs on stand-in monitors: A and B share the layout, C has no bar. No PanelWindow backend
    // loads offscreen, so the windows are checked in the shadow session; BarEditor.keyboard_owner is what their keyboardFocus reads.
    property var checks: []
    function check(name, got, want) {
        root.checks = root.checks.concat([[name, got, want]]);
    }
    readonly property var layout_rule: ({ match: "*", left: ["start", "workspaces"], center: ["clock"], right: ["tray", "volume"] })
    function fake_screen(name, x, bar) {
        return { name: name, model: "M" + name, x: x, y: 0, width: 1920, height: 1080, bar: bar };
    }
    property string real_name: "A"
    function install(screens) {
        BarEditor.tracked_of = s => Object.assign({}, root.layout_rule, s.bar === false ? { bar: false } : {});
        BarEditor.key_of = s => s.model + " @ " + s.name;
        BarEditor.tracked_rules = [];
        BarEditor.focused_name = "B";
        BarEditor.lualine = false;
        BarEditor.screens = screens;
    }
    function standard() {
        return [root.fake_screen(root.real_name, 0, true), root.fake_screen("B", 1920, true), root.fake_screen("C", 3840, false)];
    }
    function keys(list) {
        for (const k of list.split(" ")) BarEditor.press(k);
    }
    function layout() {
        const rule = BarLayout.effective(root.layout_rule, BarSettings.state, "M" + BarEditor.focus_screen + " @ " + BarEditor.focus_screen);
        return BarLayout.layout_of(rule);
    }
    function owners(names) {
        return names.filter(n => BarEditor.keyboard_owner(n));
    }
    function run_editor(name) {
        root.install(root.standard());
        // A throw would otherwise end the scenario with only the checks before it, which all pass.
        try {
            root["scenario_" + name]();
        } catch (e) {
            root.check("scenario ran to the end", String(e), "");
        }
    }
    // req: BAREDIT-01, BAREDIT-02, BAREDIT-03, BAREDIT-08, BAREDIT-10, BAREDIT-04, BAREDIT-09, BAREDIT-11, BAREDIT-12, BAREDIT-13, BAREDIT-14, BAREDIT-20, BAREDIT-21 (position_source only) the key flows through the dispatcher.
    function scenario_keys() {
        const A = root.real_name;
        root.check("monitors skip the one with no bar", BarEditor.monitors.map(m => m.name), [A, "B"]);
        root.check("opens on the focused monitor in NORMAL", [BarEditor.open(""), BarEditor.mode, BarEditor.focus_screen, BarEditor.selected], [true, "normal", "B", "start"]);
        BarEditor.close();
        BarEditor.focused_name = "C";
        root.check("a focused monitor with no bar falls back to the first one", [BarEditor.open(""), BarEditor.focus_screen], [true, A]);
        BarEditor.close();
        BarEditor.focused_name = "B";
        BarEditor.open("");
        root.keys("l");
        root.check("l selects the next module", BarEditor.selected, "workspaces");
        root.keys("l l l l l l l");
        root.check("l stops at the last module", BarEditor.selected, "volume");
        root.keys("h h h h h h h h");
        root.check("h stops at the first module", BarEditor.selected, "start");
        root.keys("l L");
        root.check("L moves the module across into center", root.layout(), { left: ["start"], center: ["workspaces", "clock"], right: ["tray", "volume"] });
        root.check("a move on a shared layout writes the shared layout", [Object.keys(BarSettings.state.monitors), BarSettings.state.shared.order.length > 0], [[], true]);
        root.keys("x");
        root.check("x hides the selected module and selects its neighbor", [root.layout().center, BarEditor.selected], [["clock"], "clock"]);
        root.check("x never purges: the module is listed hidden", BarEditor.hidden_list.indexOf("workspaces") >= 0, true);
        root.keys("u");
        root.check("u undoes the hide", root.layout().center, ["workspaces", "clock"]);
        root.keys("Ctrl+r");
        root.check("Ctrl+r redoes it", root.layout().center, ["clock"]);
        const before_a = JSON.stringify(BarSettings.state);
        root.keys("a");
        root.check("a does nothing (the add prompt is retired)", [JSON.stringify(BarSettings.state) === before_a, BarEditor.mode], [true, "normal"]);
        root.keys("u u u");
        root.check("u past the start of the session does nothing more", [root.layout(), BarEditor.undo_stack.length], [{ left: ["start", "workspaces"], center: ["clock"], right: ["tray", "volume"] }, 0]);
        root.keys("l L u");
        root.keys("L");
        root.check("a new edit clears redo", BarEditor.redo_stack.length, 0);
        BarEditor.close();
        BarEditor.open("B");
        root.keys("Tab");
        root.check("Tab shows the hidden modules", [BarEditor.mode, BarEditor.hidden_list.indexOf("battery") >= 0], ["hidden", true]);
        root.keys("l l l");
        BarEditor.hidden_selected = "battery";
        const before = JSON.stringify(BarSettings.state);
        root.keys("Enter");
        root.check("Enter picks the hidden module up onto the bar", [BarEditor.picked, root.layout().right.indexOf("battery") >= 0], ["battery", true]);
        root.keys("h");
        root.keys("Esc");
        root.check("Esc while carrying cancels with nothing changed", [JSON.stringify(BarSettings.state) === before, BarEditor.picked, BarEditor.mode, BarEditor.undo_stack.length], [true, "", "hidden", 0]);
        root.keys("Enter h h Enter");
        root.check("h/l place the carried module and Enter drops it, back in NORMAL", [BarEditor.mode, BarEditor.selected, root.layout().right.indexOf("battery") >= 0 || root.layout().center.indexOf("battery") >= 0], ["normal", "battery", true]);
        root.check("the whole pick-up is one undo step", BarEditor.undo_stack.length, 1);
        root.keys("u");
        root.check("u removes the placed module again", JSON.stringify(BarSettings.state) === before, true);
        BarEditor.close();
        BarEditor.open("B");
        root.keys("V l");
        root.check("VISUAL l moves a sharing monitor's bar edge in the shared setting", [BarEditor.mode, BarSettings.state.shared.position, BarEditor.screen_key in BarSettings.state.positions], ["visual", "right", false]);
        root.keys("j");
        root.check("VISUAL j is the bottom edge", BarSettings.state.shared.position, "bottom");
        root.keys("x");
        root.check("VISUAL x forgets the shared position, no prompt", ["position" in BarSettings.state.shared, BarEditor.position_source, BarEditor.position_edge, BarEditor.mode], [false, "default", "top", "visual"]);
        root.keys("u");
        root.check("VISUAL u undoes the forget", [BarSettings.state.shared.position, BarEditor.position_source], ["bottom", "global"]);
        root.keys("Ctrl+r");
        root.check("VISUAL Ctrl+R redoes it", "position" in BarSettings.state.shared, false);
        const steps = BarEditor.undo_stack.length;
        root.keys("x");
        root.check("VISUAL x with nothing saved is not an undo step", BarEditor.undo_stack.length, steps);
        root.keys("u");
        root.keys("j");
        root.check("hint state: the edge follows a move", [BarEditor.position_edge, BarEditor.position_source, BarEditor.can_forget], ["bottom", "global", true]);
        const saved_state = BarSettings.state;
        BarSettings.set_state(BarLayout.set_position(saved_state, BarEditor.screen_key, "left"));
        root.check("a stale own position outranks the shared one", [BarEditor.position_edge, BarEditor.position_source], ["left", "monitor"]);
        root.keys("x");
        root.check("VISUAL x on a sharing monitor clears the shared and its stale own position", [BarEditor.screen_key in BarSettings.state.positions, "position" in BarSettings.state.shared, BarEditor.position_source], [false, false, "default"]);
        root.keys("u");
        root.check("VISUAL u restores both", [BarSettings.state.positions[BarEditor.screen_key], BarSettings.state.shared.position], ["left", "bottom"]);
        BarSettings.set_state(saved_state);
        root.keys("Esc");
        root.check("Esc leaves VISUAL for NORMAL", BarEditor.mode, "normal");
        root.keys("o V k");
        root.check("a monitor with its own layout moves only its own edge", [BarSettings.state.positions[BarEditor.screen_key], BarSettings.state.shared.position], ["top", "bottom"]);
        root.keys("x");
        root.check("VISUAL x on an own layout clears only its own position", [BarEditor.screen_key in BarSettings.state.positions, BarSettings.state.shared.position, BarEditor.position_source], [false, "bottom", "global"]);
        root.keys("u");
        root.check("VISUAL u restores the own position", BarSettings.state.positions[BarEditor.screen_key], "top");
        root.keys("Ctrl+r");
        root.check("VISUAL Ctrl+R redoes the own-layout forget", [BarEditor.screen_key in BarSettings.state.positions, BarSettings.state.shared.position], [false, "bottom"]);
        root.keys("c");
        root.check("VISUAL c on an own layout sets only that layout's compact", [BarSettings.state.monitors[BarEditor.screen_key].compact, "compact" in BarSettings.state.shared], [true, false]);
        root.keys("Enter o V c");
        root.check("VISUAL c on a sharing monitor sets the shared compact", [BarSettings.state.shared.compact, Object.keys(BarSettings.state.monitors)], [true, []]);
        root.keys("c");
        root.check("VISUAL c again clears the shared compact, so every rule's own compact applies again", ["compact" in BarSettings.state.shared, Object.keys(BarSettings.state.monitors)], [false, []]);
        const portrait_scale = Math.min(520 / 1080, BarEditor.map_height(1080, 1920) / 1920);
        root.check("monitor select's map leaves a portrait monitor's tile room for its tag", [BarEditor.map_height(5760, 1080), 1080 * portrait_scale >= 150], [130, true]);
        BarEditor.tracked_rules = [{ match: { name: "D" }, compact: true }];
        root.keys("c c");
        root.check("VISUAL c keeps the shared compact when a disconnected monitor's rule gives the other value", [BarSettings.state.shared.compact], [false]);
        BarEditor.tracked_rules = [];
        root.keys("c c Enter");
        BarEditor.selected = "start";
        root.keys(Array(root.layout().left.length + root.layout().center.length + 1).join("l "));
        root.check("selection walks across the sides in bar order", BarEditor.selected, root.layout().right[0]);
        root.keys("Esc");
        root.check("Esc in NORMAL goes up to monitor select", BarEditor.mode, "monitor");
        root.keys("h");
        root.check("h picks the monitor to the left", BarEditor.focus_screen, A);
        root.keys("l l");
        root.check("l picks the monitor to the right and stops at the last", BarEditor.focus_screen, "B");
        root.keys("Enter");
        root.check("Enter edits that monitor's bar", [BarEditor.mode, BarEditor.focus_screen], ["normal", "B"]);
        root.keys("?");
        root.check("? opens the help and swallows the next key", [BarEditor.help_open, BarEditor.press("l")], [true, true]);
        root.keys("?");
        root.check("? closes it again", BarEditor.help_open, false);
        root.keys("Esc");
        root.keys("Esc");
        root.check("Esc at monitor select closes the editor", [BarEditor.active, BarEditor.focus_screen], [false, ""]);
        BarEditor.open("B");
        root.keys("q");
        root.check("q closes from NORMAL", BarEditor.active, false);
        BarEditor.open("B");
        root.keys("? q");
        root.check("q closes the editor even with the help open", BarEditor.active, false);
        BarEditor.open("B");
        root.keys("Esc q");
        root.check("q closes from monitor select", BarEditor.active, false);
        BarEditor.open("B");
        root.keys("V q");
        root.check("q closes from VISUAL", BarEditor.active, false);
        BarEditor.open("B");
        root.stamp();
        const clean = JSON.stringify(BarSettings.state);
        root.keys("Tab");
        BarEditor.hidden_selected = "battery";
        root.keys("Enter");
        root.check("carrying a module", BarEditor.picked, "battery");
        root.keys("q");
        root.check("q while carrying closes the editor and puts the module back", [BarEditor.active, BarEditor.picked, JSON.stringify(BarSettings.state) === clean], [false, "", true]);
    }

    // req: BAREDIT-13, BAREDIT-22 the HIDDEN tray lists argument variants; system and system:cpu are one module.
    function scenario_hidden_add() {
        BarEditor.tracked_of = s => ({ match: "*", left: [], center: [], right: ["tray", "system"] });
        BarEditor.open("B");
        root.keys("o");
        root.keys("Tab");
        root.check("Tab lists the variants not on the bar, never system:cpu", [BarEditor.hidden_list.indexOf("system:memory") >= 0, BarEditor.hidden_list.indexOf("system:temperature") >= 0, BarEditor.hidden_list.indexOf("system:cpu"), BarEditor.hidden_list.indexOf("system")], [true, true, -1, -1]);
        BarEditor.hidden_selected = "system:memory";
        root.keys("Enter h");
        root.check("a picked variant is carried on the bar", [BarEditor.picked, BarEditor.view.right.indexOf("system:memory") >= 0], ["system:memory", true]);
        root.keys("Enter");
        root.check("Enter drops it and selects it in NORMAL", [BarEditor.mode, BarEditor.selected, BarEditor.view.right.length], ["normal", "system:memory", 3]);
        root.keys("Tab");
        root.check("it leaves the tray, the other variant stays", [BarEditor.hidden_list.indexOf("system:memory"), BarEditor.hidden_list.indexOf("system:temperature") >= 0], [-1, true]);
        root.keys("Esc");
        root.keys("o");
        root.keys("Tab");
        root.check("back on the shared layout, which lacks it, the tray lists it again", [BarEditor.sharing, BarEditor.hidden_list.indexOf("system:memory") >= 0], [true, true]);
    }

    // What the hint bar's `c` reads now.
    function c_label() {
        const keys = stage_hints.content.groups.reduce((all, g) => all.concat(g.keys), []);
        const c = keys.find(k => k[0] === "c");
        return c ? c[1] : "";
    }

    // A real Bar for monitor B, so a module's own `compact` can be read off its live item.
    Loader {
        id: live_bar
        active: false
        sourceComponent: Bar {
            screen_name: "B"
            width: 1920
            height: 34
            rule: BarLayout.effective(root.layout_rule, BarSettings.state, "MB @ B")
        }
    }

    // req: BAREDIT-25, BAREDIT-26 `c` in NORMAL steps the selected module's own compact; one with no compact form says so.
    function scenario_module_compact() {
        live_bar.active = true;
        BarEditor.open("B");
        BarEditor.selected = "clock";
        const steps = [BarEditor.selected_compact];
        const labels = [root.c_label()];
        const live = [BarItems.item_of("B", "clock").compact];
        for (let i = 0; i < 3; i++) {
            root.keys("c");
            steps.push(BarEditor.selected_compact);
            labels.push(root.c_label());
            live.push(BarItems.item_of("B", "clock").compact);
        }
        root.check("c steps the selected module inherit, on, off, inherit", steps, ["inherit", "on", "off", "inherit"]);
        root.check("the hint's c names each step", labels, ["compact: inherit", "compact: on", "compact: off", "compact: inherit"]);
        root.check("the live clock's compact follows the override, its neighbour stays", [live, BarItems.item_of("B", "tray") !== null, !!BarItems.item_of("B", "tray") && BarItems.item_of("B", "tray").compact], [[false, true, false, false], true, false]);
        root.check("each step is an undo step and the cycle ends where it began", [BarEditor.undo_stack.length, "compact_modules" in BarSettings.state.shared], [3, false]);
        root.keys("c");
        const view = () => BarLayout.effective(root.layout_rule, BarSettings.state, BarEditor.screen_key);
        root.check("on a sharing monitor the override is shared; the clock is compact, its neighbour not", [BarSettings.state.shared.compact_modules, BarLayout.module_compact(view(), "clock"), BarLayout.module_compact(view(), "tray"), BarEditor.compact_marks], [{ clock: true }, true, false, [{ entry: "clock", on: true }]]);
        root.keys("u");
        root.check("u undoes it", ["compact_modules" in BarSettings.state.shared, BarEditor.selected_compact], [false, "inherit"]);
        root.keys("Ctrl+r");
        root.check("Ctrl+r redoes it", BarEditor.selected_compact, "on");
        root.keys("V");
        const visual_off = root.c_label();
        root.keys("c");
        root.check("in VISUAL the hint's c names the bar's compact", [visual_off, root.c_label()], ["compact: off", "compact: on"]);
        root.keys("Enter");
        root.check("the whole bar compact does not touch the override", [BarEditor.bar_compact, BarSettings.state.shared.compact_modules, BarLayout.module_compact(view(), "tray")], [true, { clock: true }, true]);
        root.keys("c");
        root.check("an off override keeps the module out of a compact bar", [BarEditor.selected_compact, BarLayout.module_compact(view(), "clock"), BarLayout.module_compact(view(), "volume")], ["off", false, true]);
        root.keys("o");
        root.check("o copies the overrides into the own layout", BarSettings.state.monitors[BarEditor.screen_key].compact_modules, { clock: false });
        root.keys("c");
        root.check("an own layout's step leaves the shared override alone", [BarEditor.selected_compact, BarSettings.state.shared.compact_modules], ["inherit", { clock: false }]);
        root.keys("o");
        BarEditor.selected = "tray";
        const before = JSON.stringify(BarSettings.state);
        const undo_depth = BarEditor.undo_stack.length;
        root.check("a module with no compact form names none", [BarEditor.selected_compact, root.c_label()], ["none", "compact: none"]);
        root.keys("c");
        root.check("c on it changes nothing and says so", [JSON.stringify(BarSettings.state) === before, BarEditor.undo_stack.length, BarEditor.notice], [true, undo_depth, "tray has no compact form"]);
        root.keys("h");
        root.check("the next key clears the message", BarEditor.notice, "");
        live_bar.active = false;
    }

    // req: BAREDIT-25 a bars.json rule's own per-module compact is what the editor shows and steps from.
    function scenario_rule_compact() {
        const rule = Object.assign({}, root.layout_rule, { compact_modules: { clock: true } });
        BarEditor.tracked_of = s => rule;
        BarEditor.open("B");
        BarEditor.selected = "clock";
        const shown = [BarEditor.selected_compact, BarEditor.compact_marks];
        root.keys("c");
        root.check("the rule's override shows and the first c turns it off", [shown, BarEditor.selected_compact, BarSettings.state.shared.compact_modules], [["on", [{ entry: "clock", on: true }]], "off", { clock: false }]);
    }

    // req: BAREDIT-22 nothing left to add.
    function scenario_hidden_empty() {
        const everything = BarLayout.known.filter(e => e !== "cava").concat(["system:memory", "system:temperature"]);
        BarEditor.tracked_of = s => ({ match: "*", left: everything, center: [], right: [] });
        BarEditor.open("B");
        root.keys("Tab");
        root.check("a bar with every module and variant has nothing to add", [BarEditor.mode, BarEditor.hidden_list, BarEditor.hidden_selected], ["hidden", [], ""]);
        root.keys("Enter");
        root.check("Enter with nothing selected changes nothing", [BarEditor.picked, BarEditor.undo_stack.length], ["", 0]);
    }

    // The keys the hint bar lists for a mode are the keys that mode acts on: each key is pressed from a fresh fixture, and the
    // ones that change anything must be exactly HintData's list.
    readonly property var probe_keys: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ?".split("").concat(["Tab", "Enter", "Esc", "Ctrl+r", "Backspace"])
    function snapshot() {
        return JSON.stringify([BarSettings.state, BarEditor.mode, BarEditor.active, BarEditor.help_open, BarEditor.focus_screen, BarEditor.selected, BarEditor.hidden_selected, BarEditor.picked, BarEditor.undo_stack.length, BarEditor.redo_stack.length, BarEditor.notice]);
    }
    // A fresh editor in `mode` with something to undo and redo and every key's target in reach.
    function hint_fixture(mode, vertical, saved_edge) {
        BarEditor.close();
        BarSettings.set_state(BarLayout.normalize(null));
        const plus = [["N", 1920, -1080], ["W", 0, 0], ["B", 1920, 0], ["E", 3840, 0], ["S", 1920, 1080]];
        root.install(plus.map(p => Object.assign(root.fake_screen(p[0], p[1], true), { y: p[2] })));
        BarEditor.tracked_of = s => Object.assign({}, root.layout_rule, vertical ? { position: "left" } : {});
        BarEditor.open("B");
        if (mode === "visual" && saved_edge) root.keys("V l Enter");
        root.keys("l l L H u");
        if (mode === "monitor") root.keys("Esc");
        if (mode === "hidden") {
            root.keys("Tab");
            BarEditor.hidden_selected = BarEditor.hidden_list[2];
        }
        if (mode === "carrying") {
            root.keys("Tab");
            BarEditor.hidden_selected = "battery";
            root.keys("Enter h");
        }
        if (mode === "visual") root.keys("V");
    }
    function check_hint_keys(label, mode, vertical, saved_edge) {
        const carrying = mode === "carrying";
        const real = carrying ? "hidden" : mode;
        const accepted = [];
        for (const k of root.probe_keys) {
            root.hint_fixture(mode, vertical, saved_edge);
            const before = root.snapshot();
            BarEditor.press(k);
            if (root.snapshot() !== before) accepted.push(k);
        }
        root.hint_fixture(mode, vertical, saved_edge);
        const listed = HintData.keys_of(HintData.groups(real, carrying, BarEditor.vertical, BarEditor.can_forget));
        // The saved edge's own key is the one hjkl press that changes nothing.
        root.check(label + ": the hint bar lists exactly the keys that act", listed.filter(k => !(saved_edge && k === "l")).sort(), accepted.filter(k => !(saved_edge && k === "l")).sort());
    }
    // req: BAREDIT-23
    function scenario_hint_keys() {
        root.check_hint_keys("monitor select", "monitor", false, false);
        root.check_hint_keys("NORMAL on a row", "normal", false, false);
        root.check_hint_keys("NORMAL on a column", "normal", true, false);
        root.check_hint_keys("HIDDEN", "hidden", false, false);
        root.check_hint_keys("HIDDEN carrying a module", "carrying", false, false);
        root.check_hint_keys("VISUAL with nothing saved", "visual", false, false);
        root.check_hint_keys("VISUAL with a saved edge", "visual", false, true);
    }

    // The window cannot load offscreen, so the hint plate is checked on a stand-in screen-sized parent.
    Item {
        id: stage
        width: 1920
        height: 1080
        HintBox { id: stage_hints }
    }
    // req: BAREDIT-24
    function scenario_hint_edge() {
        BarEditor.open("B");
        root.keys("V");
        const plate = stage_hints;
        const fresh_height = plate.content.implicitHeight + 16;
        stage_hints.on_top = false;
        root.check("bar on top: hints at the bottom edge at their own height", [plate.height, plate.y], [fresh_height, 1080 - fresh_height - 24]);
        root.keys("j");
        stage_hints.on_top = true;
        root.check("j moves the bar to the bottom: hints at the top at their own height", [plate.height, plate.y], [fresh_height, 24]);
        root.keys("k");
        stage_hints.on_top = false;
        root.check("k moves it back: hints return to the bottom, not stretched", [plate.height, plate.y], [fresh_height, 1080 - fresh_height - 24]);
    }

    // req: BAREDIT-12, BAREDIT-13
    function scenario_pick_redo() {
        BarEditor.open("B");
        root.keys("l L u");
        root.check("one redo step waiting", BarEditor.redo_stack.length, 1);
        root.keys("Tab");
        BarEditor.hidden_selected = "battery";
        root.keys("Enter");
        root.keys("Esc");
        root.check("Esc after a pick-up keeps the redo stack", [BarEditor.picked, BarEditor.redo_stack.length], ["", 1]);
        root.keys("Esc");
        root.check("leaving HIDDEN after a cancelled pick-up selects a module on the bar", BarEditor.order.indexOf(BarEditor.selected) >= 0, true);
        root.keys("Ctrl+r");
        root.check("and the redo still works", root.layout().center, ["workspaces", "clock"]);
    }


    // req: BAREDIT-15 one screen owns the keyboard, and it follows the picked monitor.
    function scenario_ownership() {
        const names = ["A", "B", "C"];
        root.check("nothing owns the keyboard before opening", root.owners(names), []);
        BarEditor.open("A");
        root.check("opening gives the keyboard to exactly one screen", root.owners(names), ["A"]);
        root.keys("Esc");
        root.keys("l");
        root.check("monitor select hands it to the picked monitor and releases the old one", [root.owners(names), BarEditor.mode], [["B"], "monitor"]);
        root.keys("l");
        root.check("a pick past the last monitor keeps one owner", root.owners(names), ["B"]);
        root.keys("h");
        root.check("and back again", root.owners(names), ["A"]);
        root.keys("Enter");
        root.check("entering NORMAL keeps the owner", root.owners(names), ["A"]);
        root.keys("q");
        root.check("q releases the keyboard on every screen", [root.owners(names), BarEditor.active], [[], false]);
        BarEditor.open("B");
        root.keys("Esc");
        root.keys("Esc");
        root.check("Esc at monitor select releases it too", root.owners(names), []);
        BarEditor.open("B");
        BarEditor.close();
        root.check("close (the IPC path) releases it", [root.owners(names), BarEditor.focus_screen], [[], ""]);
        BarEditor.open("C");
        root.check("a monitor with no bar never owns it", root.owners(names).indexOf("C"), -1);
        BarEditor.close();
        root.check("a key while closed is not taken", BarEditor.press("l"), false);
    }

    // req: BAREDIT-18 a popup and the editor never both hold the keyboard.
    function scenario_popups() {
        const names = ["A", "B", "C"];
        Popups.open("settings", null, undefined, "B");
        root.check("a popup holds the keyboard before the editor opens", Popups.open_name, "settings");
        root.check("opening the editor closes the popup and takes the keyboard", [BarEditor.open("B"), Popups.open_name, root.owners(names)], [true, "", ["B"]]);
        // A popup that takes the keyboard: the check runs a turn later, once a hover open has said it takes none.
        Popups.open("clock", null, undefined, "B");
    }

    function scenario_popups_after() {
        root.check("a popup opened under the editor that takes the keyboard closes the editor", [BarEditor.active, root.owners(["A", "B", "C"])], [false, []]);
        root.check("keys after that are not taken", BarEditor.press("x"), false);
        Popups.close();
        BarEditor.open("B");
        Popups.open("clock", null, undefined, "B");
        Popups.keyboard_off = true;
    }

    function scenario_popups_hover() {
        root.check("a hover-opened popup takes no keyboard, so the editor stays", BarEditor.active, true);
        Popups.close();
        Popups.open("clock", null, undefined, "B", "", true);
    }

    function scenario_popups_hands_off() {
        root.check("a hands-off popup (IPC view) takes no keyboard, so the editor stays", BarEditor.active, true);
        root.keys("a");
        Popups.close();
        root.check("closing a popup that is not open leaves the editor alone", BarEditor.active, true);
    }

    // set_state stamps cava_migrated, so a state captured before the first edit differs from the same layout after one.
    function stamp() {
        BarSettings.set_state(BarSettings.state);
    }

    // req: BAREDIT-19 monitors added or removed while open.
    function scenario_monitors() {
        root.stamp();
        BarEditor.open("B");
        root.check("starts on B", BarEditor.focus_screen, "B");
        BarEditor.screens = [root.fake_screen("A", 0, true), root.fake_screen("C", 3840, false)];
        root.check("the picked monitor going away drops to monitor select on a remaining one", [BarEditor.active, BarEditor.mode, BarEditor.focus_screen], [true, "monitor", "A"]);
        root.check("and the keyboard follows", root.owners(["A", "B", "C"]), ["A"]);
        BarEditor.screens = [root.fake_screen("A", 0, true), root.fake_screen("B", 1920, true), root.fake_screen("C", 3840, false)];
        root.check("a monitor added while open joins monitor select", [BarEditor.monitors.map(m => m.name), BarEditor.focus_screen, BarEditor.active], [["A", "B"], "A", true]);
        root.keys("l");
        root.check("it can be picked", BarEditor.focus_screen, "B");
        BarEditor.screens = [root.fake_screen("A", 0, true), root.fake_screen("B", 1920, true), root.fake_screen("C", 3840, true)];
        root.check("a monitor that gains a bar joins the list", BarEditor.monitors.map(m => m.name), ["A", "B", "C"]);
        root.keys("Enter");
        root.keys("Tab");
        BarEditor.hidden_selected = "battery";
        const before = JSON.stringify(BarSettings.state);
        root.keys("Enter");
        root.check("carrying a module", BarEditor.picked, "battery");
        BarEditor.screens = [root.fake_screen("A", 0, true), root.fake_screen("C", 3840, true)];
        root.check("losing the monitor mid-carry puts the module back and keeps nothing half done", [BarEditor.picked, JSON.stringify(BarSettings.state) === before, BarEditor.mode, BarEditor.focus_screen], ["", true, "monitor", "A"]);
        BarEditor.screens = [root.fake_screen("C", 3840, false)];
        root.check("when no monitor has a bar the editor closes", [BarEditor.active, root.owners(["A", "B", "C"])], [false, []]);
        root.check("and cannot open", BarEditor.open(""), false);
    }

    // req: BAREDIT-07, BAREDIT-12 undo and redo across own-layout toggles.
    function scenario_undo_own() {
        root.stamp();
        BarEditor.open("B");
        const start = JSON.stringify(BarSettings.state);
        const key = "MB @ B";
        root.keys("l L");
        const moved = JSON.stringify(BarSettings.state);
        root.keys("o");
        root.check("o gives B its own copy of what it shows", [key in BarSettings.state.monitors, BarSettings.state.monitors[key].center], [true, ["workspaces", "clock"]]);
        root.keys("L");
        const own_edit = JSON.stringify(BarSettings.state);
        root.check("an edit on the own layout leaves the shared one alone", [JSON.stringify(BarSettings.state.shared.order) === JSON.stringify(JSON.parse(moved).shared.order), BarEditor.sharing], [true, false]);
        root.keys("u");
        root.check("u undoes the own-layout edit", [JSON.stringify(BarSettings.state) !== own_edit, key in BarSettings.state.monitors], [true, true]);
        root.keys("u");
        root.check("u again undoes the switch to an own layout: B shares again", [key in BarSettings.state.monitors, BarEditor.sharing, JSON.stringify(BarSettings.state) === moved], [false, true, true]);
        root.keys("Ctrl+r");
        root.check("Ctrl+r brings the own layout back", [key in BarSettings.state.monitors, BarEditor.sharing], [true, false]);
        root.keys("Ctrl+r");
        root.check("Ctrl+r again redoes the edit", JSON.stringify(BarSettings.state), own_edit);
        root.keys("o");
        root.check("o again returns B to the shared layout", [key in BarSettings.state.monitors, BarEditor.sharing], [false, true]);
        root.keys("u u u u");
        root.check("everything undoes to the start of the session", [JSON.stringify(BarSettings.state) === start, BarEditor.undo_stack.length, BarEditor.redo_stack.length], [true, 0, 4]);
        root.keys("Ctrl+r Ctrl+r Ctrl+r Ctrl+r");
        root.check("and redoes through the toggles to the end", [BarEditor.sharing, BarEditor.redo_stack.length], [true, 0]);
        // Selection survives the layout flipping under it.
        root.keys("u u");
        root.check("selection is still on a module that exists", BarEditor.order.indexOf(BarEditor.selected) >= 0, true);
    }

    readonly property var plans: ({
        editor_ownership: { steps: [[100, () => root.run_editor("ownership")]], end: 500 },
        editor_popups: { steps: [[100, () => root.run_editor("popups")], [300, () => root.scenario_popups_after()], [500, () => root.scenario_popups_hover()], [700, () => root.scenario_popups_hands_off()]], end: 900 },
        editor_hint_keys: { steps: [[100, () => root.run_editor("hint_keys")]], end: 500 },
        editor_hidden_add: { steps: [[100, () => root.run_editor("hidden_add")]], end: 500 },
        editor_rule_compact: { steps: [[100, () => root.run_editor("rule_compact")]], end: 500 },
        editor_module_compact: { steps: [[100, () => root.run_editor("module_compact")]], end: 500 },
        editor_hidden_empty: { steps: [[100, () => root.run_editor("hidden_empty")]], end: 500 },
        editor_hint_edge: { steps: [[100, () => root.run_editor("hint_edge")]], end: 500 },
        editor_pick_redo: { steps: [[100, () => root.run_editor("pick_redo")]], end: 500 },
        editor_monitors: { steps: [[100, () => root.run_editor("monitors")]], end: 500 },
        editor_undo_own: { steps: [[100, () => root.run_editor("undo_own")]], end: 500 },
        editor_keys: { steps: [[100, () => root.run_editor("keys")]], end: 500 },
        idle: { steps: [], end: 400 },
        // The editor moves the bar edge per key press: sets 2 ms apart, each an edit that must survive the previous write's echo.
        visual_rapid: { steps: [[50, () => { root.install(root.standard()); BarEditor.open("B"); BarEditor.press("V"); }]].concat(Array.from({ length: 40 }, (_, i) => [100 + i * 2, () => root.press_edge(i)])), end: 1500 },
        // Driven from outside through `qs ipc`: the stand-in monitors are installed and the shell keeps running.
        ipc: { steps: [[50, () => root.install(root.standard())]], end: 9000, quiet: true },
        // Sets landing before, at and after the echo of the previous write.
        rapid_1ms: { steps: root.spaced(1, 60), end: 1500 },
        rapid_5ms: { steps: root.spaced(5, 60), end: 1500 },
        rapid_20ms: { steps: root.spaced(20, 40), end: 1500 },
        // An edit from outside lands between our sets and must be read; the set after it wins.
        external: { steps: [[100, () => root.set_counter(1)], [400, () => root.outside_write(root.bars_path, '{"shared":{"order":["n50"]},"monitors":{},"positions":{}}')], [900, () => root.set_counter(60)]], end: 1500 }
    })
    readonly property var plan: root.plans[root.scenario] || { steps: [], end: 100 }

    property var edges_seen: []
    function press_edge(i) {
        BarEditor.press(["h", "j", "k", "l"][i % 4]);
    }

    Connections {
        target: BarSettings
        function onStateChanged() {
            const edge = BarSettings.state.shared.position || "";
            if (edge !== "" && root.edges_seen[root.edges_seen.length - 1] !== edge) root.edges_seen = root.edges_seen.concat([edge]);
            root.observed = root.observed.concat([root.counter_of(BarSettings.state)]);
        }
    }

    BarEditorIpc {}

    function finish() {
        result_file.setText(JSON.stringify(root.result));
    }

    FileView {
        id: result_file
        path: Quickshell.env("XDG_STATE_HOME") + "/result.json"
        atomicWrites: true
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    Timer {
        id: clock
        interval: 2
        repeat: true
        running: !!root.plans[root.scenario]
        onTriggered: {
            const elapsed = Date.now() - root.started;
            root.plan.steps.forEach((step, index) => {
                if (elapsed >= step[0] && !root.done_steps[index]) {
                    root.done_steps[index] = true;
                    step[1]();
                }
            });
            if (elapsed >= root.plan.end) {
                clock.stop();
                root.result = { edges_seen: root.edges_seen, final_edge: BarSettings.state.shared.position || "", observed: root.observed, final_k: root.counter_of(BarSettings.state), checks: root.checks };
                root.finish();
            }
        }
    }

    Component.onCompleted: root.started = Date.now()

    // Hard stop so a scenario that never finishes fails on the missing result file instead of hanging.
    Timer {
        interval: 12000
        running: true
        onTriggered: Qt.quit()
    }
}
