// Runs Sections.js under node: unique ids, every source a section file, and old ids merged away still resolving.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const dir = path.join(__dirname, "../.config/quickshell/features/settings");
const source = fs.readFileSync(path.join(dir, "Sections.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { list, aliases, resolve };", T);
const S = T.api;
const ids = S.list.map(s => s.id);

const cases = [
  ["ids are unique", () => new Set(ids).size === ids.length, true],
  ["every source exists", () => S.list.filter(s => !fs.existsSync(path.join(dir, s.source))).map(s => s.source), []],
  ["an alias never hides a real id", () => Object.keys(S.aliases).filter(a => ids.includes(a)), []],
  ["every alias reaches a section", () => Object.keys(S.aliases).filter(a => S.resolve(a).index < 0), []],
  ["old ids still open", () => ["clock", "calendar", "colors", "lock", "login", "audio"].filter(id => S.resolve(id).index < 0), []],
  ["colors opens Style on its Colors heading", () => [S.list[S.resolve("colors").index].id, S.resolve("colors").part], ["style", "Colors"]],
  ["a real id opens at its top", () => S.resolve("media").part, ""],
  ["an unknown id resolves to nothing", () => S.resolve("nope").index, -1],
  ["the merged section's parts are in its file", () => Object.entries(S.aliases).filter(([, a]) => !fs.readFileSync(path.join(dir, S.list[S.resolve(a.id).index].source), "utf8").includes('heading: "' + a.part + '"')).map(([id]) => id), []],
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
console.log("settings sections: " + cases.length + " checks passed");
