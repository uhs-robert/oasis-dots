// Runs WallpaperStrip.js under node: filmstrip cursor moves, gg/G, monitor switching and the centring offset.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/settings/WallpaperStrip.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { move, step_monitor, centre_x, index_of, pinned_on };", T);
const S = T.api;

const mons = [{ key: "A" }, { key: "B" }];
const cases = [
  ["next moves one right", () => S.move(2, "next", 10), 3],
  ["prev moves one left", () => S.move(2, "prev", 10), 1],
  ["prev clamps at the first image", () => S.move(0, "prev", 10), 0],
  ["next clamps at the last image", () => S.move(9, "next", 10), 9],
  ["gg goes to the first", () => S.move(6, "first", 10), 0],
  ["G goes to the last", () => S.move(2, "last", 10), 9],
  ["an empty strip stays at 0", () => ["prev", "next", "first", "last"].map(a => S.move(5, a, 0)), [0, 0, 0, 0]],
  ["a cursor past the end is pulled in", () => S.move(40, "prev", 10), 8],
  ["an unknown action keeps the cursor", () => S.move(4, "bogus", 10), 4],
  ["a one-image strip never moves", () => ["prev", "next", "first", "last"].map(a => S.move(0, a, 1)), [0, 0, 0, 0]],
  ["monitor step wraps forward", () => S.step_monitor(1, 1, 2), 0],
  ["monitor step wraps back", () => S.step_monitor(0, -1, 3), 2],
  ["monitor step with no monitors is 0", () => S.step_monitor(0, 1, 0), 0],
  ["centre_x puts the cell in the middle", () => S.centre_x(5, 100, 400), 350],
  ["centre_x of the first cell is negative", () => S.centre_x(0, 100, 400), -150],
  ["the cell centre is the view centre at every index", () => { for (let i = 0; i < 30; i++) { const x = S.centre_x(i, 96, 700); if (i * 96 + 48 - x !== 350) return i; } return "ok"; }, "ok"],
  ["index_of finds a listed path", () => S.index_of(["a", "b", "c"], "b", -1), 1],
  ["index_of falls back for a missing or empty path", () => [S.index_of(["a"], "z", 3), S.index_of(["a"], "", 3), S.index_of(["a"], undefined, 3)], [3, 3, 3]],
  ["pinned_on lists 1-based monitor numbers", () => S.pinned_on(mons, { A: "x", B: "x" }, "x"), [1, 2]],
  ["pinned_on skips other pins", () => S.pinned_on(mons, { A: "x", B: "y" }, "y"), [2]],
];

let failed = 0;
for (const [name, run, want] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(run())), want);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}
if (failed) process.exit(1);
console.log("wallpaper_strip: " + cases.length + " cases ok");
