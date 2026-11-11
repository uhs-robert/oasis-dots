// Runs DesertfoxState.js under node: which state files count as a live version 2, what the chip takes from one
// (including a private window's id-free file), and the Firefox class gate.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const file = path.join(__dirname, "../.config/quickshell/features/desertfox/DesertfoxState.js");
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(file, "utf8").replace(/^\.pragma.*$/m, "") + "\nthis.api = { validate, hides_chip, is_firefox_class, empty };", ctx);
const D = ctx.api;

const file_of = extra => Object.assign({
  version: 2, seq: 42, host: { pid: 48211, start: "9123456" },
  firefox: { window_id: 3, private: false },
  mode: { id: "visual_line", label: "V-LINE", tab_id: 17 }
}, extra || {});

const cases = [
  ["a version 2 file is valid", () => D.validate(file_of()).valid, true],
  ["host and mode come through", () => { const v = D.validate(file_of()); return [v.host_pid, v.host_start, v.mode_id, v.mode_label]; }, [48211, "9123456", "visual_line", "V-LINE"]],
  ["a version 1 file is no state", () => D.validate(file_of({ version: 1 })), D.empty],
  ["an unknown version is no state", () => D.validate(file_of({ version: 3 })), D.empty],
  ["a missing version is no state", () => D.validate({ mode: { id: "normal", label: "NORMAL" } }).valid, false],
  ["a string version is no state", () => D.validate(file_of({ version: "2" })).valid, false],
  ["a non-object is no state", () => [D.validate(null).valid, D.validate(5).valid], [false, false]],
  ["a private window's id-free file is valid and keeps its mode", () => {
    const v = D.validate(file_of({ firefox: { private: true }, mode: { id: "normal", label: "NORMAL" } }));
    return [v.valid, v.mode_id, v.mode_label];
  }, [true, "normal", "NORMAL"]],
  ["hint and cmdline hide the chip", () => ["hint", "cmdline"].map(D.hides_chip), [true, true]],
  ["every other mode shows it", () => ["normal", "insert", "ignore", "caret", "visual", "visual_line", ""].map(D.hides_chip), [false, false, false, false, false, false, false]],
  ["a missing mode gives an empty label", () => D.validate(file_of({ mode: undefined })).mode_label, ""],
  ["firefox classes", () => ["firefox", "Firefox", "firefox-developer-edition", "org.mozilla.firefox", "foot", "", null].map(D.is_firefox_class), [true, true, true, true, false, false, false]],
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
