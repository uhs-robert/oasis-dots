// Runs IslandOutlines.js's fill-less helpers, BandGeometry.js and FrameGeometry.js under node, and checks every Style.island_shapes
// entry and Style.frame_corners entry has a kit and a label.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const root = path.join(__dirname, "../.config/quickshell");
const read = rel => fs.readFileSync(path.join(root, rel), "utf8");
const O = vm.createContext({});
vm.runInContext(read("ui/frames/IslandOutlines.js").replace(/^\.pragma.*$/gm, ""), O);
const run = code => vm.runInContext(code, O);
// BandGeometry `.import`s IslandOutlines as Outlines, which QML resolves and node cannot.
const B = vm.createContext({ Outlines: O });
vm.runInContext(read("ui/frames/BandGeometry.js").replace(/^\.(pragma|import).*$/gm, ""), B);
// A band's corners in band-frame order (start of the screen edge, its end, end of the open edge, its start), placed
// by band_affine inside band_rect; each must land on the screen corner of the band that matches.
const placed_corners = (edge, sw, sh, t) => {
  const r = B.band_rect(edge, sw, sh, t), len = B.band_frame(edge, sw, sh).length, m = B.band_affine(edge, t);
  return [[0, 0], [len, 0], [len, t], [0, t]].map(([u, v]) => [m[0] * u + m[2] * v + m[4] + r.x, m[1] * u + m[3] * v + m[5] + r.y]);
};
const plain = v => JSON.parse(JSON.stringify(v));
const C = vm.createContext({ Outlines: O });
vm.runInContext(read("ui/frames/Corners.js").replace(/^\.(pragma|import).*$/gm, ""), C);
const F = vm.createContext({ Outlines: O, Corners: C });
vm.runInContext(read("ui/frames/FrameGeometry.js").replace(/^\.(pragma|import).*$/gm, ""), F);
const kit = { corner: "round", radius: 12, thickness: 6, ornament: "" };
const top_frame = F.frame_layout(1920, 1080, "top", 30, kit);
const bottom_frame = F.frame_layout(1920, 1080, "bottom", 30, kit);
const bare_frame = F.frame_layout(1920, 1080, "", 30, kit);
const near_point = (p, q) => Math.hypot(p[0] - q[0], p[1] - q[1]) < 0.1;
// Shoelace area of a closed loop, unsigned.
const loop_area = loop => Math.abs(loop.reduce((s, p, k) => k === 0 ? 0 : s + loop[k - 1][0] * p[1] - p[0] * loop[k - 1][1], 0)) / 2;
// The exact area the frame window fills: below the strip (or the whole screen), minus the rounded hole.
const frame_area = lay => {
  const hole_w = lay.length - lay.start - lay.end, hole_h = lay.far - lay.near;
  return lay.length * (lay.depth - (lay.has_bar ? lay.near : 0)) - (hole_w * hole_h - (4 - Math.PI) * lay.radius * lay.radius);
};
const overlaps = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
const blocks_disjoint = blocks => blocks.every((a, i) => blocks.every((b, j) => i >= j || !overlaps(a, b)));
const blocks_area = blocks => blocks.reduce((s, b) => s + b.w * b.h, 0);

