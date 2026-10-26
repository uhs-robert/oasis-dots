// Checks the title_readout_size token: it defaults to 0 (the popup title keeps its fs(-5) size) and only GoldenEye sets it.
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
for (const style of fs.readdirSync(path.join(qs, "styles"))) {
  const file = path.join(qs, "styles", style, "tokens.js");
  if (!fs.existsSync(file)) continue;
  cases.push([style + " sets it only if GoldenEye", () => /title_readout_size/.test(fs.readFileSync(file, "utf8")), style === "goldeneye"]);
}

let failed = 0;
for (const [name, run, want] of cases) {
  let got;
  try { got = run(); } catch (e) { got = "threw " + e.message; }
  try { assert.deepStrictEqual(got, want); } catch (e) { failed++; console.error("FAIL " + name + ": got " + JSON.stringify(got) + ", want " + JSON.stringify(want)); }
}
if (failed) process.exit(1);
console.log(cases.length + " style title readout checks passed");
