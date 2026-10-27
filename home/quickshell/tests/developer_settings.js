// Runs DeveloperSettings.js under node: the developer.json validation and the reviewer rows Settings > Developer shows.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/developer/DeveloperSettings.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { choices, valid, clean_saved, clean_layer, merged_entries, scope_of, rows, with_choice, step };", T);
const D = T.api;

const codex = { name: "codex", label: "Codex", local: { binary: "codex", default: "all" }, gate: "auto" };
const rabbit = { name: "coderabbit", label: "CodeRabbit", local: { binary: "coderabbit", default: "off" }, gate: "auto" };
const none = { reviewers: {} };

const cases = [
  ["local takes off, public, all", () => ["off", "public", "all", "on", "", null, 1].map(v => D.valid("local", v)), [true, true, true, false, false, false, false]],
  ["gate takes auto, always, never", () => ["auto", "always", "never", "yes", undefined].map(v => D.valid("gate", v)), [true, true, true, false, false]],
  ["an unknown key is never valid", () => D.valid("scope", "all"), false],
  ["a valid file is kept", () => D.clean_saved({ reviewers: { codex: { local: "public", gate: "never" } } }), { reviewers: { codex: { local: "public", gate: "never" } } }],
  ["an invalid field is dropped, the valid one kept", () => D.clean_saved({ reviewers: { codex: { local: "bogus", gate: "always" } } }), { reviewers: { codex: { gate: "always" } } }],
  ["a reviewer left with no valid field is dropped", () => D.clean_saved({ reviewers: { codex: { local: "bogus" } } }), none],
  ["fields other than local and gate are dropped", () => D.clean_saved({ reviewers: { codex: { gate: "auto", command: "x" } } }), { reviewers: { codex: { gate: "auto" } } }],
  ["a non-object reviewer entry is dropped", () => D.clean_saved({ reviewers: { codex: "all", rabbit: null, a: [1] } }), none],
  ["wrong shapes give the empty default", () => [null, [], "x", { reviewers: [] }, { reviewers: "x" }].map(D.clean_saved), [none, none, none, none, none]],
  ["a layer keeps named object entries only", () => D.clean_layer({ reviewers: [codex, 3, { label: "x" }, null, { name: "" }] }), { reviewers: [codex] }],
  ["a layer of the wrong shape is empty", () => [null, { reviewers: {} }, []].map(D.clean_layer), [{ reviewers: [] }, { reviewers: [] }, { reviewers: [] }]],
  ["user entries merge over built-in by name, objects field by field", () => D.merged_entries([codex], [{ name: "codex", local: { default: "off" } }]), [{ name: "codex", label: "Codex", local: { binary: "codex", default: "off" }, gate: "auto" }]],
  ["a user entry with a new name is added after the built-ins", () => D.merged_entries([codex], [rabbit]).map(e => e.name), ["codex", "coderabbit"]],
  ["enabled false removes an entry", () => D.merged_entries([codex, rabbit], [{ name: "codex", enabled: false }]).map(e => e.name), ["coderabbit"]],
  ["scope: local.scope, else default, else off", () => [{ scope: "public", default: "all" }, { default: "all" }, {}, "public", "bogus", null, { scope: "bogus" }].map(D.scope_of), ["public", "all", "off", "public", "off", "off", "off"]],
  ["a row takes the entry's defaults", () => D.rows([codex, rabbit], none, ["codex", "coderabbit"]).map(r => [r.local, r.gate]), [["all", "auto"], ["off", "auto"]]],
  ["a saved choice beats the file's value", () => D.rows([codex], { reviewers: { codex: { local: "public", gate: "never" } } }, ["codex"])[0], { name: "codex", label: "Codex", binary: "codex", installed: true, local: "public", gate: "never" }],
  ["a missing binary shows installed no and local off, gate stays", () => D.rows([codex], { reviewers: { codex: { local: "all", gate: "always" } } }, [])[0], { name: "codex", label: "Codex", binary: "codex", installed: false, local: "off", gate: "always" }],
  ["a reviewer without a binary counts as installed", () => D.rows([{ name: "mine", local: { command: "mine.sh", default: "public" } }], none, [])[0], { name: "mine", label: "mine", binary: "", installed: true, local: "public", gate: "auto" }],
  ["an invalid gate in the file shows auto", () => D.rows([{ name: "x", gate: "sometimes" }], none, [])[0].gate, "auto"],
  ["with_choice changes one field and keeps the other", () => D.with_choice({ reviewers: { codex: { gate: "never" } } }, "codex", "local", "all"), { reviewers: { codex: { gate: "never", local: "all" } } }],
  ["with_choice leaves a field the user never set absent", () => D.with_choice(none, "codex", "gate", "always"), { reviewers: { codex: { gate: "always" } } }],
  ["with_choice ignores an invalid value", () => D.with_choice(none, "codex", "gate", "bogus"), none],
  ["step wraps both ways", () => [D.step("local", "all", 1), D.step("local", "off", -1), D.step("gate", "auto", 1), D.step("gate", "bogus", 1)], ["off", "all", "always", "always"]],
];

let failed = 0;
for (const [name, run, want] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(run())), want);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}
if (failed) process.exit(1);
console.log("developer settings: " + cases.length + " checks passed");
