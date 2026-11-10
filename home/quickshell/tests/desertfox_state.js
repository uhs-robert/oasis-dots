// Runs DesertfoxState.js under node: which state files count as a live version 1, what the chip and the which-key
// panel take from one, and the Firefox class gate.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const file = path.join(__dirname, "../.config/quickshell/features/desertfox/DesertfoxState.js");
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(file, "utf8").replace(/^\.pragma.*$/m, "") + "\nthis.api = { validate, payload_of, panel_key, is_firefox_class, empty };", ctx);
const D = ctx.api;

const row = (keys, command, more) => ({ keys: keys, command: command, description: "", more: more });
const file_of = extra => Object.assign({
  version: 1, seq: 42, host: { pid: 48211, start: "9123456" },
  firefox: { window_id: 3, fullscreen: false, private: false },
  mode: { id: "visual_line", label: "V-LINE", tab_id: 17 },
  whichkey: { seq: 7, title: ["+Go", "+Close tabs"], border: "square", rows: [row("gt", "Next tab", false), row("gc", "+Close tabs", true), { keys: "gi", command: "", description: "Focus input", more: false }] }
}, extra || {});

const cases = [
  ["a version 1 file is valid", () => D.validate(file_of()).valid, true],
  ["host and mode come through", () => { const v = D.validate(file_of()); return [v.host_pid, v.host_start, v.mode_id, v.mode_label]; }, [48211, "9123456", "visual_line", "V-LINE"]],
  ["an unknown version is no state", () => D.validate(file_of({ version: 2 })), D.empty],
  ["a missing version is no state", () => D.validate({ mode: { id: "normal", label: "NORMAL" } }).valid, false],
  ["a string version is no state", () => D.validate(file_of({ version: "1" })).valid, false],
  ["a non-object is no state", () => [D.validate(null).valid, D.validate(5).valid], [false, false]],
  ["rows map to items: keys, command or description, more as group", () => D.validate(file_of()).whichkey_items,
    [{ key: "gt", desc: "Next tab", group: false }, { key: "gc", desc: "+Close tabs", group: true }, { key: "gi", desc: "Focus input", group: false }]],
  ["the title joins with a space", () => D.validate(file_of()).whichkey_title, "+Go +Close tabs"],
  ["whichkey null has no items and seq 0", () => { const v = D.validate(file_of({ whichkey: null })); return [v.whichkey_items, v.whichkey_seq]; }, [[], 0]],
  ["the payload carries title and items only", () => Object.keys(D.payload_of(D.validate(file_of()))).sort(), ["items", "title"]],
  ["a mode change keeps the panel key", () => D.panel_key(D.validate(file_of({ mode: { id: "insert", label: "INSERT" }, seq: 43 }))), D.panel_key(D.validate(file_of()))],
  ["a new panel seq changes the key", () => D.panel_key(D.validate(file_of({ whichkey: { seq: 8, title: [], rows: [] } }))) !== D.panel_key(D.validate(file_of())), true],
  ["a new host with the same seq changes the key", () => D.panel_key(D.validate(file_of({ host: { pid: 1, start: "2" } }))) !== D.panel_key(D.validate(file_of())), true],
  ["a missing mode gives an empty label", () => D.validate(file_of({ mode: undefined })).mode_label, ""],
  ["firefox classes", () => ["firefox", "Firefox", "firefox-developer-edition", "foot", "", null].map(D.is_firefox_class), [true, true, true, false, false, false]],
];

let failed = 0;
for (const [name, run, want] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(run())), JSON.parse(JSON.stringify(want)));
    console.log("ok   " + name);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + "\n     " + String(e.message).split("\n").join("\n     "));
  }
}
process.exit(failed ? 1 : 0);
