// Runs BarLayout.js under node: the bar position a rule or a monitor's own layout picks, and how the state file keeps it.
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
  ["normalize keeps a monitor's position", () => L.normalize({ monitors: { [key]: { left: [], position: "bottom" } } }).monitors[key].position, "bottom"],
  ["normalize drops a bad position", () => "position" in L.normalize({ monitors: { [key]: { left: [], position: "left" } } }).monitors[key], false],
  ["effective takes the rule's position", () => L.effective(Object.assign({ position: "bottom" }, rule), L.normalize(null), key).position, "bottom"],
  ["own position wins", () => L.effective(Object.assign({ position: "bottom" }, rule), L.normalize({ monitors: { [key]: { position: "top" } } }), key).position, "top"],
  ["own layout without a position keeps the rule's", () => L.effective(Object.assign({ position: "bottom" }, rule), L.normalize({ monitors: { [key]: {} } }), key).position, "bottom"],
  ["set_own copies the position", () => L.set_own(L.normalize(null), key, rule, false, "bottom").monitors[key].position, "bottom"],
  ["set_own turns left into top", () => L.set_own(L.normalize(null), key, rule, false, "left").monitors[key].position, "top"],
  ["set_position on an own layout", () => L.set_position(L.set_own(L.normalize(null), key, rule, false, "top"), key, "bottom").monitors[key].position, "bottom"],
  ["set_position needs an own layout", () => plain(L.set_position(L.normalize(null), key, "bottom")).monitors, {}],
  ["set_position refuses left", () => L.set_position(L.set_own(L.normalize(null), key, rule, false, "bottom"), key, "left").monitors[key].position, "bottom"],
  ["position survives a round trip", () => L.normalize(plain(L.set_own(L.normalize(null), key, rule, true, "bottom"))).monitors[key], { left: ["start"], center: ["clock"], right: ["tray"], last_side: {}, compact: true, position: "bottom" }],
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
