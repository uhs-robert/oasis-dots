// Runs core/WindowEntries.js under node: the window entries the overview's search and the windows picker rank, the
// Alt+Tab start row and the picker's monitor and workspace filter.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const file = path.join(__dirname, "../.config/quickshell/core/WindowEntries.js");
const ctx = vm.createContext({});
const names = ["clean_title", "entry_of", "previous_index", "cycled_filter", "kept_by_filter", "filter_label"];
vm.runInContext(fs.readFileSync(file, "utf8").replace(/^\.pragma.*$/m, "") + "\nthis.api = { " + names.join(", ") + " };", ctx);
const W = ctx.api;

const win = (address, extra) => Object.assign({ address: address, title: "notes", cls: "org.app." + address, initial_class: "app-" + address, short_class: address, ws_name: "1", ws_id: 1, monitor: "DP-1" }, extra || {});
const here = { monitor: "DP-1", ws_id: 1 };
const entries = [win("a"), win("b", { ws_name: "2", ws_id: 2 }), win("c", { ws_name: "special:scratch", ws_id: -98, monitor: "HDMI-A-1" })].map((w, i) => W.entry_of(w, i));

const cases = [
  ["a trailing app name goes", () => W.clean_title("notes - Mozilla Firefox", "firefox"), "notes"],
  ["Firefox's private prefix goes", () => W.clean_title("XXX secret — Mozilla Firefox", "firefox"), "secret"],
  ["a dash that is not the app name stays", () => W.clean_title("a - b", "kitty"), "a - b"],
  ["no title is empty", () => W.clean_title(undefined, "kitty"), ""],
  ["the short class is the label, the address the id", () => [entries[0].label, entries[0].id, entries[0].address], ["a", "a", "a"]],
  ["no class is labelled window", () => W.entry_of(win("d", { short_class: "" }), 0).label, "window"],
  ["class, initial class, workspace and raw title are keywords", () => entries[0].keywords, ["org.app.a", "app-a", "1", "notes"]],
  ["a special workspace reads as special", () => entries[2].place, "special scratch"],
  ["the description is workspace and title", () => entries[1].description, "2 · notes"],
  ["recency is kept", () => entries.map(e => e.recency), [0, 1, 2]],
  ["starts on the window before the focused one", () => W.previous_index(entries, "a"), 1],
  ["starts on the first when the focused one is not first", () => W.previous_index(entries, "b"), 0],
  ["starts on the only window", () => W.previous_index(entries.slice(0, 1), "a"), 0],
  ["f cycles all, monitor, workspace, then all", () => [W.cycled_filter("all"), W.cycled_filter("monitor"), W.cycled_filter("workspace")], ["monitor", "workspace", "all"]],
  ["all keeps every window", () => entries.filter(e => W.kept_by_filter(e, "all", here)).map(e => e.id), ["a", "b", "c"]],
  ["monitor keeps the focused monitor's", () => entries.filter(e => W.kept_by_filter(e, "monitor", here)).map(e => e.id), ["a", "b"]],
  ["workspace keeps the focused workspace's", () => entries.filter(e => W.kept_by_filter(e, "workspace", here)).map(e => e.id), ["a"]],
  ["labels", () => ["all", "monitor", "workspace"].map(W.filter_label), ["ALL", "MONITOR", "WORKSPACE"]],
];

let failed = 0;
for (const [name, run, want] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(run())), want);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + ": " + e.message.split("\n").slice(0, 6).join(" "));
  }
}
console.log((cases.length - failed) + "/" + cases.length + " window entries cases pass");
process.exit(failed > 0 ? 1 : 0);
