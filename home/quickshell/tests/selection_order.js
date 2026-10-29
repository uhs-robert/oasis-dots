// Runs features/submap_hints/SelectionOrder.js under node: the bar keeps the newest window selection by (generation,
// serial), so a send the previous config load made that lands after a reload's clear cannot stick, and the new load's
// sends, whose serial restarts at 1, are not refused.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const script = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/submap_hints/SelectionOrder.js"), "utf8").replace(/^\.pragma.*$/gm, "");
const O = vm.createContext({});
vm.runInContext(script, O);

// Feeds events in arrival order to a fresh receiver, as WindowTargetState applies them; returns its final selection.
function receive(events) {
  let state = { generation: 0, serial: 0, selected: [] };
  for (const event of events) {
    const next = event.clear !== undefined ? O.after_clear(state, event.clear) : O.after_selection(state, event);
    if (next) state = next;
  }
  return state.selected.join(",");
}
const sel = (generation, serial, ...windows) => ({ generation, serial, windows });

const cases = [
  ["sends in order apply", [sel(100, 1, "0xa"), sel(100, 2, "0xa", "0xb")], "a,b"],
  ["an older serial landing last is dropped", [sel(100, 2, "0xa", "0xb"), sel(100, 1, "0xa")], "a,b"],
  ["the address prefix goes", [sel(100, 1, "0xa1")], "a1"],
  ["a reload's clear empties the selection", [sel(100, 3, "0xa"), { clear: 200 }], ""],
  ["the old load's send landing after the clear is dropped", [sel(100, 2, "0xa"), { clear: 200 }, sel(100, 3, "0xa", "0xb")], ""],
  ["after it, the new load's first sends still apply", [sel(100, 5, "0xa"), { clear: 200 }, sel(100, 6, "0xz"), sel(200, 1, "0xc")], "c"],
  ["a new load's send beats a higher old serial without a clear", [sel(100, 9, "0xa"), sel(200, 1, "0xc")], "c"],
  ["a clear that loses the race to its load's first send changes nothing", [sel(200, 1, "0xc"), { clear: 200 }], "c"],
  ["an older load's clear changes nothing", [sel(200, 1, "0xc"), { clear: 100 }], "c"],
  ["the same serial twice applies once", [sel(100, 1, "0xa"), sel(100, 1, "0xb")], "a"],
];

let failures = 0;
for (const [name, events, want] of cases) {
  const got = receive(events);
  if (got !== want) {
    failures += 1;
    console.log("FAIL " + name + ": got '" + got + "', want '" + want + "'");
  }
}
if (failures > 0) process.exit(1);
console.log("selection_order: all passed (" + cases.length + ")");
