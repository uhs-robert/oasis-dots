// Runs MusicGeometry.js under node: the music-mode bar rects along the screen frame.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/ui/frames/MusicGeometry.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { music_bars, music_bars_for_layout, frame_from_layout, level_at };", T);
const M = T.api;

// A layout with the fields frame_layout documents (top bar: near is the bar's height).
const layout = (edge, has_bar) => ({
  edge, has_bar, length: 1000, depth: 600, near: has_bar ? 40 : 8, far: 592, start: 8, end: 8, radius: 20,
});
const loud = Array(48).fill(1);
const quiet = Array(48).fill(0);
const on_edge = (bars, e) => bars.filter(b => b.edge === e);
const hole = { x: 8, y: 40, w: 984, h: 552 };
const strip_free = (bars, tops, bottoms) => bars.every(b => b.y >= tops && b.y + b.h <= 600 - bottoms);

const top_bar = M.music_bars_for_layout(layout("top", true), loud);
const bottom_bar = M.music_bars_for_layout(layout("bottom", true), loud);
const no_bar = M.music_bars_for_layout(layout("top", false), loud);
const two = M.music_bars({ w: 1000, h: 600, hole: { x: 8, y: 40, w: 984, h: 520 }, radius: 20, strips: [{ edge: "top", size: 40 }, { edge: "bottom", size: 40 }] }, loud);

const cases = [
  ["every edge gets bars", () => ["top", "right", "bottom", "left"].map(e => on_edge(top_bar, e).length > 0), [true, true, true, true]],
  ["top bars stand on the hole's top and grow down", () => on_edge(top_bar, "top").every(b => b.y === 40 && b.h > 0), true],
  ["bottom bars end on the hole's bottom", () => on_edge(top_bar, "bottom").every(b => b.y + b.h === 592), true],
  ["left bars start at the hole's left", () => on_edge(top_bar, "left").every(b => b.x === 8), true],
  ["right bars end at the hole's right", () => on_edge(top_bar, "right").every(b => b.x + b.w === 992), true],
  ["corners are skipped on the top and bottom", () => top_bar.filter(b => b.edge === "top" || b.edge === "bottom").every(b => b.x >= 28 && b.x + b.w <= 972), true],
  ["corners are skipped on the sides", () => top_bar.filter(b => b.edge === "left" || b.edge === "right").every(b => b.y >= 60 && b.y + b.h <= 572), true],
  ["top bar strip stays free", () => strip_free(top_bar, 40, 0), true],
  ["bottom bar strip stays free", () => strip_free(bottom_bar, 0, 40), true],
  ["bottom bar: bars stand under the hole's top edge at 8", () => on_edge(bottom_bar, "top").every(b => b.y === 8), true],
  ["no bar: bars use the thin band's edge", () => on_edge(no_bar, "top").every(b => b.y === 8), true],
  ["two strips: both stay free", () => strip_free(two, 40, 40), true],
  ["two strips: every edge still has bars", () => ["top", "right", "bottom", "left"].map(e => on_edge(two, e).length > 0), [true, true, true, true]],
  ["a strip overlapping the hole clips the bars", () => strip_free(M.music_bars({ w: 1000, h: 600, hole: { x: 8, y: 10, w: 984, h: 580 }, radius: 20, strips: [{ edge: "top", size: 40 }] }, loud), 40, 0), true],
  ["zero levels draw nothing", () => M.music_bars_for_layout(layout("top", true), quiet), []],
  ["no levels draw nothing", () => M.music_bars_for_layout(layout("top", true), []), []],
  ["non-numbers count as zero", () => M.music_bars_for_layout(layout("top", true), Array(48).fill(NaN)), []],
  ["a louder level gives a taller bar", () => {
    const lv = Array(48).fill(0); lv[0] = 0.25; const a = M.music_bars_for_layout(layout("top", true), lv);
    lv[0] = 1; const b = M.music_bars_for_layout(layout("top", true), lv);
    return b[0].h > a[0].h && a[0].h > 0;
  }, true],
  ["levels spread over the perimeter by position", () => {
    const lv = Array(48).fill(0); for (let i = 0; i < 12; i++) lv[i] = 1;
    const bars = M.music_bars_for_layout(layout("top", true), lv);
    return [on_edge(bars, "top").length > 0, on_edge(bars, "bottom").length];
  }, [true, 0]],
  ["bars do not overlap on one edge", () => { const t = on_edge(top_bar, "top"); return t.every((b, i) => i === 0 || b.x >= t[i - 1].x + t[i - 1].w); }, true],
  ["a tiny hole draws nothing and does not throw", () => M.music_bars({ w: 40, h: 40, hole: { x: 5, y: 5, w: 30, h: 30 }, radius: 15, strips: [] }, loud), []],
  ["levels are not mutated", () => { const l = [1, 0.5]; M.music_bars_for_layout(layout("top", true), l); return l; }, [1, 0.5]],
  ["adapter: top bar hole sits below the strip", () => M.frame_from_layout(layout("top", true)).hole, hole],
  ["adapter: bottom bar hole sits above the strip", () => M.frame_from_layout(layout("bottom", true)).hole, { x: 8, y: 8, w: 984, h: 552 }],
];

let failed = 0;
for (const [name, fn, expected] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(fn())), expected);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + "\n  " + e.message.split("\n")[0]);
  }
}
if (failed) process.exit(1);
console.log("music geometry: " + cases.length + " checks passed");
