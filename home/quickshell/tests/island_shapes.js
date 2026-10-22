// Runs IslandOutlines.js's fill-less helpers under node, and checks every Style.island_shapes entry has a kit and a label.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const root = path.join(__dirname, "../.config/quickshell");
const read = rel => fs.readFileSync(path.join(root, rel), "utf8");
const O = vm.createContext({});
vm.runInContext(read("features/bar/IslandOutlines.js").replace(/^\.pragma.*$/gm, ""), O);
const run = code => vm.runInContext(code, O);
const plain = v => JSON.parse(JSON.stringify(v));

const cases = [
  ["stroke_only none", () => O.stroke_only("none"), true],
  ["stroke_only underline", () => O.stroke_only("underline"), true],
  ["stroke_only brackets", () => O.stroke_only("brackets"), true],
  ["stroke_only slant", () => O.stroke_only("slant"), false],
  ["stroke_only hex", () => O.stroke_only("hex"), false],
  ["has stays filled-only", () => ["none", "underline", "brackets"].some(s => O.has(s)), false],
  ["none pad", () => O.cap_width("none", 30), 9],
  ["underline pad", () => O.cap_width("underline", 30), 9],
  ["brackets pad is arm plus gap", () => O.cap_width("brackets", 30), 12],
  ["brackets arm floor", () => O.bracket_arm(10), 4],
  ["underline path", () => plain(O.underline_path(100, 30, 2)), [[0, 29], [100, 29]]],
  ["bracket count", () => O.bracket_paths(100, 30, 9, 2).length, 4],
  ["bracket corners", () => plain(O.bracket_paths(100, 30, 9, 2).map(p => p[1])), [[1, 1], [99, 1], [99, 29], [1, 29]]],
  ["bracket arms stay inside", () => O.bracket_paths(100, 30, 9, 2).every(p => p.every(q => q[0] >= 0 && q[0] <= 100 && q[1] >= 0 && q[1] <= 30)), true],
];

let failed = 0;
for (const [name, fn, want] of cases) {
  try {
    assert.deepStrictEqual(fn(), want);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}

// Style.qml is QML, so read its lists as text.
const style = read("theme/Style.qml");
const shapes = JSON.parse(style.match(/island_shapes: (\[[^\]]*\])/)[1]);
const kits = style.slice(style.indexOf("island_shape_kits: ({"), style.indexOf("renamed_island_shapes"));
const labels = style.match(/bar_island_shape: \{([^}]*)\}/)[1];
for (const s of shapes) {
  if (!new RegExp("\\b" + s + ": \\{").test(kits)) { failed++; console.log("FAIL no kit for " + s); }
  if (!new RegExp("\\b" + s + ": \"").test(labels)) { failed++; console.log("FAIL no label for " + s); }
}
for (const s of ["none", "underline", "brackets"]) {
  if (!shapes.includes(s) || !new RegExp(s + ": \\{ filled: false").test(kits)) { failed++; console.log("FAIL " + s + " not a fill-less shape in Style.qml"); }
}

if (failed) process.exit(1);
console.log("island shapes: " + (cases.length + shapes.length * 2 + 3) + " checks passed");
