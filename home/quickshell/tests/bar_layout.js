// Runs BarLayout.js under node: the bar position a rule, the global setting or a monitor's saved position picks, and how the state file keeps it.
// Both scripts are QML `.pragma library` files; BarLayout's `.import` of BarModules is stood in by loading that first.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const script = rel => fs.readFileSync(path.join(__dirname, "../.config/quickshell", rel), "utf8").replace(/^\.(pragma|import).*$/gm, "");
const modules = vm.createContext({});
vm.runInContext(script("features/bar/BarModules.js"), modules);
const layout = vm.createContext({ BarModules: modules });
vm.runInContext(script("features/bar/BarLayout.js"), layout);
const L = layout;

const side_spans = (start, end, width) => L.lualine_side_spans(start, end, width);
const rule = { match: "*", left: ["start"], center: ["clock"], right: ["tray"] };
const key = "Dell @ DP-1";
const rule3 = { match: "*", left: ["start", "workspaces"], center: ["clock"], right: ["tray", "volume"] };
const rule_sys = { match: "*", left: [], center: [], right: ["tray", "system"] };
const view_of = (r, state) => L.layout_of(L.effective(r, state, ""));
const edited_layout = state => L.layout_of(L.effective(rule3, state, ""));
const plain = obj => JSON.parse(JSON.stringify(obj));

