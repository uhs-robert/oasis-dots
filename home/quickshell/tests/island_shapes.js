// Runs IslandOutlines.js's fill-less helpers, BandGeometry.js and FrameGeometry.js under node, and checks every Style.island_shapes
// entry and Style.screen_frames entry has a kit and a label.
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
  ["a vertical bar keeps the shapes that have a vertical form", () => ["slant", "rect", "chevron", "tab", "none", "underline", "brackets"].map(O.vertical_shape), ["slant", "rect", "chevron", "tab", "none", "underline", "brackets"]],
  ["a shape without a vertical form draws as rect for now", () => ["lualine", "window", "capsule", "hex"].map(O.vertical_shape), ["rect", "rect", "rect", "rect"]],
  ...["rect", "chevron", "tab"].flatMap(shape => ["left", "right"].flatMap(edge => {
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

// Every screen frame but "" (none) is one of the corner profiles and has a settings label; they share one kit frame_layout can measure.

let frame_checks = 0;
const expect = (ok, message) => {
  frame_checks++;
  if (!ok) { failed++; console.log("FAIL " + message); }
};
const frame_corners = JSON.parse(style.match(/frame_corners: (\[[^\]]*\])/)[1]);
const frame_kit = vm.runInNewContext(style.match(/plain_frame_kit: (\(\{[^}]*\}\))/)[1]);
const frame_labels = style.slice(style.indexOf("borrow_names")).match(/screen_frame: \{([^}]*)\}/)[1];
expect(["radius", "thickness"].every(k => typeof frame_kit[k] === "number"), "no usable plain_frame_kit");
expect(/screen_frames: \[""\]\.concat\(root\.frame_corners\)/.test(style), "screen_frames is not Off plus the corner profiles");
for (const f of [""].concat(frame_corners)) {
  expect(new RegExp((f === "" ? '""' : "\\b" + f) + ": \"").test(frame_labels), "no label for screen frame " + JSON.stringify(f));
}
// Lualine takes the frame like any style: frame_kit_for evaluated from the QML source.
const FT = vm.createContext({});
vm.runInContext(read("theme/FrameTokens.js").replace(/^\.pragma.*$/gm, ""), FT);
const kit_for = vm.runInNewContext("(function(root) { return function" + style.match(/function frame_kit_for(\([^)]*\) \{[^}]*\})/)[1] + "; })", { FrameTokens: FT })({ frame_corners, plain_frame_kit: frame_kit });
expect(kit_for({ bar_lualine: true, screen_frame: "pixel" }) !== null, "a lualine style with a frame corner gets no frame kit");
expect(kit_for({ bar_lualine: true, screen_frame: "" }) === null, "a lualine style with no frame corner gets a kit");
expect(kit_for({ screen_frame: "round", screen_frame_offered: false }) === null, "screen_frame_offered false does not opt out");
// Each style's corner hint is a profile.
for (const dir of fs.readdirSync(path.join(root, "styles"), { withFileTypes: true }).filter(d => d.isDirectory())) {
  const tokens_path = path.join(root, "styles", dir.name, "tokens.js");
  if (!fs.existsSync(tokens_path)) continue;
  for (const m of fs.readFileSync(tokens_path, "utf8").matchAll(/screen_frame_corners: "(\w+)"/g)) {
    expect(frame_corners.indexOf(m[1]) >= 0, dir.name + " hints the unknown corner " + m[1]);
  }
}

// Style.load_options turns a v2 "plain" frame into a corner before checking the row's choices, and stamps version 3.
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
expect(/options_version: 3/.test(style), "options_version is not 3");
expect(load.indexOf("screen_frame_from_plain") > 0 && load.indexOf("screen_frame_from_plain") < load.indexOf("valid_option"), "the frame migration does not run before valid_option");

// Runs the real load_options on saved files: each migration applies only below the version that introduced it.
const load_saved = data => {
  const root = { theme_values: null, frame_corners, renamed_island_shapes: { octagon: "watch" }, styles: { modern: {} },
    settings_for: () => [{ key: "bar_island_shape", default: "slant" }, { key: "screen_frame", default: "" }],
    valid_option: () => true, save_options: () => {} };
  const body = load.slice(0, load.indexOf("\n    }\n") + 6).replace(/^function load_options/, "(function");
  vm.runInNewContext(body + ")", { root, Migrations: M })(data);
  return plain(root.theme_values.modern || {});
};
const saved_modern = (version, values) => load_saved({ version, modern: values });
for (const [name, got, want] of [
  ["a version 2 file keeps a chosen octagon", saved_modern(2, { bar_island_shape: "octagon" }).bar_island_shape, "octagon"],
  ["a version 1 file renames octagon to watch", saved_modern(1, { bar_island_shape: "octagon" }).bar_island_shape, "watch"],
  ["a file without a version renames octagon to watch", saved_modern(undefined, { bar_island_shape: "octagon" }).bar_island_shape, "watch"],
  ["a version 2 file turns plain into a corner", saved_modern(2, { screen_frame: "plain", screen_frame_corners: "chamfer" }).screen_frame, "chamfer"],
  ["a version 3 file leaves plain alone", saved_modern(3, { screen_frame: "plain" }).screen_frame, "plain"],
]) {
  expect(got === want, "load_options: " + name + ": got " + got + ", want " + want);
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
  ["terminal still offers the frame", FT.offered(terminal), true],
  ["neovim (lualine) is offered the frame", FT.offered(neovim), true],
  ["a style with screen_frame_offered false is not offered it", FT.offered({ screen_frame_offered: false }), false],
  ["a frame forces a slant bar to the full bar", FT.forces_full_bar({ bar_island_shape: "slant" }), true],
  ["a frame leaves a full bar alone", FT.forces_full_bar({ bar_island_shape: "full" }), false],
  ["a frame leaves lualine's sections alone", FT.forces_full_bar(neovim), false],
  ["the row offers Off or Square for terminal", JSON.stringify(FT.row_choices(terminal.screen_frame_only, frame_corners.concat())), JSON.stringify(["", "square"])],
  ["the row offers Off and every corner otherwise", JSON.stringify(FT.row_choices("", ["", ...frame_corners])), JSON.stringify(["", ...frame_corners])],
  ["the row offers Off and every corner for an unset only", JSON.stringify(FT.row_choices(undefined, ["", ...frame_corners])), JSON.stringify(["", ...frame_corners])],
]) {
  pane_checks++;
  expect(got === want, "terminal frame: " + name + ": got " + got + ", want " + want);
}
expect(/FrameTokens\.rim_width/.test(style) && /FrameTokens\.rim_color/.test(style) && /FrameTokens\.row_choices/.test(style) && /FrameTokens\.offered/.test(style) && /FrameTokens\.forces_full_bar/.test(style), "Style.qml does not use FrameTokens");
expect(/Style\.screen_frame_rim_width/.test(read("features/bar/ScreenFrame.qml")) && /Style\.screen_frame_rim_width/.test(read("features/bar/ScreenFrameSync.qml")), "the drawn rim and Hyprland's border do not share screen_frame_rim_width");
pane_checks += 2;

if (failed) process.exit(1);
console.log("island shapes: " + (cases.length + shapes.length * 3 + strip_kits.length + 1 + frame_checks + end_checks + pane_checks) + " checks passed");
