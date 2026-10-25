// Runs CavaViewers.js under node: the viewer registry that decides when cava runs.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/media/CavaViewers.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { register, unregister, any };", T);
const V = T.api;

const a = { name: "a" };
const b = { name: "b" };
const names = list => list.map(v => v.name);

const cases = [
  ["empty registry: cava stays off", () => V.any([]), false],
  ["one viewer turns cava on", () => V.any(V.register([], a)), true],
  ["double register is one viewer", () => names(V.register(V.register([], a), a)), ["a"]],
  ["double register then one unregister stops cava", () => V.any(V.unregister(V.register(V.register([], a), a), a)), false],
  ["zero viewers after the last one leaves", () => V.any(V.unregister(V.register([], a), a)), false],
  ["a second viewer keeps cava on when the first leaves", () => [V.any(V.unregister(V.register(V.register([], a), b), a)), names(V.unregister(V.register(V.register([], a), b), a))], [true, ["b"]]],
  ["destroy while shown: unregister without a prior hide", () => names(V.unregister(V.register(V.register([], a), b), b)), ["a"]],
  ["unregistering a stranger leaves the others", () => names(V.unregister(V.register([], a), b)), ["a"]],
  ["unregister twice is harmless", () => V.any(V.unregister(V.unregister(V.register([], a), a), a)), false],
  ["viewers are matched by identity, not by content", () => names(V.register(V.register([], a), { name: "a" })), ["a", "a"]],
  ["register does not mutate its input", () => { const l = [a]; V.register(l, b); V.unregister(l, a); return names(l); }, ["a"]],
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
console.log("cava viewers: " + cases.length + " checks passed");
