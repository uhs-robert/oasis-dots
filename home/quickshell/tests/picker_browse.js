// Runs BrowseLayout.js under node: the browse picker's preview dial and how the cards share its body.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/launcher/BrowseLayout.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { size_of, grown, shrunk, toggled, columns, split };", context);
const { size_of, grown, shrunk, toggled, columns, split } = context.api;

// A 1080p body: 760 tall under the title, 720 of it under the search bar; cards 112 tall with an 8 gap.
const body = 760, area = 720, row = 120, gap = 8;

const cases = [
  // req: PICKERS-05
  ["= steps up through every size", () => ["off", "s", "m"].map(grown), ["s", "m", "l"]],
  ["= stops at large", () => grown("l"), "l"],
  ["- steps down through every size", () => ["l", "m", "s"].map(shrunk), ["m", "s", "off"]],
  ["- stops at off", () => shrunk("off"), "off"],
  ["p hides an open preview", () => ["s", "m", "l"].map(s => toggled(s, s)), ["off", "off", "off"]],
  ["p brings it back at its last size", () => toggled("off", "l"), "l"],
  ["p with no last size comes back medium", () => [toggled("off", "off"), toggled("off", "")], ["m", "m"]],
  ["an unknown size reads as medium", () => [size_of("huge"), size_of(undefined), size_of("l")], ["m", "m", "l"]],
  // req: PICKERS-04
  ["large leaves one row, a filmstrip", () => split(area, body, "l", row, gap).rows, 1],
  ["medium leaves two rows", () => split(area, body, "m", row, gap).rows, 2],
  ["small leaves three rows", () => split(area, body, "s", row, gap).rows, 3],
  ["off gives the cards everything", () => split(area, body, "off", row, gap), { rows: 6, preview_height: 0 }],
  ["the preview takes what the rows leave", () => { const s = split(area, body, "m", row, gap); return s.rows * row + gap + s.preview_height; }, area],
  ["a tiny body still shows one row", () => split(100, 140, "l", row, gap).rows, 1],
  ["columns fit the width with gaps between", () => [columns(1500, 280, 8), columns(287, 280, 8), columns(100, 280, 8)], [5, 1, 1]],
];

let failed = 0;
for (const [name, run, expected] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(run())), expected);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}
if (failed > 0) {
  console.error(failed + " failed");
  process.exit(1);
}
console.log("picker_browse: " + cases.length + " ok");
