// Runs ToastExtent.js under node: the toast drawer's window depth, stack height and hover settling.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/notifications/ToastExtent.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { window_depth, stack_height, opening, duration, hover_action };", T);
const X = T.api;

const cases = [
  ["window_depth: five tall cards on a tall screen", () => X.window_depth(5000), 5 * 200 + 4 * 8 + 16],
  ["window_depth: a short screen caps it", () => X.window_depth(500), 500],
  ["window_depth: never negative", () => X.window_depth(-4), 0],
  ["stack_height: follows the content", () => X.stack_height(300, 2, 10, 900), 300],
  ["stack_height: capped, the last card clips", () => X.stack_height(1200, 7, 10, 900), 900],
  ["stack_height: an empty stack holds the last height", () => X.stack_height(0, 0, 240, 900), 240],
  ["stack_height: a removed card shrinks it below the last height", () => X.stack_height(100, 1, 220, 900), 100],
  ["stack_height: just under, at and over the cap", () => [X.stack_height(899, 5, 0, 900), X.stack_height(900, 5, 0, 900), X.stack_height(901, 5, 0, 900)], [899, 900, 900]],
  ["window_depth: just under, at and over five tall cards", () => [X.window_depth(1047), X.window_depth(1048), X.window_depth(1049)], [1047, 1048, 1048]],
  ["duration: opening takes longer than folding or holding", () => [X.duration(100, 0), X.duration(0, 100), X.duration(50, 50)], [190, 120, 120]],
  ["hover_action: ignored while moving", () => [X.hover_action(true, true, false), X.hover_action(true, false, true)], ["none", "none"]],
  ["hover_action: settles after the move", () => [X.hover_action(false, true, false), X.hover_action(false, false, true)], ["pause", "resume"]],
  ["hover_action: nothing to do when already in step", () => [X.hover_action(false, true, true), X.hover_action(false, false, false)], ["none", "none"]],
];

let failed = 0;
for (const [name, fn, expected] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(fn())), expected);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + "\n  " + e.message.split("\n")[0]);
  }
}
if (failed) process.exit(1);
console.log("toast extent: " + cases.length + " checks passed");