const cases = [
  ["stroke_only none", () => O.stroke_only("none"), true],
  ["stroke_only underline", () => O.stroke_only("underline"), true],
  ["stroke_only brackets", () => O.stroke_only("brackets"), true],
  ["stroke_only slant", () => O.stroke_only("slant"), false],
  ["stroke_only hex", () => O.stroke_only("hex"), false],
  ["has stays filled-only", () => ["none", "underline", "brackets"].some(s => O.has(s)), false],
  ["has rect", () => O.has("rect"), true],
  ["stroke_only rect", () => O.stroke_only("rect"), false],
  ["rect pad", () => O.cap_width("rect", 30), 9],
  ["rect ends are square", () => plain(O.end_profile("rect", 30, O.cap_width("rect", 30), false)), [[0, 0], [0, 30]]],
  ["rect trailing end is square", () => plain(O.end_profile("rect", 30, O.cap_width("rect", 30), true)), [[0, 0], [0, 30]]],
  ["none pad", () => O.cap_width("none", 30), 9],
  ["underline pad", () => O.cap_width("underline", 30), 9],
  ["brackets pad is arm plus gap", () => O.cap_width("brackets", 30), 12],
  ["brackets arm floor", () => O.bracket_arm(10), 4],
  ["underline path", () => plain(O.underline_path(100, 30, 2)), [[0, 29], [100, 29]]],
  ["bracket count", () => O.bracket_paths(100, 30, 9, 2).length, 4],
  ["bracket corners", () => plain(O.bracket_paths(100, 30, 9, 2).map(p => p[1])), [[1, 1], [99, 1], [99, 29], [1, 29]]],
  ["fill_path of an empty rim is empty", () => plain(O.fill_path([], 100, true, true)), []],
  ["small bar: brackets arm floor", () => O.bracket_arm(16), 5],
  ["small bar: vertical arms stay apart", () => { const p = O.bracket_paths(60, 16, O.bracket_arm(16), 1); return p[0][0][1] < p[3][2][1]; }, true],
  ["small bar: brackets stay inside", () => O.bracket_paths(60, 16, O.bracket_arm(16), 1).every(q => q.every(r => r[0] >= 0 && r[0] <= 60 && r[1] >= 0 && r[1] <= 16)), true],
  ["band rect top", () => plain(B.band_rect("top", 1920, 1080, 30)), { x: 0, y: 0, width: 1920, height: 30 }],
  ["band rect bottom", () => plain(B.band_rect("bottom", 1920, 1080, 30)), { x: 0, y: 1050, width: 1920, height: 30 }],
  ["band rect left", () => plain(B.band_rect("left", 1920, 1080, 30)), { x: 0, y: 0, width: 30, height: 1080 }],
  ["band rect right", () => plain(B.band_rect("right", 1920, 1080, 30)), { x: 1890, y: 0, width: 30, height: 1080 }],
  ["band frame lengths", () => plain(["top", "bottom", "left", "right"].map(e => B.band_frame(e, 1920, 1080).length)), [1920, 1920, 1080, 1080]],
  ["band top keeps the frame", () => placed_corners("top", 1920, 1080, 30), [[0, 0], [1920, 0], [1920, 30], [0, 30]]],
  ["band bottom: screen edge at the bottom", () => placed_corners("bottom", 1920, 1080, 30), [[0, 1080], [1920, 1080], [1920, 1050], [0, 1050]]],
  ["band left: runs down, screen edge at x 0", () => placed_corners("left", 1920, 1080, 30), [[0, 0], [0, 1080], [30, 1080], [30, 0]]],
  ["band right: runs down, screen edge at the right", () => placed_corners("right", 1920, 1080, 30), [[1920, 0], [1920, 1080], [1890, 1080], [1890, 0]]],
  ["band rim on the open edge", () => plain(B.band_rim(1920, 30, 0, 0)), [[0, 30], [1920, 30]]],
  ["band rim insets", () => plain(B.band_rim(1920, 30, 40, 12)), [[40, 30], [1908, 30]]],
  ["band rim stroke inside", () => plain(B.band_rim_stroke(1920, 30, 0, 0, 2)), [[0, 29], [1920, 29]]],
  ["band fill closed rect", () => plain(B.band_fill(1920, 30)), [[0, 30], [1920, 30], [1920, 0], [0, 0], [0, 30]]],
  ["band span inside the rim", () => plain(B.band_span(1920, 30, 2, 10)), [0, 1920]],
  ["band span at the screen edge", () => plain(B.band_span(1920, 30, 2, 0)), [0, 1920]],
  ["band span past the rim", () => plain(B.band_span(1920, 30, 2, 29)), [0, 0]],
  // The floating strip's plate: a band with shaped ends, set in from the screen edge by Bar.
  ["round pad", () => O.cap_width("round", 40), 12],
  ["round end starts on the screen edge and ends on the open edge", () => { const p = O.end_profile("round", 40, 12, false); return near_point(p[0], [12, 0]) && near_point(p[p.length - 1], [12, 40]); }, true],
  ["round end reaches the side between its corners", () => { const p = O.end_profile("round", 40, 12, false); return p.some(q => Math.abs(q[0]) < 1e-9 && Math.abs(q[1] - 12) < 1e-9); }, true],
  ["round is not an island shape", () => O.has("round") || O.stroke_only("round"), false],
  ["a left popup follows the strip's side inset", () => [F.side_popup_inset(18, "left", "left"), F.side_popup_inset(18, "left", "right")], [18, 0]],
  ["a right popup follows the strip's side inset", () => [F.side_popup_inset(18, "right", "right"), F.side_popup_inset(18, "right", "left")], [18, 0]],
  ["a center popup keeps no side inset", () => [F.side_popup_inset(18, "center", "left"), F.side_popup_inset(18, "center", "right")], [0, 0]],
  ["no strip side, no inset", () => F.side_popup_inset(0, "left", "left"), 0],
  ["inset_ring of a rectangle", () => plain(O.inset_ring([[0, 0], [0, 10], [20, 10], [20, 0]], 1)), [[1, 1], [1, 9], [19, 9], [19, 1]]],
  ["plate rim stroke closes", () => { const r = B.plate_rim_stroke("pixel", 200, 40, O.cap_width("pixel", 40), 2); return near_point(r[0], r[r.length - 1]); }, true],
  ["plate rim stroke stays inside the plate", () => ["round", "pixel"].every(e => B.plate_rim_stroke(e, 200, 40, O.cap_width(e, 40), 2).every(p => p[0] >= 1 - 1e-9 && p[0] <= 199 + 1e-9 && p[1] >= 1 - 1e-9 && p[1] <= 39 + 1e-9)), true],
  ["plate rim stroke runs along the top edge", () => { const r = B.plate_rim_stroke("round", 200, 40, 12, 2); return Math.abs(r[0][1] - 1) < 1e-9 && Math.abs(r[r.length - 2][1] - 1) < 1e-9; }, true],
  ["plate fill is closed", () => { const f = B.band_fill(200, 40, "pixel", O.cap_width("pixel", 40)); return near_point(f[0], f[f.length - 1]); }, true],
  ["plate fill stays inside the plate", () => ["round", "pixel"].every(e => B.band_fill(200, 40, e, O.cap_width(e, 40)).every(p => p[0] >= 0 && p[0] <= 200 && p[1] >= 0 && p[1] <= 40)), true],
  ["plate fill area is the rectangle less its four corners", () => loop_area(B.band_fill(200, 40, "pixel", O.cap_width("pixel", 40))) < 200 * 40, true],
  ["plate span narrows at the corners and is full between them", () => { const c = O.cap_width("pixel", 40), top = B.band_span(200, 40, 2, 3, "pixel", c), mid = B.band_span(200, 40, 2, 20, "pixel", c); return top[0] > mid[0] && top[1] < mid[1] && near_point(mid, [2, 198]); }, true],
  ["plate span is empty on the top rim and past the open edge", () => plain([B.band_span(200, 40, 2, 1, "round", 12), B.band_span(200, 40, 2, 39, "round", 12)]), [[0, 0], [0, 0]]],
  ["band_fill without ends stays the plain band", () => plain(B.band_fill(1920, 30, "", 0)), [[0, 30], [1920, 30], [1920, 0], [0, 0], [0, 30]]],
  ["full is no outline or stroke", () => O.has("full") || O.stroke_only("full"), false],
  ["bracket arms stay inside", () => O.bracket_paths(100, 30, 9, 2).every(p => p.every(q => q[0] >= 0 && q[0] <= 100 && q[1] >= 0 && q[1] <= 30)), true],
  ["frame zones top bar", () => plain(top_frame.zones), { top: 30, right: 6, bottom: 6, left: 6 }],
  ["frame zones bottom bar", () => plain(bottom_frame.zones), { top: 6, right: 6, bottom: 30, left: 6 }],
  ["frame zones no bar", () => plain(bare_frame.zones), { top: 6, right: 6, bottom: 6, left: 6 }],
  ["frame hole top bar", () => [top_frame.near, top_frame.far, top_frame.start, top_frame.end], [30, 1074, 6, 6]],
  ["frame hole no bar starts past a band", () => bare_frame.near, 6],
  ["frame straight stretch", () => plain(top_frame.straight), [18, 1902]],
  ["frame radius clamps to half the hole", () => F.frame_layout(100, 1080, "top", 30, Object.assign({}, kit, { radius: 80 })).radius, 44],
  ["frame radius never negative", () => F.frame_layout(10, 20, "top", 30, kit).radius, 0],
  ["hole path starts at the straight stretch's far end", () => near_point(F.hole_path(top_frame)[0], [1902, 30]), true],
  ["hole path ends at the straight stretch's near end", () => near_point(F.hole_path(top_frame).slice(-1)[0], [18, 30]), true],
  ["hole path reaches the far corners", () => F.hole_path(top_frame).some(p => near_point(p, [6, 1062])) && F.hole_path(top_frame).some(p => near_point(p, [1914, 1062])), true],
  ["hole loop closes", () => near_point(F.hole_loop(top_frame)[0], F.hole_loop(top_frame).slice(-1)[0]), true],
  ["frame region with a bar is one closed loop", () => { const r = F.frame_region(top_frame); return r.length === 1 && near_point(r[0][0], r[0].slice(-1)[0]); }, true],
  ["frame region with no bar is screen and hole", () => plain(F.frame_region(bare_frame).map(l => near_point(l[0], l.slice(-1)[0]))), [true, true]],
  ["frame region area with a bar", () => Math.abs(loop_area(F.frame_region(top_frame)[0]) - frame_area(top_frame)) < 0.01 * frame_area(top_frame), true],
  ["frame region reaches exactly 1 px under the strip, no further", () => { const ys = F.frame_region(top_frame)[0].map(p => p[1]); return Math.min(...ys) === top_frame.near - 1; }, true],
  ["frame region's overlap is only over the side bands and corners", () => F.frame_region(top_frame)[0].filter(p => p[1] < top_frame.near).every(p => p[0] <= top_frame.straight[0] + 1e-9 || p[0] >= top_frame.straight[1] - 1e-9), true],
  // The strip's rim and the frame's stroke meet at the same depth, the stroke starting exactly where the rim stops, so
  // the two neither leave a notch nor draw over each other.
  ["frame stroke picks up the strip rim", () => {
    const w = 2, rim = B.band_rim_stroke(1920, 30, top_frame.straight[0], 1920 - top_frame.straight[1], w), stroke = F.frame_stroke(top_frame, w / 2);
    const a = stroke[0], z = stroke.slice(-1)[0], e = 1e-6;
    return Math.abs(a[1] - rim[1][1]) < e && Math.abs(z[1] - rim[0][1]) < e
      && Math.abs(a[0] - rim[1][0]) < e && Math.abs(z[0] - rim[0][0]) < e;
  }, true],
  ["frame stroke with no bar closes round the hole", () => { const s = F.frame_stroke(bare_frame, 1); return near_point(s[0], s.slice(-1)[0]) && Math.abs(s[0][1] - 5) < 0.1; }, true],
  ["frame stroke stays out of the hole", () => F.frame_stroke(top_frame, 1).every(p => p[0] <= 6 || p[0] >= 1914 || p[1] <= 30 || p[1] >= 1074 || (p[0] < 18 || p[0] > 1902) && (p[1] < 42 || p[1] > 1062)), true],
  ["frame blocks disjoint (bar)", () => blocks_disjoint(F.frame_blocks(top_frame)), true],
  ["frame blocks disjoint (no bar)", () => blocks_disjoint(F.frame_blocks(bare_frame)), true],
  ["frame blocks area (bar)", () => Math.abs(blocks_area(F.frame_blocks(top_frame)) - frame_area(top_frame)) < 0.01 * frame_area(top_frame), true],
  ["frame blocks area (no bar)", () => Math.abs(blocks_area(F.frame_blocks(bare_frame)) - frame_area(bare_frame)) < 0.01 * frame_area(bare_frame), true],
  ["translucent islands: region and blocks start at near, no overlap", () => { const l = F.frame_layout(1920, 1080, "top", 30, Object.assign({}, kit, { fill_overlap: 0 })); return Math.min(...F.frame_region(l)[0].map(p => p[1])) === l.near && F.frame_blocks(l).every(b => b.y >= l.near); }, true],
  ["frame blocks reach 1 px under the strip, no further", () => F.frame_blocks(top_frame).every(b => b.y >= top_frame.near - 1) && F.frame_blocks(top_frame).some(b => b.y === top_frame.near - 1), true],
  // The frame window may stack above the strip; if its stroke clip started below its fill's top, the fill's overlap row
  // would hide the strip's half of the corner's rim and inset line.
  ["frame stroke clip starts a whole px above the fill's top", () => {
    const fill_top = Math.min(...F.frame_region(top_frame)[0].map(p => p[1]), ...F.frame_blocks(top_frame).map(b => b.y));
    return F.stroke_clip_top(top_frame) <= fill_top - 1;
  }, true],
  ["translucent islands: frame stroke clip stays at near", () => F.stroke_clip_top(F.frame_layout(1920, 1080, "top", 30, Object.assign({}, kit, { fill_overlap: 0 }))), 30],
  ["frame to_screen top is the band frame", () => plain(F.to_screen(top_frame)), plain(B.band_affine("top", 1080))],
  ["frame to_screen bottom is the band frame", () => plain(F.to_screen(bottom_frame)), plain(B.band_affine("bottom", 1080))],
  // A side bar's islands draw in the same top-bar frame, turned onto the edge by band_affine (Island.qml's deco_frame).
  ...plain(run("names")).concat(["slant"]).flatMap(shape => ["left", "right"].flatMap(edge => {
    const depth = 40, length = 300, cap = O.cap_width(shape, depth);
    const fill = O.fill_path(O.rim_path(shape, length, depth, cap, true, true), length, true, true);
    const placed = fill.map(([u, v]) => { const m = B.band_affine(edge, depth); return [m[0] * u + m[2] * v + m[4], m[1] * u + m[3] * v + m[5]]; });
    const on_screen_edge = edge === "left" ? 0 : depth;
    return [
      ["a " + edge + " " + shape + " island is as big as the horizontal one", () => Math.abs(loop_area(placed) - loop_area(fill)) < 1e-6, true],
      ["a " + edge + " " + shape + " island is a column depth wide and length tall", () => placed.every(p => p[0] >= -1e-9 && p[0] <= depth + 1e-9 && p[1] >= -1e-9 && p[1] <= length + 1e-9), true],
      ["a " + edge + " " + shape + " island rests on the screen edge", () => placed.some(p => Math.abs(p[0] - on_screen_edge) < 1e-9), true],
    ];
  })),
  ["a left island's open edge faces right", () => { const m = B.band_affine("left", 40); return [m[0] * 0 + m[2] * 40 + m[4], m[1] * 7 + m[3] * 0 + m[5]]; }, [40, 7]],
  ["a right island's open edge faces left", () => { const m = B.band_affine("right", 40); return [m[2] * 40 + m[4], m[1] * 7 + m[5]]; }, [0, 7]],
];

