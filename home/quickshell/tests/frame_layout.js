// Runs FrameGeometry.js's frame_layout under node with each set of bar edges a screen can have: a top bar, a bottom bar
// (the canonical frame mirrored), both, and none. Checks the hole, the zones, the fill, the lines round the hole and how
// a far strip sees the frame.
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
const plain = v => JSON.parse(JSON.stringify(v));

// Unequal bar heights, so a swapped near and far strip shows.
const W = 1920, H = 1080, TOP = 30, BOTTOM = 26;
const kit = { corner: "round", radius: 12, thickness: 6, ornament: "" };
const top_only = F.frame_layout(W, H, { top: TOP }, kit);
const bottom_only = F.frame_layout(W, H, { bottom: TOP }, kit);
const both = F.frame_layout(W, H, { top: TOP, bottom: BOTTOM }, kit);
const none = F.frame_layout(W, H, {}, kit);

const loop_area = loop => Math.abs(loop.reduce((s, p, k) => k === 0 ? 0 : s + loop[k - 1][0] * p[1] - p[0] * loop[k - 1][1], 0)) / 2;
const closed = (loop, tol = 1e-9) => Math.hypot(loop[0][0] - loop[loop.length - 1][0], loop[0][1] - loop[loop.length - 1][1]) < tol;
const blocks_area = blocks => blocks.reduce((a, b) => a + b.w * b.h, 0);
const disjoint = b => b.every((r, i) => b.every((q, j) => j <= i || r.x + r.w <= q.x + 1e-9 || q.x + q.w <= r.x + 1e-9 || r.y + r.h <= q.y + 1e-9 || q.y + q.h <= r.y + 1e-9));
const segments_cross = (a, b, c, d) => {
  const side = (p, q, r) => Math.sign((q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]));
  return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0;
};
const self_intersects = pts => pts.some((p, i) => i + 1 < pts.length && pts.some((q, j) => j > i + 1 && j + 1 < pts.length && segments_cross(p, pts[i + 1], q, pts[j + 1])));
const on_screen = (lay, p) => { const m = F.to_screen(lay); return [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]]; };
// A polyline as a sorted set of rounded screen points, so two drawings of one line compare equal whatever their order.
const point_set = (lay, lines) => lines.flatMap(line => line.map(p => on_screen(lay, p).map(v => Math.round(v * 1e6) / 1e6).join(","))).sort();
// The band area between the strips: every pixel but the hole and the strips, plus the fill's overlap rows past the
// straight stretches, less each hole corner's free area. The arcs are chords (ARC_STEPS 10), which cut each corner's
// sector short by about 0.0033 r^2, so areas compare to corner_slack.
const corner_free = r => r * r * (1 - Math.PI / 4);
const corner_slack = r => 0.1 + 4 * 0.0035 * r * r;

