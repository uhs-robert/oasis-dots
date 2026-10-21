// Runs BarLayout.js under node: the bar position a rule or a monitor's saved position picks, and how the state file keeps it.
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

const rule = { match: "*", left: ["start"], center: ["clock"], right: ["tray"] };
const key = "Dell @ DP-1";
const plain = obj => JSON.parse(JSON.stringify(obj));

const cases = [
  ["no position is top", () => L.position_of(rule), "top"],
  ["null rule is top", () => L.position_of(null), "top"],
  ["bottom kept", () => L.position_of({ position: "bottom" }), "bottom"],
  ["left falls back", () => L.position_of({ position: "left" }), "top"],
  ["typo falls back", () => L.position_of({ position: "botom" }), "top"],
  ["no problem without a position", () => L.position_problem(rule), ""],
  ["no problem for bottom", () => L.position_problem({ position: "bottom" }), ""],
  ["right is planned", () => L.position_problem({ position: "right" }), "bar position \"right\" is not supported yet; using top"],
  ["unknown named", () => L.position_problem({ position: 3 }), "unknown bar position 3 in bars.json; using top"],
  ["normalize keeps a saved position", () => L.normalize({ positions: { [key]: "bottom" } }).positions, { [key]: "bottom" }],
  ["normalize drops a bad position", () => L.normalize({ positions: { [key]: "left", other: 3 } }).positions, {}],
  ["normalize moves an own layout's position out", () => L.normalize({ monitors: { [key]: { left: [], position: "bottom" } } }), { shared: { place: {}, order: [], last_side: {} }, monitors: { [key]: { left: [], center: [], right: [], last_side: {} } }, positions: { [key]: "bottom" } }],
  ["effective takes the rule's position", () => L.effective(Object.assign({ position: "bottom" }, rule), L.normalize(null), key).position, "bottom"],
  ["saved position wins over the rule", () => L.effective(Object.assign({ position: "bottom" }, rule), L.normalize({ positions: { [key]: "top" } }), key).position, "top"],
  ["saved position applies with an own layout", () => L.effective(rule, L.normalize({ monitors: { [key]: {} }, positions: { [key]: "bottom" } }), key).position, "bottom"],
  ["another monitor's position is ignored", () => L.effective(rule, L.normalize({ positions: { other: "bottom" } }), key).position === undefined, true],
  ["set_position without an own layout", () => plain(L.set_position(L.normalize(null), key, "bottom")), { shared: { place: {}, order: [], last_side: {} }, monitors: {}, positions: { [key]: "bottom" } }],
  ["set_position refuses left", () => L.set_position(L.normalize({ positions: { [key]: "bottom" } }), key, "left").positions[key], "bottom"],
  ["own layout on keeps the position", () => L.set_own(L.set_position(L.normalize(null), key, "bottom"), key, rule, false).positions[key], "bottom"],
  ["own layout off keeps the position", () => L.drop_own(L.set_own(L.set_position(L.normalize(null), key, "bottom"), key, rule, false), key).positions[key], "bottom"],
  ["set_own writes no position", () => "position" in L.set_own(L.normalize(null), key, rule, false).monitors[key], false],
  ["a position key is reused after a connector change", () => L.resolve_key(L.normalize({ positions: { "Dell @ DP-1": "bottom" } }), "Dell", "DP-2", [{ name: "DP-2", description: "Dell" }]), "Dell @ DP-1"],
  ["position survives a round trip", () => L.normalize(plain(L.set_position(L.normalize(null), key, "bottom"))).positions, { [key]: "bottom" }],
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
