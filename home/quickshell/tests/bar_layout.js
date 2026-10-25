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
  ["step_position toggles top and bottom either way", () => [L.step_position("top", 1), L.step_position("bottom", 1), L.step_position("top", -1), L.step_position("bottom", -1)], ["bottom", "top", "bottom", "top"]],
  ["step_position from a saved side position still lands on top or bottom", () => [L.step_position("left", 1), L.step_position("right", -1)], ["bottom", "bottom"]],
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
  ["migrate adds cava after workspaces", () => L.migrate_cava({ monitors: { [key]: { left: ["start", "workspaces", "cmdstatus"], center: ["clock"], right: [] } } }).monitors[key].left, ["start", "workspaces", "cava", "cmdstatus"]],
  ["migrate appends to left without workspaces", () => L.migrate_cava({ monitors: { [key]: { left: ["start"], center: [], right: [] } } }).monitors[key].left, ["start", "cava"]],
  ["migrate keeps a cava already listed, in any side", () => L.migrate_cava({ monitors: { [key]: { left: ["workspaces"], center: [], right: ["cava"] } } }).monitors[key], { left: ["workspaces"], center: [], right: ["cava"], last_side: {} }],
  ["migrate sets the flag, and normalize keeps it", () => L.normalize(plain(L.migrate_cava(L.normalize(null)))).cava_migrated, true],
  ["migrate runs once: a removed cava stays removed", () => L.migrate_cava({ cava_migrated: true, monitors: { [key]: { left: ["workspaces"], center: [], right: [] } } }).monitors[key].left, ["workspaces"]],
  ["normalize without the flag adds none", () => "cava_migrated" in L.normalize(null), false],
  ["shared layouts are untouched by migrate", () => L.migrate_cava({ shared: { place: { clock: "left" } } }).shared.place, { clock: "left" }],
  ["migrate keeps the directory switches", () => L.directory_switches(L.migrate_cava(L.normalize({ directory: { path: false }, monitors: { [key]: { left: ["workspaces"], center: [], right: [] } } }))), { app_name: true, path: false, file_name: true }],
  ["migrate covers every monitor with its own layout", () => Object.values(L.migrate_cava({ monitors: { a: { left: ["workspaces"], center: [], right: [] }, b: { left: ["start"], center: [], right: ["cava"] }, c: { left: [], center: [], right: [] } } }).monitors).map(m => m.left.concat(m.right)), [["workspaces", "cava"], ["start", "cava"], ["cava"]]],
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
