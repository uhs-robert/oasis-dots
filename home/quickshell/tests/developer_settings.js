// Runs DeveloperSettings.js under node: the developer.json validation and the reviewer rows Settings > Developer shows.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/developer/DeveloperSettings.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { choices, valid, clean_saved, clean_layer, merged_entries, scope_of, rows, with_choice, step, cell_click };", T);
const D = T.api;

const codex = { name: "codex", label: "Codex", local: { binary: "codex", default: "all" }, gate: "auto" };
const rabbit = { name: "coderabbit", label: "CodeRabbit", local: { binary: "coderabbit", default: "off" }, gate: "auto" };
const none = { reviewers: {} };

const cases = [
  ["a string local in a later layer keeps the built-in binary", () => D.rows(D.merged_entries(D.clean_layer({ reviewers: [codex] }).reviewers, D.clean_layer({ reviewers: [{ name: "codex", local: "public" }] }).reviewers), none, [])[0], { name: "codex", label: "Codex", binary: "codex", installed: false, probing: false, local: "off", gate: "auto" }],
  ["a null local in a later layer is ignored", () => D.merged_entries(D.clean_layer({ reviewers: [codex] }).reviewers, D.clean_layer({ reviewers: [{ name: "codex", local: null }] }).reviewers)[0].local, codex.local],
  ["an invalid gate in a later layer keeps the earlier one", () => D.merged_entries(D.clean_layer({ reviewers: [{ name: "x", gate: "never" }] }).reviewers, D.clean_layer({ reviewers: [{ name: "x", gate: "bogus" }] }).reviewers)[0].gate, "never"],
  ["before the first probe a row with a binary is probing, not missing", () => D.rows([codex], none, null).map(r => [r.installed, r.probing, r.local]), [[false, true, "all"]]],
  ["before the first probe a row without a binary is installed", () => D.rows([{ name: "m" }], none, null).map(r => [r.installed, r.probing]), [[true, false]]],
  ["a click in the local cell steps by half, in the gate cell likewise", () => [D.cell_click(105, 100, 300, 130), D.cell_click(229, 100, 300, 130), D.cell_click(300, 100, 300, 130), D.cell_click(429, 100, 300, 130)], [{ column: 0, delta: -1 }, { column: 0, delta: 1 }, { column: 1, delta: -1 }, { column: 1, delta: 1 }]],
  ["a click on the name or the Installed cell steps nothing", () => [D.cell_click(10, 100, 300, 130), D.cell_click(99, 100, 300, 130), D.cell_click(235, 100, 300, 130), D.cell_click(430, 100, 300, 130)], [null, null, null, null]],
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
  ["a saved choice beats the file's value", () => D.rows([codex], { reviewers: { codex: { local: "public", gate: "never" } } }, ["codex"])[0], { name: "codex", label: "Codex", binary: "codex", installed: true, probing: false, local: "public", gate: "never" }],
  ["a missing binary shows installed no and local off, gate stays", () => D.rows([codex], { reviewers: { codex: { local: "all", gate: "always" } } }, [])[0], { name: "codex", label: "Codex", binary: "codex", installed: false, probing: false, local: "off", gate: "always" }],
  ["a reviewer without a binary counts as installed", () => D.rows([{ name: "mine", local: { command: "mine.sh", default: "public" } }], none, [])[0], { name: "mine", label: "mine", binary: "", installed: true, probing: false, local: "public", gate: "auto" }],
  ["an invalid gate in the file shows auto", () => D.rows([{ name: "x", gate: "sometimes" }], none, [])[0].gate, "auto"],
  ["with_choice changes one field and keeps the other", () => D.with_choice({ reviewers: { codex: { gate: "never" } } }, "codex", "local", "all"), { reviewers: { codex: { gate: "never", local: "all" } } }],
  ["with_choice leaves a field the user never set absent", () => D.with_choice(none, "codex", "gate", "always"), { reviewers: { codex: { gate: "always" } } }],
  ["with_choice ignores an invalid value", () => D.with_choice(none, "codex", "gate", "bogus"), none],
  ["step wraps both ways", () => [D.step("local", "all", 1), D.step("local", "off", -1), D.step("gate", "auto", 1), D.step("gate", "bogus", 1)], ["off", "all", "always", "always"]],
];

// Parity: the rows must show what reviewers.sh resolves from the same user layer. Only files, no Settings layer.
const resolver = path.join(__dirname, "../../claude/.claude/skills/orchestrator/reviewers.sh");
const builtin_layer = { reviewers: [codex, rabbit, { name: "claude", label: "Claude", local: { binary: "claude", default: "off" }, gate: "never" }] };
const user_layers = [
  ["string local", { reviewers: [{ name: "codex", local: "public" }] }],
  ["null local", { reviewers: [{ name: "codex", local: null }, { name: "claude", local: 3 }] }],
  ["invalid gate", { reviewers: [{ name: "codex", gate: "bogus" }, { name: "claude", gate: 7 }] }],
  ["invalid scope", { reviewers: [{ name: "codex", local: { scope: "bogus" } }, { name: "coderabbit", local: { default: "nope" } }] }],
  ["default only", { reviewers: [{ name: "coderabbit", local: { default: "all" } }] }],
  ["enabled", { reviewers: [{ name: "codex", enabled: false }, { name: "claude", enabled: "no" }] }],
  ["new entry", { reviewers: [{ name: "mine", local: { command: "m.sh", default: "public" }, gate: "always" }, { label: "nameless" }] }],
  ["wrong shape", { reviewers: {} }],
];
const parity = [];
if (require("child_process").spawnSync("jq", ["--version"]).status === 0) {
  const dir = fs.mkdtempSync(path.join(require("os").tmpdir(), "dev-parity-"));
  fs.writeFileSync(path.join(dir, "builtin.json"), JSON.stringify(builtin_layer));
  for (const [label, user] of user_layers) {
    parity.push([label, (() => {
      fs.writeFileSync(path.join(dir, "user.json"), JSON.stringify(user));
      const out = require("child_process").spawnSync("bash", [resolver, "list", dir], { encoding: "utf8", env: Object.assign({}, process.env, { REVIEWERS_BUILTIN_FILE: path.join(dir, "builtin.json"), REVIEWERS_USER_FILE: path.join(dir, "user.json"), REVIEWERS_SETTINGS_FILE: path.join(dir, "none.json") }) });
      const sh = JSON.parse(out.stdout).map(e => ({ name: e.name, binary: (e.local || {}).binary || "", local: e.local.scope, gate: e.gate }));
      const merged = D.merged_entries(D.clean_layer(builtin_layer).reviewers, D.clean_layer(user).reviewers);
      const js = D.rows(merged, none, merged.map(e => (e.local || {}).binary).filter(Boolean)).map(r => ({ name: r.name, binary: r.binary, local: r.local, gate: r.gate }));
      return [js, sh];
    })()]);
  }
  fs.rmSync(dir, { recursive: true });
}
for (const [name, run] of parity) cases.push(["parity with reviewers.sh: " + name, () => { const [js, sh] = run; return JSON.stringify(js) === JSON.stringify(sh) ? "same" : { js, sh }; }, "same"]);

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
