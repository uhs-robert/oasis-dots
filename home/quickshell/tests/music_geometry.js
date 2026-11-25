// Runs MusicGeometry.js under node: the music-mode bar rects along the screen frame.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const root = path.join(__dirname, "../.config/quickshell/ui/frames");
const read = name => fs.readFileSync(path.join(root, name), "utf8").replace(/^\.(pragma|import).*$/gm, "");
const load = (name, imports) => { const ctx = vm.createContext(imports); vm.runInContext(read(name), ctx); return ctx; };
const O = load("IslandOutlines.js", {});
const C = load("Corners.js", { Outlines: O });
const F = load("FrameGeometry.js", { Outlines: O, Corners: C });
const T = load("MusicGeometry.js", { Frame: F });
vm.runInContext("this.api = { music_bars, music_bars_for_layout, music_slots, bars_from_slots, frame_from_layout, level_at };", T);
const M = T.api;

// The real frame_layout on a 1000 x 600 screen with a 40 px bar (or none): hole inset 8, corner radius 20.
const kit = { corner: "round", radius: 20, thickness: 8, ornament: "" };
const layout = (edge, has_bar) => F.frame_layout(1000, 600, has_bar ? edge : "", 40, kit);
const loud = Array(48).fill(1);
const quiet = Array(48).fill(0);
const on_edge = (bars, e) => bars.filter(b => b.edge === e);
const hole = { x: 8, y: 40, w: 984, h: 552 };
const strip_free = (bars, tops, bottoms) => bars.every(b => b.y >= tops && b.y + b.h <= 600 - bottoms);

const hole_opt = { grow: "hole" };
const top_bar = M.music_bars_for_layout(layout("top", true), loud, hole_opt);
const band_top = M.music_bars_for_layout(layout("top", false), loud);
const band_bar = M.music_bars_for_layout(layout("top", true), loud);
const bottom_bar = M.music_bars_for_layout(layout("bottom", true), loud, hole_opt);
const no_bar = M.music_bars_for_layout(layout("top", false), loud, hole_opt);
const two = M.music_bars({ w: 1000, h: 600, hole: { x: 8, y: 40, w: 984, h: 520 }, radius: 20, strips: [{ edge: "top", size: 40 }, { edge: "bottom", size: 40 }] }, loud, hole_opt);
const two_band = M.music_bars({ w: 1000, h: 600, hole: { x: 8, y: 40, w: 984, h: 520 }, radius: 20, strips: [{ edge: "top", size: 40 }, { edge: "bottom", size: 40 }] }, loud);

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
  ["a strip overlapping the hole clips the bars", () => strip_free(M.music_bars({ w: 1000, h: 600, hole: { x: 8, y: 10, w: 984, h: 580 }, radius: 20, strips: [{ edge: "top", size: 40 }] }, loud, hole_opt), 40, 0), true],
  ["default grows into the band: right bars start at the hole and stop at the screen edge", () => on_edge(band_top, "right").every(b => b.x === 992 && b.x + b.w === 1000), true],
  ["default: left bars end at the hole and stop at the screen edge", () => on_edge(band_top, "left").every(b => b.x === 0 && b.x + b.w === 8), true],
  ["default: top bars stand on the hole and grow up to the screen edge", () => on_edge(band_top, "top").every(b => b.y === 0 && b.y + b.h === 8), true],
  ["default: bottom bars grow down to the screen edge", () => on_edge(band_top, "bottom").every(b => b.y === 592 && b.y + b.h === 600), true],
  ["default: bars never pass the band depth", () => band_top.every(b => b.x >= 0 && b.y >= 0 && b.x + b.w <= 1000 && b.y + b.h <= 600), true],
  ["default with a top bar: the strip side draws nothing and the strip stays free", () => [on_edge(band_bar, "top").length, strip_free(band_bar, 40, 0)], [0, true]],
  ["default with two strips: top and bottom sides draw nothing, bars stay free", () => [on_edge(two_band, "top").length, on_edge(two_band, "bottom").length, strip_free(two_band, 40, 40), on_edge(two_band, "left").length > 0], [0, 0, true, true]],
  ["zero levels draw nothing", () => M.music_bars_for_layout(layout("top", true), quiet), []],
  ["no levels draw nothing", () => M.music_bars_for_layout(layout("top", true), []), []],
  ["non-numbers count as zero", () => M.music_bars_for_layout(layout("top", true), Array(48).fill(NaN)), []],
  ["a louder level gives a taller bar", () => {
    const lv = Array(48).fill(0); lv[0] = 0.25; const a = M.music_bars_for_layout(layout("top", true), lv, hole_opt);
    lv[0] = 1; const b = M.music_bars_for_layout(layout("top", true), lv, hole_opt);
    return b[0].h > a[0].h && a[0].h > 0;
  }, true],
  ["levels spread over the perimeter by position (hole mode, top bar)", () => {
    const lv = Array(48).fill(0); for (let i = 0; i < 12; i++) lv[i] = 1;
    const bars = M.music_bars_for_layout(layout("top", true), lv, hole_opt);
    return [on_edge(bars, "top").length > 0, on_edge(bars, "bottom").length, on_edge(bars, "left").length];
  }, [true, 0, 0]],
  ["band mode, top bar: the bass lands on the first drawn side (right)", () => {
    const lv = Array(48).fill(0); lv[0] = 1;
    const bars = M.music_bars_for_layout(layout("top", true), lv);
    return [bars.length > 0, bars.every(b => b.edge === "right")];
  }, [true, true]],
  ["band mode, bottom bar: the treble lands on the last drawn side (left)", () => {
    const lv = Array(48).fill(0); lv[47] = 1;
    const bars = M.music_bars_for_layout(layout("bottom", true), lv);
    return [bars.length > 0, bars.every(b => b.edge === "left")];
  }, [true, true]],
  ["default mode, bottom bar: the bottom strip stays free and the top side draws", () => [strip_free(M.music_bars_for_layout(layout("bottom", true), loud), 0, 40), on_edge(M.music_bars_for_layout(layout("bottom", true), loud), "top").every(b => b.y === 0 && b.h === 8), on_edge(M.music_bars_for_layout(layout("bottom", true), loud), "bottom").length], [true, true, 0]],
  ["levels rise clockwise: top, right, then bottom and left read from their far ends", () => {
    const ramp = Array.from({ length: 48 }, (_, i) => i / 47);
    const bars = M.music_bars_for_layout(layout("top", false), ramp);
    const len = b => (b.edge === "top" || b.edge === "bottom") ? b.h : b.w;
    const by = (e, key, dir) => on_edge(bars, e).sort((p, q) => dir * (p[key] - q[key]));
    const walk = [].concat(by("top", "x", 1), by("right", "y", 1), by("bottom", "x", -1), by("left", "y", -1)).map(len);
    return [walk.length > 8, walk.every((v, i) => i === 0 || v >= walk[i - 1])];
  }, [true, true]],
  ["bars sit on whole pixels", () => band_top.every(b => [b.x, b.y, b.w, b.h].every(Number.isInteger)), true],
  ["one cached plan serves changing levels like a fresh plan each time", () => {
    const frame = M.frame_from_layout(layout("top", true));
    const ramp = Array.from({ length: 48 }, (_, i) => i / 47);
    const falling = ramp.slice().reverse();
    const plan = M.music_slots(frame);
    return [ramp, falling, ramp].map(lv => JSON.stringify(M.bars_from_slots(plan, lv)) === JSON.stringify(M.bars_from_slots(M.music_slots(frame), lv)) && M.bars_from_slots(plan, lv).length > 0);
  }, [true, true, true]],
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