const cases = [
  ["top only: on the top edge, near strip only", () => [top_only.edge, top_only.has_bar, top_only.far_bar], ["top", true, false]],
  ["top only: hole and zones", () => plain([top_only.near, top_only.far, top_only.zones]), [30, 1074, { top: 30, right: 6, bottom: 6, left: 6 }]],
  ["top only: bar edges filled in", () => plain(top_only.bar_edges), { top: 30, bottom: 0 }],
  ["top only: no stroke clip at the bottom", () => F.stroke_clip_bottom(top_only), H],

  // A lone bottom bar draws the top bar's canonical frame turned over.
  ["bottom only: canonical frame on the bottom edge", () => [bottom_only.edge, bottom_only.has_bar, bottom_only.far_bar], ["bottom", true, false]],
  ["bottom only: same canonical hole as a top bar", () => plain([bottom_only.near, bottom_only.far, bottom_only.straight]), plain([top_only.near, top_only.far, top_only.straight])],
  ["bottom only: same fill as a top bar, mirrored", () => plain([F.frame_region(bottom_only), F.frame_blocks(bottom_only)]), plain([F.frame_region(top_only), F.frame_blocks(top_only)])],
  ["bottom only: to_screen mirrors v", () => plain(F.to_screen(bottom_only)), [1, 0, 0, -1, 0, H]],
  ["bottom only: zones", () => plain(bottom_only.zones), { top: 6, right: 6, bottom: 30, left: 6 }],
  ["bottom only: hole on screen", () => plain(F.hole_rect(bottom_only)), { x: 6, y: 6, w: 1908, h: 1044 }],
  ["bottom only: seams", () => ["top", "bottom", "left", "right"].map(e => F.seam_of(bottom_only, e)), [6, 1050, 6, 1914]],

  ["none: plain bands", () => [none.edge, none.has_bar, none.far_bar, none.near, none.far], ["top", false, false, 6, 1074]],
  ["none: zones", () => plain(none.zones), { top: 6, right: 6, bottom: 6, left: 6 }],
  ["none: the stroke closes round the hole", () => { const s = F.frame_strokes(none, 1); return s.length === 1 && closed(s[0], 0.1); }, true],
  ["absent, negative and junk edges count as none", () => plain([F.frame_layout(W, H, undefined, kit).bar_edges, F.frame_layout(W, H, { top: -4, bottom: "x" }, kit).bar_edges]), [{ top: 0, bottom: 0 }, { top: 0, bottom: 0 }]],

  ["both: top bar is the near strip, bottom the far", () => [both.edge, both.has_bar, both.far_bar], ["top", true, true]],
  ["both: hole between the strips", () => plain([both.near, both.far, both.start, both.end]), [TOP, H - BOTTOM, 6, 6]],
  ["both: each edge reserves its own bar", () => plain(both.zones), { top: TOP, right: 6, bottom: BOTTOM, left: 6 }],
  ["both: bar edges as given", () => plain(both.bar_edges), { top: TOP, bottom: BOTTOM }],
  ["both: hole on screen", () => plain(F.hole_rect(both)), { x: 6, y: TOP, w: 1908, h: H - TOP - BOTTOM }],
  ["both: seams", () => ["top", "bottom", "left", "right"].map(e => F.seam_of(both, e)), [TOP, H - BOTTOM, 6, 1914]],
  ["both: fill is two closed side loops", () => { const r = F.frame_region(both); return [r.length, r.every(l => closed(l))]; }, [2, true]],
  ["both: fill stays between the overlap rows", () => F.frame_region(both).every(l => l.every(p => p[1] >= TOP - 1 && p[1] <= H - BOTTOM + 1)), true],
  ["both: fill's overlap is only past the straight stretches", () => F.frame_region(both).every(l => l.filter(p => p[1] < both.near || p[1] > both.far).every(p => p[0] <= both.straight[0] + 1e-9 || p[0] >= both.straight[1] - 1e-9)), true],
  ["both: fill area is the side bands and the corners", () => {
    const want = 2 * 6 * (both.far - both.near + 2) + 2 * 2 * (both.straight[0] - 6) + 4 * corner_free(both.radius);
    return Math.abs(F.frame_region(both).reduce((a, l) => a + loop_area(l), 0) - want) < corner_slack(both.radius);
  }, true],
  ["both: blocks are disjoint and cover the fill", () => {
    const b = F.frame_blocks(both), area = F.frame_region(both).reduce((a, l) => a + loop_area(l), 0);
    return disjoint(b) && Math.abs(blocks_area(b) - area) < 0.02 * both.radius * both.radius * 4;
  }, true],
  ["both: no block reaches into a strip past its overlap", () => F.frame_blocks(both).every(b => b.y >= TOP - 1 && b.y + b.h <= H - BOTTOM + 1), true],
  ["both: stroke clip ends a whole px past the far overlap", () => [F.stroke_clip_top(both), F.stroke_clip_bottom(both)], [TOP - 2, H - BOTTOM + 2]],
  ["both: translucent islands clip at the strips' edges", () => { const l = F.frame_layout(W, H, { top: TOP, bottom: BOTTOM }, Object.assign({}, kit, { fill_overlap: 0 })); return [F.stroke_clip_top(l), F.stroke_clip_bottom(l), F.frame_blocks(l).every(b => b.y >= TOP && b.y + b.h <= H - BOTTOM)]; }, [TOP, H - BOTTOM, true]],
  ["both: a drawer at the bottom gaps the bottom strip only", () => plain([F.strip_gaps([{ x: 100, y: H - 40, w: 50, h: 40 }], "bottom", BOTTOM, H), F.strip_gaps([{ x: 100, y: H - 40, w: 50, h: 40 }], "top", TOP, H)]), [[{ x: 100, y: 0, w: 50, h: BOTTOM }], []]],

  // The bottom strip draws its part of the line in its own band frame: from there the frame is a top-bar frame whose
  // near strip is the bottom bar.
  ["seen from the bottom: bottom bar is the near strip", () => { const s = F.seen_from(both, "bottom"); return plain([s.edge, s.has_bar, s.far_bar, s.near, s.far]); }, ["bottom", true, true, BOTTOM, H - TOP]],
  ["seen from the bottom: same hole on screen", () => plain(F.hole_rect(F.seen_from(both, "bottom"))), plain(F.hole_rect(both))],
  ["seen from the bottom: same lines on screen", () => { const s = F.seen_from(both, "bottom"); return JSON.stringify(point_set(s, F.frame_strokes(s, 1))) === JSON.stringify(point_set(both, F.frame_strokes(both, 1))); }, true],
  ["seen from the bottom and back is the layout", () => plain(F.seen_from(F.seen_from(both, "bottom"), "top")), plain(both)],
  ["seen from an edge with no bar is the layout", () => [F.seen_from(top_only, "bottom") === top_only, F.seen_from(none, "bottom") === none], [true, true]],
];