let failed = 0;
for (const [name, fn, want] of cases) {
  try {
    assert.deepStrictEqual(fn(), want);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}

// Style.qml is QML, so read its lists as text.
const style = read("theme/Style.qml");
const shapes = JSON.parse(style.match(/island_shapes: (\[[^\]]*\])/)[1]);
const kits = style.slice(style.indexOf("island_shape_kits: ({"), style.indexOf("renamed_island_shapes"));
const labels = style.slice(style.indexOf("borrow_names")).match(/bar_island_shape: \{([^}]*)\}/)[1];
for (const s of shapes) {
  if (!new RegExp("\\b" + s + ": \\{").test(kits)) { failed++; console.log("FAIL no kit for " + s); }
  if (!new RegExp("\\b" + s + ": \"").test(labels)) { failed++; console.log("FAIL no label for " + s); }
}
// Island draws a plate from the kit's flag and the settings row hides from it, while IslandOutlines sizes the pad
// from stroke_names: the two lists must agree for every shape.
for (const s of shapes) {
  const kit_says_fill_less = new RegExp("\\b" + s + ": \\{ filled: false").test(kits);
  if (kit_says_fill_less !== O.stroke_only(s)) { failed++; console.log("FAIL kit flag and stroke_only disagree for " + s); }
}

// Every island shape has a vertical form: an outline or stroke shape is drawn in the top-bar frame and turned onto the
// side by Island's deco_frame, and the hand-drawn ones (listed here, so a new shape must be added knowingly) place their
// layers through it too. Island may not keep a fallback shape or a layer mirrored only for a bottom bar.
const hand_drawn = ["slant", "octagon", "watch", "window", "capsule", "visor", "full", "strip"];
const island_src = read("features/bar/Island.qml");
for (const s of shapes) {
  if (!O.has(s) && !O.stroke_only(s) && hand_drawn.indexOf(s) < 0) { failed++; console.log("FAIL island shape " + s + " has no vertical form"); }
}
if (/vertical_shape|transform: mirror/.test(island_src)) { failed++; console.log("FAIL Island.qml keeps a horizontal-only layer or a shape fallback"); }

// A kit's fixed sizes (`set`) must be in plain_island_shape, or leaving the shape would keep them.
const plain_keys = [...style.match(/plain_island_shape: \(\{([^}]*)\}\)/)[1].matchAll(/(\w+):/g)].map(m => m[1]);
for (const m of kits.matchAll(/set: \{([^}]*)\}/g)) {
  for (const k of [...m[1].matchAll(/(\w+):/g)].map(x => x[1])) {
    if (plain_keys.indexOf(k) < 0) { failed++; console.log("FAIL kit size " + k + " is not reset by plain_island_shape"); }
  }
}

