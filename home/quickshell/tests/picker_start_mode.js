// Runs StartMode.js under node: the mode a bottom-docked picker opens in, and how typing.json keys load.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const qs = path.join(__dirname, "../.config/quickshell");
function load(file, names) {
  const ctx = vm.createContext({});
  const source = fs.readFileSync(path.join(qs, file), "utf8").replace(/^\.pragma.*$/m, "");
  vm.runInContext(source + "\nthis.api = { " + names.join(", ") + " };", ctx);
  return ctx.api;
}
const S = load("features/launcher/StartMode.js", ["choices", "defaults", "group_mode", "docked_mode", "bottom_pickers"]);
const V = load("core/Validated.js", ["validated", "in_choices"]);

const choices = S.choices();
const defaults = S.defaults();
const loaded = raw => V.validated(defaults, raw, (key, value) => V.in_choices(choices, key, value));
const mode = (raw, name, group) => S.docked_mode(loaded(raw), name, group);

const cases = [
  ["defaults: browse opens NORMAL, search INSERT", () => [mode({}, "clipboard", "browse"), mode({}, "apps", "search")], ["normal", "insert"]],
  ["defaults: every bottom picker follows its group", () => S.bottom_pickers.map(n => defaults[n + "_start_mode"]), Array(7).fill("group")],
  ["a file from before the groups loads with their defaults", () => loaded({ start_mode: "normal", remember_query: true }).browse_start_mode, "normal"],
  ["a group setting moves its members", () => [mode({ browse_start_mode: "insert" }, "agents", "browse"), mode({ search_start_mode: "normal" }, "emoji", "search")], ["insert", "normal"]],
  ["a group setting leaves the other group alone", () => mode({ browse_start_mode: "insert" }, "apps", "search"), "insert"],
  ["an override beats its group", () => [mode({ clipboard_start_mode: "insert" }, "clipboard", "browse"), mode({ search_start_mode: "normal", dirs_start_mode: "insert" }, "dirs", "search")], ["insert", "insert"]],
  ["group defers to the group setting", () => mode({ search_start_mode: "normal", keybinds_start_mode: "group" }, "keybinds", "search"), "normal"],
  ["an override reaches only its picker", () => mode({ clipboard_start_mode: "insert" }, "agents", "browse"), "normal"],
  ["an invalid value falls back to the default", () => [mode({ clipboard_start_mode: "maybe" }, "clipboard", "browse"), mode({ search_start_mode: 1 }, "apps", "search")], ["normal", "insert"]],
  ["a provider with no or an unknown group is a search picker", () => [mode({ search_start_mode: "normal" }, "other", ""), mode({ search_start_mode: "normal" }, "other", "bogus")], ["normal", "normal"]],
  ["group_mode reads the group's value", () => [S.group_mode(loaded({ browse_start_mode: "insert" }), "browse"), S.group_mode({}, "search")], ["insert", "insert"]],
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
console.log("picker start mode: " + cases.length + " checks passed");
