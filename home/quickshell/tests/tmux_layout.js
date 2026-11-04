// Runs TmuxLayout.js under node: which panes the tmux preview draws and where, the font size that fits the window's
// grid, the letterbox, tmux's borders between panes and the chosen pane's outline.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const file = path.join(__dirname, "../.config/quickshell/features/launcher/TmuxLayout.js");
const ctx = vm.createContext({});
const names = ["drawn_panes", "grid_size", "font_px_to_fit", "fitted_px", "layout_key", "letterbox", "borders", "frame", "screen_text"];
vm.runInContext(fs.readFileSync(file, "utf8").replace(/^\.pragma.*$/m, "") + "\nthis.api = { " + names.join(", ") + " };", ctx);
const L = ctx.api;

// A 160x40 window: %1 over %3 on the left, %2 the full height on the right, with tmux's one-cell borders between.
const pane = (pane_id, left, top, width, height) => ({ pane_id, left, top, width, height });
const split = { width: 160, height: 40, zoomed: false, panes: [pane("%1", 0, 0, 79, 19), pane("%2", 80, 0, 80, 40), pane("%3", 0, 20, 79, 20)] };
const drawn = L.drawn_panes(split, split.panes[0]);
const at = id => drawn.find(p => p.pane_id === id);

const cases = [
  ["every pane at its place in cells", () => drawn.map(p => [p.pane_id, p.x, p.y, p.w, p.h]), [["%1", 0, 0, 79, 19], ["%2", 80, 0, 80, 40], ["%3", 0, 20, 79, 20]]],
  ["a zoomed window draws the shown pane alone from the top left", () => L.drawn_panes(Object.assign({}, split, { zoomed: true }), split.panes[1]), [{ pane_id: "%2", x: 0, y: 0, w: 80, h: 40 }]],
  ["no window draws nothing", () => L.drawn_panes(null, null), []],
  ["the grid is the window's size", () => L.grid_size(split), { cols: 160, rows: 40 }],
  ["without a size the grid spans the panes", () => L.grid_size(Object.assign({}, split, { width: 0, height: 0 })), { cols: 160, rows: 40 }],
  ["no window has an empty grid", () => L.grid_size(null), { cols: 0, rows: 0 }],
  ["the font fits the narrower side", () => [L.font_px_to_fit(160, 40, 800, 600, 0.6, 1.2), L.font_px_to_fit(80, 24, 2000, 300, 0.6, 1.2)], [8, 10]],
  ["the font is at least a pixel", () => L.font_px_to_fit(400, 100, 50, 50, 0.6, 1.2), 1],
  ["an empty grid or area gets no font", () => [L.font_px_to_fit(0, 40, 800, 600, 0.6, 1.2), L.font_px_to_fit(160, 40, 0, 600, 0.6, 1.2)], [0, 0]],
  ["the letterbox centres the grid across, from the top", () => L.letterbox(301, 100, 600, 401), { x: 149, y: 0, w: 301, h: 100 }],
  ["a fitting grid keeps its font size", () => L.fitted_px(8, 790, 590, 800, 600), 8],
  ["a grid that overflows once measured steps down", () => [L.fitted_px(8, 820, 500, 800, 600), L.fitted_px(8, 2000, 500, 800, 600), L.fitted_px(1, 2000, 500, 800, 600)], [7, 3, 1]],
  ["the layout key changes with a pane's place or size only", () => { const moved = Object.assign({}, split, { panes: split.panes.map(p => p.pane_id === "%3" ? Object.assign({}, p, { top: 21, height: 19 }) : p) }); return [L.layout_key(split) === L.layout_key(Object.assign({}, split, { activity: 9 })), L.layout_key(split) === L.layout_key(moved), L.layout_key(Object.assign({}, split, { zoomed: true })) === L.layout_key(split), L.layout_key(null)]; }, [true, false, false, ""]],
  ["a grid larger than the area starts at its corner", () => L.letterbox(700, 500, 600, 400), { x: 0, y: 0, w: 700, h: 500 }],
  ["borders run through the cells between panes, into the shared corner", () => L.borders(drawn, 160, 40), [{ x1: 79.5, y1: 0, x2: 79.5, y2: 19.5 }, { x1: 0, y1: 19.5, x2: 79.5, y2: 19.5 }, { x1: 79.5, y1: 19.5, x2: 79.5, y2: 40 }]],
  ["a single pane has no borders", () => L.borders([{ pane_id: "%1", x: 0, y: 0, w: 80, h: 24 }], 80, 24), []],
  ["the outline sits on shared borders and the window's edges", () => [L.frame(at("%1"), 160, 40), L.frame(at("%2"), 160, 40), L.frame(at("%3"), 160, 40)], [{ x: 0, y: 0, w: 79.5, h: 19.5 }, { x: 79.5, y: 0, w: 80.5, h: 40 }, { x: 0, y: 19.5, w: 79.5, h: 20.5 }]],
  ["the screen is the pane's first rows", () => [L.screen_text(["a", "b", "c", ""], 2), L.screen_text(["a"], 3), L.screen_text(undefined, 3)], ["a\nb", "a", ""]],
];

let failed = 0;
for (const [name, run, want] of cases) {
  let got;
  try {
    got = JSON.parse(JSON.stringify(run()));
    assert.deepStrictEqual(got, want);
  } catch (e) {
    failed += 1;
    console.log("FAIL " + name + "\n  want: " + JSON.stringify(want) + "\n  got:  " + (got === undefined ? e : JSON.stringify(got)));
  }
}
console.log(cases.length - failed + "/" + cases.length + " passed");
process.exit(failed ? 1 : 0);