// Style.strip_shape turns on for any kit with `strip: true`, so each must be a shape the settings row offers.
const strip_kits = [...kits.matchAll(/\b(\w+): \{[^}]*\bstrip: true/g)].map(m => m[1]);
if (strip_kits.length === 0) { failed++; console.log("FAIL no strip kit"); }
for (const s of strip_kits) {
  if (shapes.indexOf(s) < 0) { failed++; console.log("FAIL strip kit " + s + " is not in island_shapes"); }
}

// Every corner profile has a settings label; they share one kit frame_layout can measure.

let frame_checks = 0;
const expect = (ok, message) => {
  frame_checks++;
  if (!ok) { failed++; console.log("FAIL " + message); }
};
const frame_corners = JSON.parse(style.match(/frame_corners: (\[[^\]]*\])/)[1]);
const frame_kit = vm.runInNewContext(style.match(/plain_frame_kit: (\(\{[^}]*\}\))/)[1]);
const frame_labels = style.slice(style.indexOf("borrow_names")).match(/corner_style: \{([^}]*)\}/)[1];
expect(["radius", "thickness"].every(k => typeof frame_kit[k] === "number"), "no usable plain_frame_kit");
expect(!/screen_frames/.test(style), "Style still has the old screen_frames list");
for (const f of frame_corners) {
  expect(new RegExp("\\b" + f + ": \"").test(frame_labels), "no label for corner style " + JSON.stringify(f));
}
// Lualine takes the frame like any style: frame_kit_for evaluated from the QML source.
const FT = vm.createContext({});
vm.runInContext(read("theme/FrameTokens.js").replace(/^\.pragma.*$/gm, ""), FT);
const kit_for = vm.runInNewContext("(function(root) { return function" + style.match(/function frame_kit_for(\([^)]*\) \{[^}]*\})/)[1] + "; })", { FrameTokens: FT })({ frame_corners, plain_frame_kit: frame_kit });
expect(kit_for({ bar_lualine: true, screen_frame: true }) !== null, "a lualine style with the frame on gets no frame kit");
expect(kit_for({ bar_lualine: true, screen_frame: false }) === null, "a lualine style with the frame off gets a kit");
expect(kit_for({ screen_frame: true, screen_frame_offered: false }) === null, "screen_frame_offered false does not opt out");
expect(kit_for({ screen_frame: false, corner_style: "chamfer" }) === null, "a corner style alone gives a frame kit");
// Each style's corner hint is a profile.
for (const dir of fs.readdirSync(path.join(root, "styles"), { withFileTypes: true }).filter(d => d.isDirectory())) {
  const tokens_path = path.join(root, "styles", dir.name, "tokens.js");
  if (!fs.existsSync(tokens_path)) continue;
  for (const m of fs.readFileSync(tokens_path, "utf8").matchAll(/screen_frame_corners: "(\w+)"/g)) {
    expect(frame_corners.indexOf(m[1]) >= 0, dir.name + " hints the unknown corner " + m[1]);
  }
}

// Style.load_options turns a v2 "plain" frame into a corner before checking the row's choices, then (version 4) splits a
// saved corner into frame On plus a Corner style, and moves the per-style flush to the global setting.
const M = vm.createContext({});
vm.runInContext(read("theme/OptionMigrations.js").replace(/^\.pragma.*$/gm, ""), M);
const plain_to = (saved, hint) => M.screen_frame_from_plain(saved, hint, frame_corners);
for (const [name, got, want] of [
  ["saved corner wins over the hint", plain_to("chamfer", "pixel"), "chamfer"],
  ["no saved corner takes the style's hint", plain_to(undefined, "pixel"), "pixel"],
  ["neither falls back to round", plain_to(undefined, undefined), "round"],
  ["an unknown saved corner takes the hint", plain_to("octagon", "square"), "square"],
  ["an unknown saved corner and hint fall back to round", plain_to("octagon", "blob"), "round"],
  ["round saved stays round over a hint", plain_to("round", "pixel"), "round"],
]) {
  expect(got === want, "migration: " + name + ": got " + got + ", want " + want);
}
const load = style.slice(style.indexOf("function load_options"));
expect(/options_version: 4/.test(style), "options_version is not 4");
expect(load.indexOf("screen_frame_from_plain") > 0 && load.indexOf("screen_frame_from_plain") < load.indexOf("valid_option"), "the frame migration does not run before valid_option");
expect(load.indexOf("frame_to_bool") > load.indexOf("screen_frame_from_plain") && load.indexOf("frame_to_bool") < load.indexOf("valid_option"), "the frame split does not run after plain and before valid_option");

// The settings rows load_options checks values against: the real settings_for source, so the bool Screen frame (default
// off) and the Corner style row are the ones the app builds. Stubbed styles carry the natural corners of the real ones.
const natural = { goldeneye: "round", ps2: "round", ff7: "round", gameboy: "pixel", tie: "chamfer", reticle: "square", terminal: "round", modern: "round" };
const style_tokens = name => ({ screen_frame_corners: natural[name], screen_frame_only: name === "terminal" ? "square" : "" });
const settings_src = style.slice(style.indexOf("    function settings_for"), style.indexOf("    // The value of option `key`"));
const option_default_src = style.match(/function option_default(\(def\) \{[^}]*\})/)[1];
const make_root = () => {
  const r = { theme_values: {}, frame_corners, renamed_island_shapes: { octagon: "watch" }, flush_single: true, saves: 0, options_saves: 0,
    styles: Object.fromEntries(Object.keys(natural).map(n => [n, Object.assign({ bar_island_shape: "slant", bar_lualine: false }, style_tokens(n))])),
    state_read: true, flush_unsaved: false, island_shape_filled: () => true, island_shapes: ["slant", "octagon", "watch", "full"], picker_skins: [], overview_skins: [], osd_layouts: [], weather_layouts: [], keeptabs_layouts: [], done_anims: [], wait_anims: [], toast_enters: [], workspace_arts: [], bar_icon_sets: [], bar_meeting_markers: [], font_choices: [],
    borrow_labels: () => ({}), frame_kit_for: t => (FT.frame_on(t) ? frame_kit : null), plain_frame_kit: frame_kit };
  r.save = () => { r.saves++; };
  r.save_options = () => { r.options_saves++; };
  const fns = vm.runInNewContext("(function(root, FrameTokens, Qt) { return { settings_for: function" + settings_src.match(/function settings_for(\([^]*)/)[1].replace(/\n    \}\n[^]*$/, "\n    }") + ", option_default: function" + option_default_src + ", valid_option: function" + style.match(/function valid_option(\([^]*?\n    \})/)[1] + " }; })", {})(r, FT, { color: () => ({ a: 1 }) });
  Object.assign(r, fns);
  r.carry_flush_off = () => { r.flush_single = false; r.save(); };
  return r;
};
// Runs the real load_options on saved files.
const run_load = data => {
  const r = make_root();
  const body = load.slice(0, load.indexOf("\n    }\n") + 6).replace(/^function load_options/, "(function");
  vm.runInNewContext(body + ")", { root: r, Migrations: M })(data);
  return r;
};
const load_saved = data => plain(run_load(data).theme_values);
const saved_of = (data, name) => load_saved(data)[name] || {};
// What the shell then draws: the saved options laid over the style, as Style.active does.
const effective = (data, name) => {
  const r = run_load(data);
  const tokens = Object.assign({}, r.styles[name], r.theme_values[name] || {});
  return { frame: FT.frame_on(tokens), corner: FT.corner_of(tokens, frame_corners) };
};
for (const [name, got, want] of [
  ["a version 2 file keeps a chosen octagon", saved_of({ version: 2, modern: { bar_island_shape: "octagon" } }, "modern").bar_island_shape, "octagon"],
  ["a version 1 file renames octagon to watch", saved_of({ version: 1, modern: { bar_island_shape: "octagon" } }, "modern").bar_island_shape, "watch"],
  ["a file without a version renames octagon to watch", saved_of({ modern: { bar_island_shape: "octagon" } }, "modern").bar_island_shape, "watch"],
  ["a version 2 file turns plain into a corner", effective({ version: 2, modern: { screen_frame: "plain", screen_frame_corners: "chamfer" } }, "modern").corner, "chamfer"],
  ["a version 2 plain frame is on", effective({ version: 2, modern: { screen_frame: "plain" } }, "modern").frame, true],
  ["a version 3 file leaves plain alone", effective({ version: 3, modern: { screen_frame: "plain" } }, "modern").frame, false],
]) {
  expect(got === want, "load_options: " + name + ": got " + got + ", want " + want);
}

