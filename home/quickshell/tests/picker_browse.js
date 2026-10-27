// Runs BrowseLayout.js under node: the browse picker's preview dial, how the cards or list share its body, the quick
// pick digits and the clipboard's type filter.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/launcher/BrowseLayout.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { size_of, grown, shrunk, toggled, columns, split, fit, toggled_view, digit_index, hint_of, cycled_filter, kept_by_filter, filter_labels };", context);
const { size_of, grown, shrunk, toggled, columns, split, fit, toggled_view, digit_index, hint_of, cycled_filter, kept_by_filter, filter_labels } = context.api;

// A 1080p body: 760 tall under the title, 720 of it under the search bar; cards 112 tall with an 8 gap.
const body = 760, area = 720, row = 120, gap = 8;

const cases = [
  // req: PICKERS-05
  ["= steps up through every size", () => ["off", "s", "m"].map(grown), ["s", "m", "l"]],
  // req: PICKERS-16
  ["= at large goes on to max, and stops there", () => [grown("l"), grown("max")], ["max", "max"]],
  // req: PICKERS-16
  ["- at max steps back to large", () => shrunk("max"), "l"],
  // req: PICKERS-16
  ["p hides max and brings it back", () => [toggled("max", "max"), toggled("off", "max")], ["off", "max"]],
  // req: PICKERS-16
  ["max gives the preview everything and hides the rows", () => split(area, body, "max", row, gap), { rows: 0, preview_height: area }],
  ["max never overflows, so no cue", () => fit(area, body, "max", row, gap, 50, 4, 20), { rows: 0, preview_height: area, view_height: 0, overflows: false }],
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
  // req: PICKERS-12
  ["items that fit leave the layout as it was", () => fit(area, body, "m", row, gap, 8, 4, 20), { rows: 2, preview_height: 472, view_height: 240, overflows: false }],
  // req: PICKERS-12
  ["items past the rows widen the view by a faded peek at each end", () => { const f = fit(area, body, "m", row, gap, 9, 4, 20); return [f.overflows, f.view_height - f.rows * row]; }, [true, 40]],
  // req: PICKERS-12
  ["the peek comes out of the preview, not past the area", () => { const f = fit(area, body, "l", row, gap, 9, 4, 20); return f.preview_height + gap + f.view_height; }, area],
  // req: PICKERS-12
  ["the single-row strip keeps its row with the peek", () => fit(area, body, "l", row, gap, 9, 4, 20).rows, 1],
  // req: PICKERS-12
  ["medium keeps its two rows; the preview gives up the peek", () => { const f = fit(area, body, "m", row, gap, 9, 4, 20); return [f.rows, f.preview_height]; }, [2, 432]],
  // req: PICKERS-12
  ["an off preview gives a row to the peek when the area has no spare", () => fit(area, body, "off", row, gap, 50, 4, 20), { rows: 5, preview_height: 0, view_height: 640, overflows: true }],
  ["an off preview keeps its rows when the spare holds the peek", () => fit(760, body, "off", row, gap, 50, 4, 20).rows, 6],
  // req: PICKERS-13
  ["v flips grid and list", () => [toggled_view("grid"), toggled_view("list"), toggled_view(undefined)], ["list", "grid", "list"]],
  // req: PICKERS-13
  ["list rows follow the room left under the preview", () => [split(area, body, "l", 38, gap).rows, split(area, body, "off", 38, gap).rows], [4, 18]],
  // req: PICKERS-14
  ["digits 1-9 pick the nth item", () => ["1", "5", "9"].map(d => digit_index(d, 20)), [0, 4, 8]],
  // req: PICKERS-14
  ["0, letters and digits past the end pick nothing", () => [digit_index("0", 20), digit_index("j", 20), digit_index("12", 20), digit_index("4", 3), digit_index(undefined, 3)], [-1, -1, -1, -1, -1]],
  // req: PICKERS-14
  ["only the first nine show a number", () => [0, 8, 9, -1].map(hint_of), ["1", "9", "", ""]],
  // req: PICKERS-15
  ["f cycles all, text, images and back", () => ["all", "text", "image", "bogus"].map(cycled_filter), ["text", "image", "all", "all"]],
  // req: PICKERS-15
  ["binary entries show only under all", () => ["all", "text", "image"].map(f => ["text", "image", "binary"].filter(k => kept_by_filter(k, f))), [["text", "image", "binary"], ["text"], ["image"]]],
  ["each filter has a label for the search bar", () => ["all", "text", "image"].map(f => filter_labels[f]), ["ALL", "TEXT", "IMAGES"]],
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
