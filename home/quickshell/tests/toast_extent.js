// Runs ToastExtent.js under node: the toast drawer's window depth, stack height and hover settling.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/notifications/ToastExtent.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { window_depth, stack_height, opening, hover_action };", T);
const X = T.api;

const cases = [
  ["window_depth: five tall cards on a tall screen", () => X.window_depth(5000), 5 * 200 + 4 * 8 + 16],
  ["window_depth: a short screen caps it", () => X.window_depth(500), 500],
  ["window_depth: never negative", () => X.window_depth(-4), 0],
  ["stack_height: follows the content", () => X.stack_height(300, 2, 10, 900), 300],
  ["stack_height: capped, the last card clips", () => X.stack_height(1200, 7, 10, 900), 900],
  ["stack_height: an empty stack holds the last height", () => X.stack_height(0, 0, 240, 900), 240],
  ["stack_height: growth re-targets", () => [X.stack_height(100, 1, 0, 900), X.stack_height(220, 2, 100, 900)], [100, 220]],
  ["opening: grows toward a larger target", () => [X.opening(100, 0), X.opening(0, 100), X.opening(50, 50)], [true, false, false]],
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