// The owner's saved v3 file (theme_options.json) migrates with every corner kept and every frame on, and the file is
// rewritten at version 4 with nothing of the old keys left.
const owner_v3 = () => ({ version: 3, goldeneye: { screen_frame: "chamfer" }, ps2: { screen_frame: "round" }, ff7: { screen_frame: "round" }, gameboy: { screen_frame: "pixel" }, tie: { screen_frame: "chamfer" } });
for (const [name, corner] of [["goldeneye", "chamfer"], ["ps2", "round"], ["ff7", "round"], ["gameboy", "pixel"], ["tie", "chamfer"]]) {
  const got = effective(owner_v3(), name);
  expect(got.frame === true, "owner v3 " + name + ": frame is off after migrating");
  expect(got.corner === corner, "owner v3 " + name + ": corner " + got.corner + ", want " + corner);
}
expect(run_load(owner_v3()).options_saves === 1, "owner v3: migrated file not written back at version 4");
expect(JSON.stringify(Object.keys(saved_of(owner_v3(), "goldeneye"))) === JSON.stringify(["screen_frame", "corner_style"]), "goldeneye keeps frame on and a corner that is not its natural one");
expect(!("corner_style" in saved_of(owner_v3(), "gameboy")) && effective(owner_v3(), "gameboy").corner === "pixel", "a corner equal to the natural one is the default, not stored, and still pixel");
expect(!Object.values(load_saved(owner_v3())).some(v => typeof v.screen_frame === "string" || "screen_frame_flush" in v), "old frame or flush keys survive the migration");
expect(run_load(owner_v3()).flush_single === true, "owner v3: no style saved flush off, so the global stays on");

// A corner is never lost, whatever the style: every corner on every style, frame on, and frame off ("" saved is the default).
for (const n of Object.keys(natural)) {
  for (const c of frame_corners) {
    if (n === "terminal" && c !== "square") continue;
    const got = effective({ version: 3, [n]: { screen_frame: c } }, n);
    expect(got.frame === true && got.corner === c, "migration: " + n + " saved " + c + " became " + JSON.stringify(got));
  }
  const off = effective({ version: 3, [n]: { screen_frame_flush: true } }, n);
  expect(off.frame === false && off.corner === (n === "terminal" ? "square" : natural[n]), "migration: " + n + " with no frame turned the frame on or moved its corner");
}
// A style's frame never flips: no saved frame stays off, a saved one stays on, in a mixed file.
const mixed = effective({ version: 3, modern: { bar_island_shape: "chamfer" }, ps2: { screen_frame: "round" } }, "modern");
expect(mixed.frame === false && mixed.corner === "round", "a style without a saved frame turned it on or lost its corner");
expect(effective({ version: 3, ps2: { screen_frame: "round" } }, "ps2").frame === true, "a saved frame went off");
expect(effective({ version: 3, ps2: { screen_frame: "" } }, "ps2").frame === false, "an empty saved frame turned on");
expect(effective({ version: 3, ps2: { screen_frame: "blob" } }, "ps2").frame === false, "an unknown saved frame turned on");
expect(effective({ version: 3, terminal: { screen_frame: "square" } }, "terminal").frame === true, "terminal's saved square frame went off");

// The per-style flush becomes one global: off if any style had it off, on otherwise, and a version 4 file is not read for it.
expect(run_load({ version: 3, ps2: { screen_frame: "round", screen_frame_flush: false }, ff7: { screen_frame_flush: true } }).flush_single === false, "one style's flush off did not turn the global off");
expect(run_load({ version: 3, ff7: { screen_frame_flush: false } }).flush_single === false, "a flush off on a frame-less style was dropped");
expect(run_load({ version: 3, ps2: { screen_frame_flush: true }, ff7: { screen_frame: "round" } }).flush_single === true, "no flush off turned the global off");
expect(run_load({ version: 3, ps2: { screen_frame_flush: false } }).saves === 1, "turning the global flush off did not save style.json");
expect(run_load({ version: 3, ps2: { screen_frame: "round" } }).saves === 0, "an unchanged global flush rewrote style.json");
expect(run_load({ version: 4, ps2: { screen_frame: true, corner_style: "pixel" }, ff7: { screen_frame_flush: false } }).flush_single === true, "a version 4 file was read for the old flush key");
expect(!("screen_frame_flush" in saved_of({ version: 3, ps2: { screen_frame: "round", screen_frame_flush: false } }, "ps2")), "the per-style flush key survived");

// Idempotent: the migrated file, loaded again, gives the same values and does not migrate or save again.
const once = run_load(owner_v3());
const again = run_load(Object.assign({ version: 4 }, plain(once.theme_values)));
expect(JSON.stringify(plain(again.theme_values)) === JSON.stringify(plain(once.theme_values)), "loading the migrated file changed it");
expect(again.options_saves === 0 && again.saves === 0, "the migrated file saved again on load");
expect(effective(Object.assign({ version: 4 }, plain(once.theme_values)), "tie").corner === "chamfer", "tie lost its corner on the second load");
// A new version 4 file with the frame on and a corner loads as saved.
const v4 = effective({ version: 4, ps2: { screen_frame: true, corner_style: "pixel" } }, "ps2");
expect(v4.frame === true && v4.corner === "pixel", "a version 4 file did not load as saved");
// The unknown "version" key and a style no longer shipped are skipped without error.
expect(JSON.stringify(load_saved({ version: 3, gone: { screen_frame: "round" } })) === "{}", "a removed style kept its values");

