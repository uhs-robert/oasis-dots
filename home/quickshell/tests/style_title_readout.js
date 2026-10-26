// Checks the title_readout_size token: it defaults to 0 (the popup title keeps its fs(-5) size) and a style that sets it sets a positive size.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const qs = path.join(__dirname, "../.config/quickshell");
const read = rel => fs.readFileSync(path.join(qs, rel), "utf8");

const T = vm.createContext({});
vm.runInContext(read("theme/StyleSchema.js").replace(/^\.pragma.*$/m, "") + "\nthis.tokens = tokens;", T);
const token = T.tokens.find(k => k.name === "title_readout_size");

const cases = [
  ["schema has the token", () => token !== undefined, true],
  ["default is 0, the fs(-5) size", () => token && token.value, 0],
  ["PopupTitle falls back to fs(-5) on 0", () => /title_readout_size > 0 \? [^:]+ : root\.st\.fs\(-5\)/.test(read("features/popups/frames/PopupTitle.qml")), true],
];
// A style may set the token, but a literal must be a positive int (0 is the unset default; a computed value is taken as given).
// Every *tokens.js file in a style folder is scanned, so goldeneye/watch_tokens.js is covered too.
for (const style of fs.readdirSync(path.join(qs, "styles"))) {
  const dir = path.join(qs, "styles", style);
  if (!fs.statSync(dir).isDirectory()) continue;
  for (const file of fs.readdirSync(dir).filter(f => f.endsWith("tokens.js"))) {
    const set = fs.readFileSync(path.join(dir, file), "utf8").match(/title_readout_size:\s*([^,\n]+)/);
    if (!set) continue;
    cases.push([style + "/" + file + " sets a positive size", () => !/^-?\d+(\.\d+)?$/.test(set[1].trim()) || /^[1-9]\d*$/.test(set[1].trim()), true]);
  }
}

let failed = 0;
for (const [name, run, want] of cases) {
  let got;
  try { got = run(); } catch (e) { got = "threw " + e.message; }
  try { assert.deepStrictEqual(got, want); } catch (e) { failed++; console.error("FAIL " + name + ": got " + JSON.stringify(got) + ", want " + JSON.stringify(want)); }
}
if (failed) process.exit(1);
console.log(cases.length + " style title readout checks passed");
