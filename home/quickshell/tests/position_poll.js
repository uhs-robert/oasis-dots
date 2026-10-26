// Runs PositionPoll.js under node: how often the track position is re-read.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/media/PositionPoll.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { interval };", T);
const P = T.api;

const cases = [
  ["nothing viewing: no polling, playing or not", () => [P.interval(false, true), P.interval(false, false)], [0, 0]],
  ["viewed and playing: every second", () => P.interval(true, true), 1000],
  ["viewed and paused: slow poll for outside seeks", () => P.interval(true, false), 2000],
];

let failed = 0;
for (const [name, fn, want] of cases) {
  try { assert.deepStrictEqual(fn(), want); console.log("ok   " + name); } catch (e) { failed++; console.log("FAIL " + name + "\n  " + e.message); }
}
process.exit(failed ? 1 : 0);