// Corner resolution, frame on or off: the choice, else the natural corner, and terminal is always square.
for (const [name, tokens, want] of [
  ["a choice wins", { corner_style: "pixel", screen_frame_corners: "chamfer" }, "pixel"],
  ["no choice takes the natural corner", { corner_style: "", screen_frame_corners: "chamfer" }, "chamfer"],
  ["no hint is round", {}, "round"],
  ["an unknown choice is the natural corner", { corner_style: "blob", screen_frame_corners: "pixel" }, "pixel"],
  ["terminal is square whatever is saved", { corner_style: "round", screen_frame_only: "square" }, "square"],
  ["the frame does not change the corner", { screen_frame: true, corner_style: "chamfer" }, "chamfer"],
]) {
  const got = FT.corner_of(tokens, frame_corners);
  expect(got === want, "corner_of: " + name + ": got " + got + ", want " + want);
}
// With the frame off the corner reaches Hyprland and the apps only once picked; with it on, always.
expect(FT.corner_applies(true, false) === true && FT.corner_applies(true, true) === true, "the frame on does not send the corner");
expect(FT.corner_applies(false, false) === false, "an untouched style with no frame sends its corner");
expect(FT.corner_applies(false, true) === true, "a picked Corner style with no frame is not sent");
for (const f of ["features/bar/FrameExport.qml"]) {
  expect(/Style\.corner_sent/.test(read(f)), f + " does not gate the corner on Style.corner_sent");
}
expect(/corner_sent: FrameTokens\.corner_applies\(root\.screen_frame_on, root\.corner_style_chosen\)/.test(style), "Style.corner_sent is not corner_applies of the frame and the pick");
// ScreenFrameSync's mode: the frame only where a screen draws it; a frame on with only side bars still sends the corner.
for (const [name, args, want] of [
  ["frame drawn", [true, true, true], "frame"],
  ["frame on, only side bars, corner sent", [true, false, true], "corner"],
  ["frame off, corner picked", [false, false, true], "corner"],
  ["frame off, untouched", [false, false, false], "clear"],
]) {
  expect(FT.sync_mode(...args) === want, "sync_mode: " + name + ": got " + FT.sync_mode(...args) + ", want " + want);
}
expect(/Style\.sync_mode\(/.test(read("features/bar/ScreenFrameSync.qml")), "ScreenFrameSync does not use Style.sync_mode");
// Every token set `active` returns is squared, the forced full bar's too.
const active_src = style.slice(style.indexOf("readonly property var active:"), style.indexOf("function squared"));
expect(!/return root\.with_options\(/.test(active_src) && (active_src.match(/root\.squared\(/g) || []).length === 2, "active returns a token set that skipped squared");
const squared = vm.runInNewContext("(function(root, FrameTokens) { return function" + style.match(/function squared(\([^)]*\) \{[^]*?\n    \})/)[1] + "; })", {})({ frame_corners }, FT);
expect(squared({ corner_style: "square", frame_radius: 10 }).frame_radius === 0 && squared({ corner_style: "round", frame_radius: 10 }).frame_radius === 10 && squared({ screen_frame_only: "square", frame_radius: 6 }).frame_radius === 0, "squared");
expect(FT.natural_corner({ screen_frame_corners: "pixel" }, frame_corners) === "pixel" && FT.natural_corner({}, frame_corners) === "round", "natural_corner");
// The pixel step reaches the profile with the frame off (gameboy 2): Style.corner_profile reads the style's own.
expect(/corner_profile: \(\{ corner: root\.corner_style, radius: root\.plain_frame_kit\.radius, step: root\.bar\.screen_frame_step \}\)/.test(style), "corner_profile does not carry the style's pixel step");
expect(/screen_frame_profile: root\.screen_frame_on \? root\.corner_profile : null/.test(style), "screen_frame_profile is not corner_profile with the frame on, null off");
expect(/gameboy[^]*screen_frame_step: 2/.test(read("styles/gameboy/tokens.js")), "gameboy lost its pixel step");
// The Corner style row exists on every style that has a settings list, with the frame on or off, and its default is the natural corner.
for (const n of Object.keys(natural)) {
  const rows = make_root().settings_for(n, true);
  const corner_row = rows.find(r => r.key === "corner_style");
  expect(corner_row && corner_row.default === (n === "terminal" ? "square" : natural[n]), "Corner style row of " + n + " is missing or has the wrong default");
  const frame_row = rows.find(r => r.key === "screen_frame");
  expect(frame_row && frame_row.type === "bool" && frame_row.default === false, "Screen frame row of " + n + " is not an Off-by-default bool");
  expect(!rows.some(r => r.key === "screen_frame_flush"), "the per-style flush row of " + n + " is still there");
}
expect(JSON.stringify(make_root().settings_for("terminal", true).find(r => r.key === "corner_style").choices) === JSON.stringify(["square"]), "terminal's Corner style row offers more than square");
{
  const r = make_root();
  r.styles.modern.screen_frame_offered = false;
  const rows = r.settings_for("modern", true);
  expect(!rows.some(x => x.key === "screen_frame") && rows.some(x => x.key === "corner_style"), "a style without a frame option lost its Corner style row or kept the frame row");
}
// A bool row that defaults off is "off" until set, and setting it on is stored.
{
  const r = make_root();
  expect(r.option_default({ type: "bool", default: false }) === false && r.option_default({ type: "bool", default: true }) === true && r.option_default({ type: "choice", default: "x" }) === "x", "option_default");
}

// The floating strip's end profile is the kit `ends` of the style's own island shape (Style.strip_ends), so each
// style gets the corners its islands have.
const kit_ends = shape => (kits.match(new RegExp("\\b" + shape + ": \\{[^}]*\\bends: \"(\\w+)\"")) || [])[1];
const own_shape = style_name => (read("styles/" + style_name + "/tokens.js").match(/bar_island_shape: "(\w+)"/) || [])[1] || "slant";
let end_checks = 0;
for (const [style_name, want] of [["gameboy", "pixel"], ["snes", "pixel"], ["nes", "pixel"], ["goldeneye", "chamfer"], ["metroid", "chamfer"], ["modern", "round"]]) {
  end_checks++;
  expect(kit_ends(own_shape(style_name)) === want, "strip ends of " + style_name + ": got " + kit_ends(own_shape(style_name)) + ", want " + want);
}
for (const shape of shapes) {
  end_checks++;
  const ends = kit_ends(shape);
  expect(shape === "none" || shape === "underline" || shape === "brackets" || shape === "full" || shape === "strip" || ends !== undefined, "island shape " + shape + " has no strip ends");
  expect(ends === undefined || ends === "round" || ends === "chamfer" || O.has(ends), "island shape " + shape + " names ends " + ends + ", which IslandOutlines cannot draw");
}
const chamfer = O.end_profile("chamfer", 40, 12, false);
expect(JSON.stringify(plain(chamfer)) === JSON.stringify([[12, 0], [0, 12], [0, 28], [12, 40]]), "chamfer end profile: " + JSON.stringify(chamfer));
expect(O.cap_width("chamfer", 40) === 12 && !O.has("chamfer"), "chamfer is a 0.3 h pad and not an island shape");
end_checks += 2;

// The Terminal screen frame: its tmux pane colours replace the bar border, it is fixed to Square, and its line is 1 px.
const TT = vm.createContext({});
vm.runInContext(read("styles/terminal/tokens.js").replace(/^\.pragma.*$/gm, ""), TT);
const terminal = plain(TT.overrides({ theme_primary: "PRIMARY", fg_muted: "MUTED" }, {}));
const NT = vm.createContext({ Qt: { tint: a => a, alpha: c => c, rgba: () => "RGBA", darker: c => c, lighter: c => c } });
vm.runInContext(read("styles/neovim/tokens.js").replace(/^\.pragma.*$/gm, ""), NT);
const neovim = Object.assign({ bar_island_shape: "slant" }, plain(NT.overrides(new Proxy({}, { get: () => "COLOR" }), {})));
const rim = (panes, focused) => FT.rim_color(panes, focused, "BAR", "BAR_DIM");
let pane_checks = 0;
for (const [name, got, want] of [
  ["terminal's panes carry the palette colours", JSON.stringify(terminal.screen_frame_panes), JSON.stringify({ active: "PRIMARY", inactive: "MUTED" })],
  ["panes colour the focused rim", rim(terminal.screen_frame_panes, true), "PRIMARY"],
  ["panes colour the other monitors' rim", rim(terminal.screen_frame_panes, false), "MUTED"],
  ["no panes keeps the bar border when focused", rim(null, true), "BAR"],
  ["no panes keeps the dimmed bar border elsewhere", rim(undefined, false), "BAR_DIM"],
  ["panes draw 1 px whatever the bar border is", FT.rim_width(terminal.screen_frame_panes, 3), 1],
  ["no panes draws the bar border width", FT.rim_width(null, 3), 3],
  ["terminal is fixed to square", terminal.screen_frame_only, "square"],
  ["terminal's corner is square", FT.corner_of(terminal, frame_corners), "square"],
  ["terminal still offers the frame", FT.offered(terminal), true],
  ["neovim (lualine) is offered the frame", FT.offered(neovim), true],
  ["a style with screen_frame_offered false is not offered it", FT.offered({ screen_frame_offered: false }), false],
  ["a frame forces a slant bar to the full bar", FT.forces_full_bar({ bar_island_shape: "slant" }), true],
  ["a frame leaves a full bar alone", FT.forces_full_bar({ bar_island_shape: "full" }), false],
  ["a frame leaves lualine's sections alone", FT.forces_full_bar(neovim), false],
  ["the row offers Square only for terminal", JSON.stringify(FT.row_choices(terminal.screen_frame_only, frame_corners.concat())), JSON.stringify(["square"])],
  ["the row offers every corner otherwise", JSON.stringify(FT.row_choices("", frame_corners)), JSON.stringify(frame_corners)],
  ["the row offers every corner for an unset only", JSON.stringify(FT.row_choices(undefined, frame_corners)), JSON.stringify(frame_corners)],
]) {
  pane_checks++;
  expect(got === want, "terminal frame: " + name + ": got " + got + ", want " + want);
}
expect(/FrameTokens\.rim_width/.test(style) && /FrameTokens\.rim_color/.test(style) && /FrameTokens\.row_choices/.test(style) && /FrameTokens\.offered/.test(style) && /FrameTokens\.forces_full_bar/.test(style), "Style.qml does not use FrameTokens");
expect(/Style\.screen_frame_rim_width/.test(read("features/bar/ScreenFrame.qml")) && /Style\.screen_frame_rim_width/.test(read("features/bar/ScreenFrameSync.qml")), "the drawn rim and Hyprland's border do not share screen_frame_rim_width");
pane_checks += 2;

// A popup's cut-corner outline leaves the corners against the bar square, on every bar position. The square set is
// the one Popup.qml derives (PanelCuts.bar_square, fed the corners DrawerGeometry.beside_corners rounds), and each
// outline and its decorations (scanline trim, struts, visor teeth) are drawn from it.
const P = vm.createContext({});
vm.runInContext(read("ui/frames/PanelCuts.js").replace(/^\.pragma.*$/gm, ""), P);
const D = vm.createContext({ Outlines: O, Band: B, Corners: C });
vm.runInContext(read("ui/frames/DrawerGeometry.js").replace(/^\.(pragma|import).*$/gm, ""), D);
const popup = read("features/popups/frames/Popup.qml");
const sides = { top_left: [0, 0], top_right: [1, 0], bottom_right: [1, 1], bottom_left: [0, 1] };
const both = (a, b) => Object.fromEntries(Object.keys(sides).map(k => [k, k === a || k === b]));
// The corners each bar position touches, written out by hand as the reference.
const touching = { top: both("top_left", "top_right"), bottom: both("bottom_left", "bottom_right"), left: both("top_left", "bottom_left"), right: both("top_right", "bottom_right") };
// What Popup.qml passes: beside a side bar the rounded corners, else null and whether the popup rises from a bottom bar.
const same = (a, b) => Object.keys(sides).every(k => a[k] === b[k]);
const derive = (bar, flush = true) => plain(P.bar_square(bar === "left" || bar === "right" ? D.beside_corners(bar) : null, flush, bar === "bottom"));
const none = { top_left: false, top_right: false, bottom_left: false, bottom_right: false };
const W = 200, H = 120;
// Whether a corner is cut: the box's corner point itself is not on the outline.
const corner_is_cut = (pts, name) => !pts.some(p => Math.abs(p[0] - sides[name][0] * W) < 0.01 && Math.abs(p[1] - sides[name][1] * H) < 0.01);
// The slant foot and the chamfer only shape the bottom corners; their top corners are the plain frame's.
const outlines = {
  octagon: { names: Object.keys(sides), draw: sq => P.octagon(W, H, 0, 20, sq) },
  visor: { names: Object.keys(sides), draw: sq => P.visor(W, H, 0, 18, 6, H - 18 * 0.52, sq) },
  chamfer: { names: ["bottom_left", "bottom_right"], draw: sq => P.chamfer(W, H, 12, 0, sq) },
  slant: { names: ["bottom_left", "bottom_right"], draw: sq => P.slant_foot(W, H, 0, sq) },
};
for (const bar of Object.keys(touching)) {
  const sq = derive(bar);
  expect(same(sq, touching[bar]), "bar_square under a " + bar + " bar: " + JSON.stringify(sq));
  if (bar === "top" || bar === "bottom") expect(same(derive(bar, false), none), "bar_square of a floating or docked popup under a " + bar + " bar: " + JSON.stringify(derive(bar, false)));
  for (const [shape, { names, draw }] of Object.entries(outlines)) {
    for (const name of names) {
      const cut = corner_is_cut(draw(sq), name);
      expect(cut === !sq[name], shape + " beside a " + bar + " bar: " + name + " corner " + (cut ? "is cut" : "is square") + ", want " + (sq[name] ? "square" : "cut"));
    }
  }
  // Scanline rows: a row at the top or bottom edge is trimmed at a side only where that side's corner is cut.
  for (const [name, [x, y]] of Object.entries(sides)) {
    const trimmed = P.corner_cut(sq, x === 0, y === 0 ? 0 : H - 1, 20, 2, H) > 0;
    expect(trimmed === !sq[name], "tie scanline trim beside a " + bar + " bar: " + name + (trimmed ? " is trimmed" : " is not trimmed") + ", want the opposite");
  }
  // Struts: one per cut corner, none on a square one.
  const strut_corners = P.struts(sq).map(t => (t[1] === 0 ? "top_" : "bottom_") + (t[0] === 0 ? "left" : "right")).sort();
  expect(JSON.stringify(strut_corners) === JSON.stringify(Object.keys(sides).filter(k => !sq[k]).sort()), "tie struts beside a " + bar + " bar: " + strut_corners);
  // Visor teeth: one under each cut bottom corner, on its own side.
  const teeth = P.visor_teeth(W, 18, sq).map(t => t[0] < W / 2 ? "bottom_left" : "bottom_right").sort();
  expect(JSON.stringify(teeth) === JSON.stringify(["bottom_left", "bottom_right"].filter(k => !sq[k])), "visor teeth beside a " + bar + " bar: " + teeth);
}
// A floating style rounds the corner against the bar too, beside a side bar as under a top one.
for (const bar of ["left", "right"]) {
  expect(same(P.bar_square(Object.fromEntries(Object.keys(sides).map(k => [k, true])), false, false), none), "a floating popup beside a " + bar + " bar squares a corner");
}
// Nothing is squared by default, so the overview and toasts keep their cuts.
expect(Object.values(vm.runInContext("none", P)).every(v => v === false), "PanelCuts.none squares a corner");
// The center island's cava on a side bar stands in a tail below the modules, not over them: none on a top or bottom
// bar or with cava off, cut to the room above the bottom island on a short screen, and the modules never move.
const T = vm.createContext({});
vm.runInContext(read("features/bar/CavaTail.js").replace(/^\.pragma.*$/gm, ""), T);
const tail_gap = Number(/tail_gap: (\d+)/.exec(read("features/bar/Bar.qml"))[1]), along_margin = Number(/along_margin: [^\n]*: (\d+)\n/.exec(read("features/bar/Bar.qml"))[1]);
const wanted = 108, least = tail_gap + along_margin, roomy = T.free_space(1080, 200, 300, 0, 6), short = T.free_space(600, 200, 300, 0, 6);
const tail_of = (free, fade = 1) => T.tail_span(T.tail_target(true, wanted, free, least), fade);
expect(T.tail_span(T.tail_target(false, wanted, roomy, least), 1) === 0, "a top or bottom bar gets a cava tail");
expect(tail_of(roomy, 0) === 0, "the tail stays with cava off");
expect(tail_of(roomy, 1) === wanted, "the tail is not full with room to spare");
expect(short < wanted && tail_of(short) === Math.max(0, short), "the tail is not cut to the free room on a short screen");
// Free room between none and what is wanted: 900 px leaves 44 below the modules, and a bottom inset takes from it.
expect(T.free_space(900, 200, 300, 0, 6) === 44 && T.free_space(900, 200, 300, 10, 6) === 34 && roomy === 134, "free_space gives " + T.free_space(900, 200, 300, 0, 6) + ", " + T.free_space(900, 200, 300, 10, 6) + " and " + roomy + ", want 44, 34 and 134");
expect(tail_of(44) === 44 && tail_of(44, 0.5) === 22, "a free room of 44 gives a tail of " + tail_of(44) + ", want 44 (22 at half fade)");
// Room that cannot hold a bar (under the gap and margin) gives no tail, not an empty one.
expect(tail_of(least - 1) === 0 && tail_of(least) === 0 && tail_of(least + 1) === least + 1, "tails at least-1, least and least+1 are " + tail_of(least - 1) + ", " + tail_of(least) + " and " + tail_of(least + 1) + ", want 0, 0 and " + (least + 1));
expect(T.tail_target(true, wanted, -40, least) === 0, "a negative free room gives a tail");
// The bars stay inside the plate while it fades: at every fade the bars, their gap before and the margin after fit in the tail.
for (const fade of [0, 0.1, 0.25, 0.5, 0.9, 1]) {
  const span = tail_of(roomy, fade), bars = T.bars_length(span, tail_gap, along_margin);
  expect(bars >= 0 && (bars === 0 || bars + least === span), "bars of " + bars + " in a tail of " + span + " at fade " + fade + " do not fit it");
}
expect(/CavaTail\.bars_length\(center_cava\.tail_span,/.test(read("features/bar/Bar.qml")) && /module_span \+ center_cava\.tail_span - center_cava\.along_margin/.test(read("features/bar/Bar.qml")), "the cava bars are not sized and placed from the fading tail");
expect(tail_of(roomy, 0.5) === wanted / 2, "the tail does not follow the bars' fade");
// A centre popup beside the bar lines up with the modules, so the cava tail must not move it: with a tail the island is
// taller by the tail, and the popup's extent takes that back out.
for (const side of ["left", "center", "right"]) {
  const modules = 200, top = 440, popup_length = 150, tail = 80;
  const without = D.beside_place(side, "left", top, D.beside_extent(modules, 0), popup_length, 1080).margin_top;
  const with_tail = D.beside_place(side, "left", top, D.beside_extent(modules + tail, tail), popup_length, 1080).margin_top;
  expect(without === with_tail && D.beside_extent(modules + tail, tail) === modules, "a " + side + " popup moves from " + without + " to " + with_tail + " when the cava tail grows");
}
expect(/Drawer\.beside_extent\(root\.island\.height, root\.island\.tail_span \|\| 0\)/.test(popup), "Popup.qml does not take the tail out of the island length");
// Every island property the popup reads must exist on the island.
expect(/readonly property real capsule_width:/.test(read("features/bar/Island.qml")) && /island\.capsule_width/.test(popup), "Popup.qml reads a capsule_width the island does not define");
// The bar's wiring: the least tail is the gap plus the margin the tail's bars keep clear, a hidden bottom island reserves
// no room, and the submap line follows the island's centre (half the tail below the screen's).
const bar_src = read("features/bar/Bar.qml");
expect(/tail_target\([^]*?center_cava\.tail_gap \+ center_cava\.along_margin\)/.test(bar_src), "Bar.qml does not pass the gap plus margin as the least tail");
expect(/right_side\.length > 0 \? right_island\.height : 0/.test(bar_src), "Bar.qml reserves room for a hidden bottom island");
expect(/line_shift: [^\n]*center_tail \/ 2/.test(read("shell.qml")) && /root\.line_shift \* 2/.test(read("features/bar/SubmapTab.qml")), "the submap line is not shifted by half the cava tail");
expect(/CavaTail\.tail_span\(center_cava\.tail_target, center_cava\.opacity\)/.test(read("features/bar/Bar.qml")) && /\(root\.height - module_length\) \/ 2/.test(read("features/bar/Bar.qml")), "the center island is centred by its tail or the tail ignores the fade");
// The popup hands that derivation to the frame, and the radii read the same rounded set; each outline draws through PanelCuts.
expect(/square: root\.bar_square/.test(popup) && /Cuts\.bar_square\(root\.beside \? root\.beside_round : null/.test(popup) && /beside_round\.top_left/.test(popup), "Popup.qml does not derive its bar-side corners once");
expect(/Cuts\.corner_cut/.test(read("styles/tie/widgets/OctagonFrame.qml")) && /Cuts\.struts/.test(read("styles/tie/widgets/OctagonFrame.qml")), "OctagonFrame does not trim and strut through PanelCuts");
expect(/Cuts\.visor_teeth/.test(read("ui/frames/VisorGlass.qml")), "VisorGlass does not draw its teeth through PanelCuts");
for (const f of ["features/popups/frames/StyledFrame.qml", "features/popups/frames/CustomFrame.qml", "styles/oasis/widgets/SlantFrame.qml", "styles/tie/widgets/OctagonFrame.qml", "ui/frames/VisorGlass.qml", "ui/frames/FrameShade.qml"]) {
  expect(/square/.test(read(f)) && /PanelCuts\.js/.test(read(f)), f + " does not draw through PanelCuts with a square set");
}
for (const f of ["features/popups/frames/StyledFrame.qml", "features/popups/frames/CustomFrame.qml"]) {
  expect((read(f).match(/square: root\.square/g) || []).length >= 2, f + " does not pass square on to every outline");
}

if (failed) process.exit(1);
console.log("island shapes: " + (cases.length + shapes.length * 3 + strip_kits.length + 1 + frame_checks + end_checks + pane_checks) + " checks passed");