const cases = [
  ["a framed lualine bar leaves its two sides to the frame band", () => side_spans(40, 960, 1000), [[0, 40], [960, 1000]]],
  ["a lualine bar with the frame at the screen edges has no side", () => side_spans(0, 1000, 1000), []],
  ["no position is top", () => L.position_of(rule), "top"],
  ["null rule is top", () => L.position_of(null), "top"],
  ["bottom kept", () => L.position_of({ position: "bottom" }), "bottom"],
  ["left kept", () => L.position_of({ position: "left" }), "left"],
  ["right kept", () => L.position_of({ position: "right" }), "right"],
  ["typo falls back", () => L.position_of({ position: "botom" }), "top"],
  ["no problem without a position", () => L.position_problem(rule), ""],
  ["no problem for bottom", () => L.position_problem({ position: "bottom" }), ""],
  ["no problem for left or right", () => [L.position_problem({ position: "left" }), L.position_problem({ position: "right" })], ["", ""]],
  ["a frame is drawn only on a top, bottom or bar-less screen", () => ["top", "bottom", "", "left", "right"].map(p => L.draws_frame(true, p)), [true, true, true, false, false]],
  ["no frame style draws no frame", () => L.draws_frame(false, "top"), false],
  ["Hyprland gets the frame while any screen draws one", () => [L.any_draws_frame(true, ["left", "top"]), L.any_draws_frame(true, ["left", "right"]), L.any_draws_frame(true, []), L.any_draws_frame(false, ["top"])], [true, false, false, false]],
  ["only left and right are vertical", () => ["top", "bottom", "left", "right", "x"].map(L.is_vertical), [false, false, true, true, false]],
  ["step_position walks top, bottom, left, right and wraps", () => [L.step_position("top", 1), L.step_position("bottom", 1), L.step_position("left", 1), L.step_position("right", 1), L.step_position("top", -1)], ["bottom", "left", "right", "top", "right"]],
  ["popups walk with Ctrl+H/L along a row and Ctrl+K/J down a column", () => ["top", "bottom", "left", "right"].map(L.walk_keys), [{ back: "H", forward: "L" }, { back: "H", forward: "L" }, { back: "K", forward: "J" }, { back: "K", forward: "J" }]],
  ["unknown named", () => L.position_problem({ position: 3 }), "unknown bar position 3 in bars.json; using top"],
  ["normalize keeps a saved position", () => L.normalize({ positions: { [key]: "bottom" } }).positions, { [key]: "bottom" }],
  ["normalize keeps a side position", () => L.normalize({ positions: { [key]: "left", other: 3 } }).positions, { [key]: "left" }],
  ["normalize drops a bad position", () => L.normalize({ positions: { [key]: "diagonal", other: 3 } }).positions, {}],
  ["normalize moves an own layout's position out", () => L.normalize({ monitors: { [key]: { left: [], position: "bottom" } } }), { shared: { place: {}, order: [], last_side: {} }, monitors: { [key]: { left: [], center: [], right: [], last_side: {} } }, positions: { [key]: "bottom" } }],
  ["effective takes the rule's position", () => L.effective(Object.assign({ position: "bottom" }, rule), L.normalize(null), key).position, "bottom"],
  ["saved position wins over the rule", () => L.effective(Object.assign({ position: "bottom" }, rule), L.normalize({ positions: { [key]: "top" } }), key).position, "top"],
  ["saved position applies with an own layout", () => L.effective(rule, L.normalize({ monitors: { [key]: {} }, positions: { [key]: "bottom" } }), key).position, "bottom"],
  ["another monitor's position is ignored", () => L.effective(rule, L.normalize({ positions: { other: "bottom" } }), key).position === undefined, true],
  ["set_position without an own layout", () => plain(L.set_position(L.normalize(null), key, "bottom")), { shared: { place: {}, order: [], last_side: {} }, monitors: {}, positions: { [key]: "bottom" } }],
  ["set_position takes right", () => L.set_position(L.normalize({ positions: { [key]: "bottom" } }), key, "right").positions[key], "right"],
  ["set_position refuses a typo", () => L.set_position(L.normalize({ positions: { [key]: "bottom" } }), key, "diagonal").positions[key], "bottom"],
  ["own layout on keeps the position", () => L.set_own(L.set_position(L.normalize(null), key, "bottom"), key, rule, false).positions[key], "bottom"],
  ["own layout off keeps the position", () => L.drop_own(L.set_own(L.set_position(L.normalize(null), key, "bottom"), key, rule, false), key).positions[key], "bottom"],
  ["set_own writes no position", () => "position" in L.set_own(L.normalize(null), key, rule, false).monitors[key], false],
  ["a position key is reused after a connector change", () => L.resolve_key(L.normalize({ positions: { "Dell @ DP-1": "bottom" } }), "Dell", "DP-2", [{ name: "DP-2", description: "Dell" }]), "Dell @ DP-1"],
  ["position survives a round trip", () => L.normalize(plain(L.set_position(L.normalize(null), key, "bottom"))).positions, { [key]: "bottom" }],
  ["normalize keeps a shared position", () => L.normalize({ shared: { position: "bottom" } }).shared.position, "bottom"],
  ["normalize drops a bad shared position", () => "position" in L.normalize({ shared: { position: "diagonal" } }).shared, false],
  ["shared position wins over the rule", () => L.effective(Object.assign({ position: "top" }, rule), L.set_shared_position(L.normalize(null), "bottom"), key).position, "bottom"],
  ["shared position applies with no key", () => L.effective(rule, L.set_shared_position(L.normalize(null), "bottom"), "").position, "bottom"],
  ["shared position applies with an own layout", () => L.effective(rule, L.normalize({ shared: { position: "bottom" }, monitors: { [key]: {} } }), key).position, "bottom"],
  ["monitor position wins over the shared one", () => L.effective(rule, L.normalize({ shared: { position: "bottom" }, positions: { [key]: "top" } }), key).position, "top"],
  ["source is monitor", () => L.position_source(rule, L.normalize({ shared: { position: "bottom" }, positions: { [key]: "top" } }), key), "monitor"],
  ["source is global", () => L.position_source(Object.assign({ position: "top" }, rule), L.normalize({ shared: { position: "bottom" } }), key), "global"],
  ["source is bars.json", () => L.position_source(Object.assign({ position: "bottom" }, rule), L.normalize(null), key), "bars.json"],
  ["source is default", () => L.position_source(rule, L.normalize(null), key), "default"],
  ["clearing a monitor follows the shared one", () => L.effective(rule, L.clear_position(L.normalize({ shared: { position: "bottom" }, positions: { [key]: "top" } }), key), key).position, "bottom"],
  ["clearing a monitor leaves the others", () => L.clear_position(L.normalize({ positions: { [key]: "top", other: "bottom" } }), key).positions, { other: "bottom" }],
  ["clearing the shared one follows the rule", () => L.effective(Object.assign({ position: "bottom" }, rule), L.clear_shared_position(L.set_shared_position(L.normalize(null), "top")), key).position, "bottom"],
  ["set_shared_position takes left", () => L.set_shared_position(L.normalize({ shared: { position: "bottom" } }), "left").shared.position, "left"],
  ["set_shared_position refuses a typo", () => L.set_shared_position(L.normalize({ shared: { position: "bottom" } }), "diagonal").shared.position, "bottom"],
  ["layout edits keep the shared position", () => L.edit(rule, L.normalize({ shared: { position: "bottom" } }), "", { type: "hide", entry: "clock" }).shared.position, "bottom"],
  ["shared position survives a round trip", () => L.normalize(plain(L.set_shared_position(L.normalize(null), "bottom"))).shared, { place: {}, order: [], last_side: {}, position: "bottom" }],
  ["directory is a known module", () => L.known.indexOf("directory") >= 0 && modules.find("directory").file, "Directory.qml"],
  ["directory switches default to all on", () => L.directory_switches(L.normalize(null)), { app_name: true, path: true, file_name: true }],
  ["a flipped switch is saved and the others stay on", () => L.directory_switches(L.set_directory_switch(L.normalize(null), "path", false)), { app_name: true, path: false, file_name: true }],
  ["a switch turns back on", () => L.directory_switches(L.set_directory_switch(L.set_directory_switch(L.normalize(null), "path", false), "path", true)).path, true],
  ["an unknown switch is ignored", () => "bogus" in (L.set_directory_switch(L.normalize(null), "bogus", false).directory || {}), false],
  ["switches survive a round trip", () => L.directory_switches(L.normalize(plain(L.set_directory_switch(L.normalize(null), "file_name", false)))).file_name, false],
  ["normalize drops non-boolean switches", () => L.directory_switches(L.normalize({ directory: { path: "no", app_name: false } })), { app_name: false, path: true, file_name: true }],
  ["layout edits keep the switches", () => L.directory_switches(L.edit(rule, L.set_directory_switch(L.normalize(null), "app_name", false), "", { type: "hide", entry: "clock" })).app_name, false],
  ["lualine draws the directory itself, with or without an argument", () => [L.lualine_draws_itself("directory"), L.lualine_draws_itself("directory:x"), L.lualine_draws_itself("clock")], [true, true, false]],
  ["lualine draws cava itself too", () => L.lualine_draws_itself("cava"), true],
  ["a rule lists cava on any side, so lualine still shows it", () => [L.rule_lists({ left: [], center: ["clock"], right: ["cava"] }, "cava"), L.rule_lists({ left: ["cava"] }, "cava"), L.rule_lists(rule, "cava"), L.rule_lists(null, "cava")], [true, true, false, false]],
  ["a state without switches has no directory key", () => "directory" in L.normalize(null), false],
  ["cava is a registered module", () => L.known.indexOf("cava") >= 0, true],
  ["cava sits in the lualine x section", () => L.lualine_section("cava"), "x"],
  ["migrate adds media after workspaces", () => L.migrate_cava({ monitors: { [key]: { left: ["start", "workspaces", "cmdstatus"], center: ["clock"], right: [] } } }).monitors[key].left, ["start", "workspaces", "media", "cmdstatus"]],
  ["migrate appends to left without workspaces", () => L.migrate_cava({ monitors: { [key]: { left: ["start"], center: [], right: [] } } }).monitors[key].left, ["start", "media"]],
  ["migrate keeps a cava already listed, in any side", () => L.migrate_cava({ monitors: { [key]: { left: ["workspaces"], center: [], right: ["cava"] } } }).monitors[key], { left: ["workspaces"], center: [], right: ["cava"], last_side: {} }],
  ["migrate sets the flag, and normalize keeps it", () => L.normalize(plain(L.migrate_cava(L.normalize(null)))).cava_migrated, true],
  ["migrate runs once: a removed cava stays removed", () => L.migrate_cava({ cava_migrated: true, monitors: { [key]: { left: ["workspaces"], center: [], right: [] } } }).monitors[key].left, ["workspaces"]],
  ["normalize without the flag adds none", () => "cava_migrated" in L.normalize(null), false],
  ["shared layouts are untouched by migrate", () => L.migrate_cava({ shared: { place: { clock: "left" } } }).shared.place, { clock: "left" }],
  ["migrate keeps the directory switches", () => L.directory_switches(L.migrate_cava(L.normalize({ directory: { path: false }, monitors: { [key]: { left: ["workspaces"], center: [], right: [] } } }))), { app_name: true, path: false, file_name: true }],
  ["migrate covers every monitor with its own layout", () => Object.values(L.migrate_cava({ monitors: { a: { left: ["workspaces"], center: [], right: [] }, b: { left: ["start"], center: [], right: ["cava"] }, c: { left: [], center: [], right: [] } } }).monitors).map(m => m.left.concat(m.right)), [["workspaces", "media"], ["start", "cava"], ["media"]]],
  // The cava -> media rename of the state file.
  ["cava only: renamed in place on every side, in order, place and last_side", () => L.migrate_cava_to_media({ cava_migrated: true, shared: { place: { cava: "left", clock: "center" }, order: ["start", "cava", "clock"], last_side: { cava: { side: "left", index: 2 } } }, monitors: { [key]: { left: ["workspaces", "cava"], center: ["clock"], right: ["tray"], last_side: { cava: "left" } } } }),
    { shared: { place: { clock: "center", media: "left" }, order: ["start", "media", "clock"], last_side: { media: { side: "left", index: 2 } } }, monitors: { [key]: { left: ["workspaces", "media"], center: ["clock"], right: ["tray"], last_side: { media: { side: "left", index: -1 } } } }, positions: {}, cava_migrated: true }],
  ["media only: the very same object comes back, untouched", () => { const s = { shared: { place: { media: "left" }, order: ["media"], last_side: {} }, monitors: { [key]: { left: ["media"], center: [], right: [], last_side: {} } }, positions: {} }; return L.migrate_cava_to_media(s) === s; }, true],
  ["both in one section: keep media, drop cava, wherever cava sat", () => [L.migrate_cava_to_media({ monitors: { [key]: { left: ["cava", "start", "media"], center: [], right: [] } } }).monitors[key].left, L.migrate_cava_to_media({ monitors: { [key]: { left: ["media", "start", "cava"], center: [], right: [] } } }).monitors[key].left], [["start", "media"], ["media", "start"]]],
  ["both in place: media's own value wins", () => L.migrate_cava_to_media({ shared: { place: { cava: "left", media: "hidden" } } }).shared.place, { media: "hidden" }],
  ["a missing file (null) has nothing to migrate and is not rewritten", () => { const s = L.normalize(null); return [L.has_cava(null), L.migrate_cava_to_media(null) === null, L.migrate_cava_to_media(s) === s]; }, [false, true, true]],
  ["a layout without cava is returned untouched", () => { const s = L.normalize({ monitors: { [key]: { left: ["workspaces"], center: [], right: [] } } }); return L.migrate_cava_to_media(s) === s; }, true],
  ["cava stays accepted but is not offered in the picker", () => [L.known.indexOf("cava") >= 0, L.hidden_entries([], L.normalize(null), { left: [], center: [], right: [] }).indexOf("cava") >= 0, L.hidden_entries([], L.normalize(null), { left: [], center: [], right: [] }).indexOf("media") >= 0], [true, false, true]],

  // The bar thickness: the rule's height wins, a side bar may use the style's vertical one, the top bar never does.
  ["bars.json height beats every style value", () => [["top", 30], ["left", 30]].map(([p, h]) => L.thickness_for(h, 24, 34, p, 34)), [30, 30]],
  ["a side bar takes the style's vertical thickness, the top bar its plain one", () => ["top", "bottom", "left", "right"].map(p => L.thickness_for(0, 24, 34, p, 40)), [24, 24, 34, 34]],
  ["a style with no vertical thickness keeps one thickness on every edge", () => ["top", "left"].map(p => L.thickness_for(0, 24, 0, p, 40)), [24, 24]],
  ["a style with no thickness at all falls back to the default", () => ["top", "right"].map(p => L.thickness_for(0, 0, 0, p, 40)), [40, 40]],
  // How much screen height a bar takes: a side bar takes width instead.
  ["a top or bottom bar takes its thickness and the float gap from the height", () => ["top", "bottom"].map(p => L.vertical_reserve(p, 34, 8)), [42, 42]],
  ["a side bar takes none of the height", () => ["left", "right"].map(p => L.vertical_reserve(p, 34, 8)), [0, 0]],

  // The bar editor's pure edit steps.
  // req: BAREDIT-04 selection order: sides in order on a plain bar; a lualine bar draws center and right by section, and leaves out what it draws itself.
  ["nav order on a plain bar is left, center, right", () => L.nav_order({ left: ["start", "workspaces"], center: ["clock"], right: ["tray", "volume"] }, false), ["start", "workspaces", "clock", "tray", "volume"]],
  ["nav order on a lualine bar sorts center and right by section and skips directory", () => L.nav_order({ left: ["start"], center: ["clock"], right: ["bluetooth", "tray", "directory"] }, true), ["start", "tray", "bluetooth", "clock"]],
  ["nav order skips modules the bar does not know", () => L.nav_order({ left: ["start", "nope"], center: [], right: [] }, false), ["start"]],
  ["nav_step clamps at both ends", () => [L.nav_step(["a", "b", "c"], "a", -1), L.nav_step(["a", "b", "c"], "c", 1), L.nav_step(["a", "b", "c"], "b", 1), L.nav_step(["a", "b"], "gone", 1)], ["a", "c", "c", "a"]],
  // req: BAREDIT-05, BAREDIT-06 moving
  ["move_step swaps within a side on the shared layout", () => edited_layout(L.move_step(rule3, L.normalize(null), "", "volume", -1, false)), { left: ["start", "workspaces"], center: ["clock"], right: ["volume", "tray"] }],
  ["move_step on the shared layout writes the shared layout only", () => Object.keys(L.move_step(rule3, L.normalize(null), "", "volume", -1, false).monitors), []],
  ["another sharing monitor sees the move", () => L.layout_of(L.effective(rule3, L.move_step(rule3, L.normalize(null), key, "volume", -1, false), "Other @ DP-2")).right, ["volume", "tray"]],
  ["move_step crosses from the end of left into center", () => edited_layout(L.move_step(rule3, L.normalize(null), "", "workspaces", 1, false)), { left: ["start"], center: ["workspaces", "clock"], right: ["tray", "volume"] }],
  ["move_step crosses from the end of center into right", () => edited_layout(L.move_step(rule3, L.normalize(null), "", "clock", 1, false)), { left: ["start", "workspaces"], center: [], right: ["clock", "tray", "volume"] }],
  ["move_step crosses back from the start of right to the end of center", () => edited_layout(L.move_step(rule3, L.normalize(null), "", "tray", -1, false)), { left: ["start", "workspaces"], center: ["clock", "tray"], right: ["volume"] }],
  ["move_step stops at the first and last side", () => [L.move_step(rule3, L.normalize(null), "", "start", -1, false), L.move_step(rule3, L.normalize(null), "", "volume", 1, false)].map(s => JSON.stringify(s) === JSON.stringify(L.normalize(null))), [true, true]],
  ["move_step on an own layout leaves the shared layout alone", () => { const s = L.move_step(rule3, L.set_own(L.normalize(null), key, rule3, false), key, "volume", -1, false); return [s.monitors[key].right, s.shared.order]; }, [["volume", "tray"], []]],
  ["a lualine move refuses to swap across sections", () => { const r = { left: [], center: [], right: ["tray", "bluetooth"] }; const s = L.set_own(L.normalize(null), key, r, false); return L.move_step(r, s, key, "tray", 1, true).monitors[key].right; }, ["tray", "bluetooth"]],
  ["a lualine move swaps inside a section", () => { const r = { left: [], center: [], right: ["tray", "volume", "bluetooth"] }; const s = L.set_own(L.normalize(null), key, r, false); return L.move_step(r, s, key, "tray", 1, true).monitors[key].right; }, ["volume", "tray", "bluetooth"]],
  ["a lualine move leaves the left side unsectioned", () => { const r = { left: ["start", "bluetooth"], center: [], right: [] }; const s = L.set_own(L.normalize(null), key, r, false); return L.move_step(r, s, key, "start", 1, true).monitors[key].left; }, ["bluetooth", "start"]],
  ["a lualine move across sides lands in the sorted island", () => { const r = { left: [], center: ["clock"], right: ["tray"] }; const s = L.set_own(L.normalize(null), key, r, false); return L.nav_order(L.layout_of(L.effective(r, L.move_step(r, s, key, "clock", 1, true), key)), true); }, ["tray", "clock"]],
  // req: BAREDIT-07
  ["toggle_own copies the effective layout and compact", () => { const s = L.toggle_own(rule3, L.normalize(null), key); return [s.monitors[key].left, s.monitors[key].right, s.monitors[key].compact]; }, [["start", "workspaces"], ["tray", "volume"], false]],
  ["toggle_own keeps the shared edits it copied", () => L.toggle_own(rule3, L.move_step(rule3, L.normalize(null), "", "volume", -1, false), key).monitors[key].right, ["volume", "tray"]],
  ["toggle_own twice returns to the same state", () => L.toggle_own(rule3, L.toggle_own(rule3, L.normalize(null), key), key), L.normalize(null)],
  // req: BAREDIT-08
  ["compact on a sharing monitor sets the shared compact", () => { const s = L.toggle_compact(rule3, L.normalize(null), key); return [s.shared.compact, Object.keys(s.monitors), L.effective(rule3, s, "Other @ DP-2").compact]; }, [true, [], true]],
  ["compact on a sharing monitor flips it back and leaves no setting behind", () => "compact" in L.toggle_compact(rule3, L.toggle_compact(rule3, L.normalize(null), key), key).shared, false],
  ["c with a shared compact already set always flips what is shown", () => { const loud = Object.assign({}, rule3, { compact: true }); const set = L.toggle_compact(loud, L.normalize({ shared: { compact: true } }), key); const set_false = L.normalize({ shared: { compact: false } }); return [L.effective(loud, set, key).compact, L.effective(rule3, L.toggle_compact(rule3, set_false, key), key).compact]; }, [false, true]],
  // A lualine bar draws center and right together, sorted by section, so a move steps through that shown order.
  ["a lualine move takes the side of the neighbor shown, when its id is on two sides", () => { const r = { left: [], center: ["tray", "volume"], right: ["tray"] }; const s = L.set_own(L.normalize(null), key, r, false); const moved = L.move_step(r, s, key, "volume", 1, true).monitors[key]; return [moved.center, moved.right]; }, [["tray"], ["tray", "volume"]]],
  ["a lualine move steps past a neighbor on the other side", () => { const r = { left: [], center: ["tray", "clock"], right: ["volume"] }; const s = L.set_own(L.normalize(null), key, r, false); const moved = L.move_step(r, s, key, "tray", 1, true); return [L.layout_of(L.effective(r, moved, key)), L.nav_order(L.layout_of(L.effective(r, moved, key)), true)]; }, [{ left: [], center: ["clock"], right: ["volume", "tray"] }, ["volume", "tray", "clock"]]],
  ["a lualine move back steps before a neighbor on the other side", () => { const r = { left: [], center: ["tray", "clock"], right: ["volume"] }; const s = L.set_own(L.normalize(null), key, r, false); const moved = L.move_step(r, s, key, "volume", -1, true); return L.nav_order(L.layout_of(L.effective(r, moved, key)), true); }, ["volume", "tray", "clock"]],
  ["a lualine move still refuses a neighbor in another section across sides", () => { const r = { left: [], center: ["tray", "clock"], right: ["volume"] }; const s = L.set_own(L.normalize(null), key, r, false); return L.move_step(r, s, key, "volume", 1, true).monitors[key].right; }, ["volume"]],
  ["a lualine move from the first shown module goes to the end of left", () => { const r = { left: ["start"], center: ["tray"], right: [] }; const s = L.set_own(L.normalize(null), key, r, false); return L.layout_of(L.effective(r, L.move_step(r, s, key, "tray", -1, true), key)).left; }, ["start", "tray"]],
  // c on a shared layout drops the setting only when every sharing monitor's rule already gives the flipped value.
  ["c twice leaves monitors with different rule compacts as they were shown at the start of the second press", () => { const a = Object.assign({}, rule3, { compact: false }); const b = Object.assign({}, rule3, { compact: true }); const once = L.toggle_compact(a, L.normalize(null), key, [a, b]); const twice = L.toggle_compact(a, once, key, [a, b]); return [once.shared.compact, twice.shared.compact, L.effective(a, twice, key).compact, L.effective(b, twice, "Other @ DP-2").compact]; }, [true, false, false, false]],
  ["c drops the setting when every sharing rule already gives the flipped value", () => { const a = Object.assign({}, rule3, { compact: false }); const b = Object.assign({}, rule3, { compact: false }); const once = L.toggle_compact(a, L.normalize(null), key, [a, b]); return ["compact" in L.toggle_compact(a, once, key, [a, b]).shared]; }, [false]],
  ["a lualine cross-side move works on a shared layout", () => { const r = { left: [], center: ["tray", "clock"], right: ["volume"] }; const moved = L.move_step(r, L.normalize(null), "", "tray", 1, true); const view = L.layout_of(L.effective(r, moved, "")); return [Object.keys(moved.monitors), view, L.nav_order(view, true)]; }, [[], { left: [], center: ["clock"], right: ["volume", "tray"] }, ["volume", "tray", "clock"]]],
  ["a lualine move with an empty center takes the first shown module on the right to the end of left", () => { const r = { left: ["start"], center: [], right: ["tray", "volume"] }; const s = L.set_own(L.normalize(null), key, r, false); return L.layout_of(L.effective(r, L.move_step(r, s, key, "tray", -1, true), key)); }, { left: ["start", "tray"], center: [], right: ["volume"] }],
  ["a lualine move with an empty center swaps inside right", () => { const r = { left: [], center: [], right: ["tray", "volume"] }; const s = L.set_own(L.normalize(null), key, r, false); return L.layout_of(L.effective(r, L.move_step(r, s, key, "tray", 1, true), key)).right; }, ["volume", "tray"]],
  ["a lualine move skips a module the bar draws itself", () => { const r = { left: [], center: [], right: ["tray", "directory", "volume"] }; const s = L.set_own(L.normalize(null), key, r, false); const view = L.layout_of(L.effective(r, L.move_step(r, s, key, "tray", 1, true), key)); return [L.nav_order(view, true), view.right.indexOf("directory") >= 0]; }, [["volume", "tray"], true]],
  ["compact flipped back follows each rule's own compact again", () => { const loud = Object.assign({}, rule3, { compact: true }); const s = L.toggle_compact(loud, L.toggle_compact(loud, L.normalize(null), key), key); return [L.effective(loud, s, key).compact, "compact" in s.shared]; }, [true, false]],
  ["compact on an own layout sets that layout only", () => { const s = L.toggle_compact(rule3, L.set_own(L.normalize(null), key, rule3, false), key); return [s.monitors[key].compact, "compact" in s.shared]; }, [true, false]],
  ["shared compact reaches sharing monitors but not own layouts", () => { const s = L.set_own(L.toggle_compact(rule3, L.normalize(null), key), "Own @ DP-3", rule3, false); return [L.effective(rule3, s, key).compact, L.effective(rule3, s, "Own @ DP-3").compact]; }, [true, false]],
  ["normalize keeps shared compact and drops a non-boolean one", () => [L.normalize({ shared: { compact: true } }).shared.compact, "compact" in L.normalize({ shared: { compact: "yes" } }).shared], [true, false]],
  // req: BAREDIT-09
  ["hide_entry takes the module off every side and lists it hidden", () => { const s = L.hide_entry(rule3, L.normalize(null), "", "tray"); return [edited_layout(s).right, L.hidden_entries([rule3], s, L.layout_of(L.effective(rule3, s, ""))).indexOf("tray") >= 0]; }, [["volume"], true]],
  ["hide_entry never purges the module from the state", () => { const s = L.hide_entry(rule3, L.normalize(null), "", "tray"); return [s.shared.place.tray, s.shared.last_side.tray]; }, ["hidden", { side: "right", index: 0 }]],
  ["hide_entry on an own layout never purges either", () => { const s = L.hide_entry(rule3, L.set_own(L.normalize(null), key, rule3, false), key, "system:cpu"); return [s.monitors[key].right, s.monitors[key].last_side["system:cpu"] === undefined]; }, [["tray", "volume"], true]],
  ["hide then restore puts the module back where it was", () => { const s = L.hide_entry(rule3, L.normalize(null), "", "tray"); return edited_layout(L.unhide_place([rule3], rule3, s, "", "tray")); }, { left: ["start", "workspaces"], center: ["clock"], right: ["tray", "volume"] }],
  ["unhide_place of a never-shown module goes to the right side's end", () => edited_layout(L.unhide_place([rule3], rule3, L.normalize(null), "", "battery")).right, ["tray", "volume", "battery"]],
  // req: BAREDIT-10
  ["valid_entry takes only a module with that argument", () => ["system:cpu", "system:gpu", "clock:x", "system", "nope:cpu"].map(L.valid_entry), [true, false, false, false, false]],
  ["add_entry puts the argument entry after the selected module", () => view_of(rule_sys, L.add_entry(rule_sys, L.normalize(null), "", "system:cpu", "system")).right, ["tray", "system", "system:cpu"]],
  ["add_entry refuses a duplicate or an invalid entry", () => [L.add_entry(rule_sys, L.normalize(null), "", "system:cpu", "system"), L.add_entry(rule_sys, L.normalize(null), "", "system:gpu", "system")].map((s, i) => i === 0 ? view_of(rule_sys, L.add_entry(rule_sys, s, "", "system:cpu", "system")).right : JSON.stringify(s) === JSON.stringify(L.normalize(null))), [["tray", "system", "system:cpu"], true]],
  ["suggest_entry is the next unused argument of the module", () => [L.suggest_entry(rule_sys, L.normalize(null), "", "system"), L.suggest_entry(rule_sys, L.add_entry(rule_sys, L.normalize(null), "", "system:cpu", "system"), "", "system"), L.suggest_entry(rule_sys, L.normalize(null), "", "clock")], ["system:cpu", "system:memory", ""]],
  // req: BAREDIT-14
  ["a sharing monitor's bar edge is the shared position", () => { const s = L.set_position_for_mode(L.normalize(null), key, "left"); return [s.shared.position, key in s.positions]; }, ["left", false]],
  ["a sharing monitor's own saved edge is cleared so the shared move shows", () => { const s = L.set_position_for_mode(L.set_position(L.normalize(null), key, "bottom"), key, "left"); return [s.shared.position, key in s.positions]; }, ["left", false]],
  ["a monitor with its own layout moves only its own edge", () => { const s = L.set_position_for_mode(L.set_own(L.normalize(null), key, rule3, false), key, "right"); return [s.positions[key], "position" in s.shared]; }, ["right", false]],
  ["is_sharing is true until the monitor has its own layout", () => [L.is_sharing(L.normalize(null), key), L.is_sharing(L.set_own(L.normalize(null), key, rule3, false), key)], [true, false]],
];

let failed = 0;
for (const [name, run, want] of cases) {
  let got;
  try {
    got = plain(run());
  } catch (e) {
    got = "threw " + e;
  }
  if (JSON.stringify(got) !== JSON.stringify(want)) {
    failed += 1;
    console.log("FAIL " + name + "\n  want: " + JSON.stringify(want) + "\n  got:  " + JSON.stringify(got));
  }
}
console.log(cases.length - failed + "/" + cases.length + " passed");
process.exit(failed ? 1 : 0);
