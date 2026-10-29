// Runs core/WindowVisibility.js under node: which clients a monitor shows (its workspace, its open special workspace,
// pinned clients, each on its own monitor) and which tiled clients a fullscreen or maximized one covers. The objects
// are shaped as Hyprland 0.57's `hyprctl -j` sends them: a special workspace has no id, a closed one an empty name.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const script = fs.readFileSync(path.join(__dirname, "../.config/quickshell/core/WindowVisibility.js"), "utf8").replace(/^\.pragma.*$/gm, "");
const V = vm.createContext({});
vm.runInContext(script, V);

const ws = (id) => ({ address: String(id), id: id, type: "normal", name: String(id) });
const special = (name) => ({ address: "special:" + name, type: "special", name: "special:" + name });
const closed = { address: "", type: "", name: "" };

const monitors = [
  { id: 0, name: "DP-1", activeWorkspace: ws(1), specialWorkspace: special("scratchpad") },
  { id: 1, name: "HDMI-A-1", activeWorkspace: ws(2), specialWorkspace: closed },
];
const shown = V.shown_by_monitor(monitors);
const client = (fields) => Object.assign({ mapped: true, hidden: false, monitor: 0, workspace: ws(1), fullscreen: 0, floating: false, pinned: false }, fields);

const regular = client({});
const scratch = client({ workspace: special("scratchpad"), floating: true });
const other_special = client({ workspace: special("music") });
const pinned = client({ workspace: ws(5), floating: true, pinned: true });
const elsewhere = client({ workspace: ws(3) });
const other_monitor = client({ monitor: 1, workspace: ws(2) });
const wrong_monitor = client({ monitor: 1, workspace: ws(1) });
const hidden_scratch = client({ monitor: 1, workspace: special("scratchpad") });
const grouped_tab = client({ hidden: true });
const unmapped = client({ mapped: false });
const fullscreen = client({ fullscreen: 1 });
const floating = client({ floating: true });

const cases = [
  ["the active workspace's window is shown, with the scratchpad open over it", () => V.is_shown(regular, shown), true],
  ["the open special workspace's window is shown", () => V.is_shown(scratch, shown), true],
  ["another special workspace's window is not", () => V.is_shown(other_special, shown), false],
  ["a pinned window is shown whatever workspace it records", () => V.is_shown(pinned, shown), true],
  ["another workspace's window is not", () => V.is_shown(elsewhere, shown), false],
  ["a window on the other monitor's workspace is shown there", () => V.is_shown(other_monitor, shown), true],
  ["a workspace is matched on the client's own monitor", () => V.is_shown(wrong_monitor, shown), false],
  ["a closed special workspace shows none of its windows", () => V.is_shown(hidden_scratch, shown), false],
  ["a hidden grouped tab is not shown", () => V.is_shown(grouped_tab, shown), false],
  ["an unmapped window is not shown", () => V.is_shown(unmapped, shown), false],
  ["no monitors, nothing shown", () => V.is_shown(regular, V.shown_by_monitor([])), false],
  ["an id-only workspace still matches", () => V.is_shown(client({ workspace: { id: 1 } }), V.shown_by_monitor([{ id: 0, activeWorkspace: { id: 1 } }])), true],
  ["a tiled window under a fullscreen one is covered", () => V.is_covered(regular, [regular, fullscreen, floating]), true],
  ["the fullscreen window itself is not covered", () => V.is_covered(fullscreen, [regular, fullscreen]), false],
  ["a floating window stays above it", () => V.is_covered(floating, [floating, fullscreen]), false],
  ["a pinned window stays above it", () => V.is_covered(pinned, [pinned, fullscreen]), false],
  ["fullscreen on another workspace covers nothing here", () => V.is_covered(other_monitor, [other_monitor, fullscreen]), false],
  ["the scratchpad's fullscreen window does not cover the regular workspace", () => V.is_covered(regular, [regular, client({ workspace: special("scratchpad"), fullscreen: 1 })]), false],
];

let failures = 0;
for (const [name, run, want] of cases) {
  const got = run();
  if (got !== want) {
    failures += 1;
    console.log("FAIL " + name + ": got " + JSON.stringify(got) + ", want " + JSON.stringify(want));
  }
}
if (failures > 0) process.exit(1);
console.log("window_visibility: all passed (" + cases.length + ")");