// Every corner profile and line width: each of the two lines starts and ends on a strip's own line d out from its
// edge, exactly where that strip's straight stretch ends, so the strips' rims pick them up without a notch.
for (const corner of ["round", "chamfer", "pixel", "square"]) {
  const lay = F.frame_layout(W, H, { top: TOP, bottom: BOTTOM }, Object.assign({}, kit, { corner, step: 2 }));
  cases.push([`both ${corner}: two hole pieces, clean`, () => { const p = F.hole_pieces(lay); return p.length === 2 && p.every(q => !self_intersects(q)); }, true]);
  for (const d of [1, 2.5]) {
    cases.push([`both ${corner}, d ${d}: each line ends on a strip's line at a straight end`, () => {
      const [lo, hi] = lay.straight, on_strip_line = p => Math.abs(p[1] - (lay.near - d)) < 1e-6 || Math.abs(p[1] - (lay.far + d)) < 1e-6;
      const at_end = p => Math.abs(p[0] - lo) < 1e-6 || Math.abs(p[0] - hi) < 1e-6;
      const s = F.frame_strokes(lay, d);
      return s.length === 2 && s.every(line => [line[0], line[line.length - 1]].every(p => on_strip_line(p) && at_end(p)));
    }, true]);
    cases.push([`both ${corner}, d ${d}: lines stay out of the hole`, () => F.frame_strokes(lay, d).every(line => line.every(p => p[0] <= lay.start || p[0] >= W - lay.end || p[1] <= lay.near || p[1] >= lay.far || (p[0] < lay.straight[0] || p[0] > lay.straight[1]) && (p[1] < lay.near + lay.radius || p[1] > lay.far - lay.radius))), true]);
  }
}

let failed = 0;
for (const [name, fn, want] of cases) {
  try {
    assert.deepStrictEqual(fn(), want);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}
if (failed) process.exit(1);
console.log("frame layout: " + cases.length + " checks passed");
