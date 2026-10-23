// Runs DrawerGeometry.js, Corners.js and FrameGeometry's hole_rect/seam_of under node: the drawer's layout, fill, outline and
// placement on every edge, that its rim lands where the screen frame's own line is, and each corner profile's joins.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const root = path.join(__dirname, "../.config/quickshell");
const read = rel => fs.readFileSync(path.join(root, rel), "utf8").replace(/^\.(pragma|import).*$/gm, "");
const O = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, "features/bar/IslandOutlines.js"), "utf8").replace(/^\.pragma.*$/gm, ""), O);
const load = (rel, imports) => {
  const ctx = vm.createContext(imports);
  vm.runInContext(read(rel), ctx);
  return ctx;
};
const B = load("features/bar/BandGeometry.js", { Outlines: O });
const C = load("features/bar/Corners.js", { Outlines: O });
const F = load("features/bar/FrameGeometry.js", { Outlines: O, Corners: C });
const D = load("features/bar/DrawerGeometry.js", { Outlines: O, Band: B, Corners: C });
const plain = v => JSON.parse(JSON.stringify(v));

const kit = { corner: "round", radius: 12, thickness: 6, ornament: "" };
const top_frame = F.frame_layout(1920, 1080, "top", 30, kit);
const bottom_frame = F.frame_layout(1920, 1080, "bottom", 30, kit);
const bare_frame = F.frame_layout(1920, 1080, "", 30, kit);
const cover = D.cover_depth(2, 1, 1);
const EDGES = ["top", "bottom", "left", "right"];
const KINDS = [["fillet", "fillet"], ["pocket", "fillet"], ["fillet", "pocket"], ["pocket", "pocket"]];
const spec = (over) => Object.assign({ edge: "top", body_length: 400, body_depth: 200, extent: 200, radius: 12, fillet: 12, start_kind: "fillet", end_kind: "fillet", cover: cover }, over);
const lay_of = over => D.drawer_layout(spec(over));
const near = (p, q, tol = 0.1) => Math.hypot(p[0] - q[0], p[1] - q[1]) < tol;
const loop_area = loop => Math.abs(loop.reduce((s, p, k) => k === 0 ? 0 : s + loop[k - 1][0] * p[1] - p[0] * loop[k - 1][1], 0)) / 2;
const corner_gap = 1 - Math.PI / 4;
// The area the fill covers, from its parts: the cover strip, the body, each pocket's strip down the side band, each
// fillet's corner, less each free corner.
const fill_area = lay => {
  const c = lay.cover, e = lay.body.d, f = lay.fillet_eff, r = lay.radius_eff;
  let a = lay.length * c + lay.body.w * e + 2 * f * f * corner_gap;
  for (const kind of [lay.start_kind, lay.end_kind]) a += kind === "pocket" ? c * (e + f) : -r * r * corner_gap;
  return a;
};
// The polyline's chords cut each arc's sector short by about 0.0033 r^2 (ARC_STEPS 10), so the area is checked to that.
const chord_slack = lay => 0.1 + 0.0035 * (2 * lay.fillet_eff ** 2 + 2 * lay.radius_eff ** 2);
// Whether any two non-adjacent segments of a polyline cross, which a drawer's loop or line must never do.
const segments_cross = (a, b, c, d) => {
  const side = (p, q, r) => Math.sign((q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]));
  return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0;
};
const self_intersects = pts => pts.some((p, i) => i + 1 < pts.length && pts.some((q, j) => j > i + 1 && j + 1 < pts.length && segments_cross(p, pts[i + 1], q, pts[j + 1])));
const in_polygon = (pt, poly) => {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const a = poly[i], b = poly[j];
    if ((a[1] > pt[1]) !== (b[1] > pt[1]) && pt[0] < (b[0] - a[0]) * (pt[1] - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
  }
  return inside;
};
const apply = (m, p) => [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]];
const finite = pts => pts.every(p => Number.isFinite(p[0]) && Number.isFinite(p[1]));
const bbox = pts => ({
  x0: Math.min(...pts.map(p => p[0])), x1: Math.max(...pts.map(p => p[0])),
  y0: Math.min(...pts.map(p => p[1])), y1: Math.max(...pts.map(p => p[1]))
});
const hole_box = lay => {
  const m = F.to_screen(lay), b = bbox(F.hole_loop(lay).map(p => [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]]));
  return { x: b.x0, y: b.y0, w: b.x1 - b.x0, h: b.y1 - b.y0 };
};

const cases = [
  ["cover_depth rim 2 inset 1+1", () => D.cover_depth(2, 1, 1), 3],
  ["cover_depth fractional rim", () => D.cover_depth(1.5, 0, 0), 3],
  ["cover_depth inset beyond rim", () => D.cover_depth(1, 3, 1), 5],

  // 1920x1080 with a 30 px bar and 6 px bands.
  ["hole_rect top bar", () => plain(F.hole_rect(top_frame)), { x: 6, y: 30, w: 1908, h: 1044 }],
  ["hole_rect bottom bar", () => plain(F.hole_rect(bottom_frame)), { x: 6, y: 6, w: 1908, h: 1044 }],
  ["hole_rect no bar", () => plain(F.hole_rect(bare_frame)), { x: 6, y: 6, w: 1908, h: 1068 }],
  ["seam_of top bar", () => EDGES.map(e => F.seam_of(top_frame, e)), [30, 1074, 6, 1914]],
  ["seam_of bottom bar", () => EDGES.map(e => F.seam_of(bottom_frame, e)), [6, 1050, 6, 1914]],
  ["seam_of no bar", () => EDGES.map(e => F.seam_of(bare_frame, e)), [6, 1074, 6, 1914]],
  ...[["top", top_frame], ["bottom", bottom_frame], ["no bar", bare_frame]].map(([name, lay]) =>
    ["hole_rect matches hole_loop's box, " + name, () => plain(F.hole_rect(lay)), plain(hole_box(lay))]),
];

// Surface size: fixed for the whole animation, swapped on the vertical edges.
for (const [start_kind, end_kind] of KINDS) {
  const pockets = (start_kind === "pocket") + (end_kind === "pocket");
  const length = 400 + (start_kind === "pocket" ? cover : 12 + 2) + (end_kind === "pocket" ? cover : 12 + 2);
  const depth = cover + 200 + (pockets ? 12 + 2 : 0);
  for (const edge of EDGES) {
    const vertical = edge === "left" || edge === "right";
    for (const extent of [0, 50, 200]) {
      cases.push([`surface ${start_kind}/${end_kind} ${edge} extent ${extent}`, () => plain(lay_of({ edge, start_kind, end_kind, extent }).surface),
        vertical ? { width: depth, height: length } : { width: length, height: depth }]);
    }
  }
}

for (const [start_kind, end_kind] of KINDS) {
  for (const extent of [0, 5, 13, 24, 60, 200]) {
    const lay = lay_of({ start_kind, end_kind, extent });
    const name = `${start_kind}/${end_kind} extent ${extent}`;
    cases.push(["fill area " + name, () => Math.abs(loop_area(D.fill_loop(lay)) - fill_area(lay)) < chord_slack(lay), true]);
    cases.push(["fill loop closes, finite " + name, () => { const l = D.fill_loop(lay); return near(l[0], l[l.length - 1], 1e-9) && finite(l); }, true]);
    cases.push(["stroke finite " + name, () => finite(D.stroke_path(lay, 1)) && finite(D.stroke_path(lay, 2)), true]);
    // The loop stays inside the surface, so nothing is clipped.
    cases.push(["fill within surface " + name, () => { const b = bbox(D.fill_loop(lay)); return b.x0 > -1e-9 && b.y0 > -1e-9 && b.x1 < lay.length + 1e-9 && b.y1 < lay.depth + 1e-9; }, true]);
    // No segment of the outline runs along the seam inside the body span, whatever the extent but 0.
    if (extent > 0) {
      cases.push(["outline open on the attached side " + name, () => {
        const p = D.outline_path(lay), lo = lay.start_room, hi = lay.length - lay.end_room;
        return p.every((q, k) => k === 0 || !(Math.abs(q[1] - lay.cover) < 1e-9 && Math.abs(p[k - 1][1] - lay.cover) < 1e-9 && Math.max(q[0], p[k - 1][0]) > lo + 1e-9 && Math.min(q[0], p[k - 1][0]) < hi - 1e-9));
      }, true]);
    }
  }
  // The area only grows as the drawer opens.
  cases.push([`area grows with the extent ${start_kind}/${end_kind}`, () => {
    let last = -1;
    for (let k = 0; k <= 10; k++) {
      const a = loop_area(D.fill_loop(lay_of({ start_kind, end_kind, extent: 20 * k })));
      if (!Number.isFinite(a) || a < last - 1e-9) return false;
      last = a;
    }
    return true;
  }, true]);
  cases.push([`closed drawer is the cover strip ${start_kind}/${end_kind}`, () => {
    const lay = lay_of({ start_kind, end_kind, extent: 0 });
    return Math.abs(loop_area(D.fill_loop(lay)) - lay.length * lay.cover) < 1e-6 && D.fill_loop(lay).every(p => p[1] <= lay.cover + 1e-9);
  }, true]);
}
cases.push(["closed fillet drawer's outline is the seam", () => D.outline_path(lay_of({ extent: 0 })).every(p => p[1] === cover), true]);
cases.push(["radii clamp to half the extent", () => { const l = lay_of({ extent: 10 }); return [l.radius_eff, l.fillet_eff]; }, [5, 5]]);
cases.push(["radius clamps to half the body", () => lay_of({ body_length: 10 }).radius_eff, 5]);
cases.push(["extent clamps to the body depth", () => lay_of({ extent: 500 }).body.d, 200]);
cases.push(["extent never negative", () => lay_of({ extent: -4 }).body.d, 0]);

// With a bar, the stroke starts and ends on the strip's own line d out from the near edge, exactly at the straight
// stretch's ends where the strip's line takes over, and runs along that line to each corner's mitre: whatever the
// corner and however thick the line, the corners join it without a notch, a step or an overlap.
for (const corner of ["round", "chamfer", "pixel", "square"]) {
  for (const d of [1, 2.5]) {
    cases.push(["frame stroke ends on the strip's line: " + corner + ", d " + d, () => {
      const lay = F.frame_layout(1920, 1080, "top", 34, Object.assign({}, kit, { corner, step: 2 }));
      const s = F.frame_stroke(lay, d), n = s.length;
      const [lo, hi] = lay.straight, on_line = p => Math.abs(p[1] - (lay.near - d)) < 1e-6;
      return [s[0], s[1], s[n - 2], s[n - 1]].every(on_line)
        && Math.abs(s[0][0] - hi) < 1e-6 && Math.abs(s[n - 1][0] - lo) < 1e-6
        && s[1][0] >= hi && s[1][0] <= hi + d + 1e-6 && s[n - 2][0] <= lo && s[n - 2][0] >= lo - d - 1e-6;
    }, true]);
  }
}

// The rim meets the frame's own line. The window sits cover px up inside the band from the seam, so the outline's
// seam at v = cover lands on the hole's edge and the rim a half-width in on the band side, like frame_stroke's.
{
  const top = lay_of({ edge: "top" });
  const origin_y = top_frame.near - cover;
  cases.push(["rim continues the frame's line, top bar", () => {
    const m = D.drawer_affine(top), p = apply(m, D.stroke_path(top, 1)[0]);
    return Math.abs(p[1] + origin_y - (top_frame.near - 1)) < 0.1;
  }, true]);
  const bottom = lay_of({ edge: "bottom" });
  cases.push(["rim continues the frame's line, bottom bar", () => {
    // A bottom bar's seam is at depth - near on screen; the frame's line lies below it, at screen y + 1.
    const m = D.drawer_affine(bottom), p = apply(m, D.stroke_path(bottom, 1)[0]);
    const origin_y = F.seam_of(bottom_frame, "bottom") + cover - bottom.depth;
    const f = F.to_screen(bottom_frame), g = F.frame_stroke(bottom_frame, 1)[0];
    const frame_y = f[1] * g[0] + f[3] * g[1] + f[5];
    return Math.abs(p[1] + origin_y - frame_y) < 0.1;
  }, true]);
  // Left and right carry the same line round: a point on the seam maps onto the hole's edge.
  for (const edge of ["left", "right"]) {
    cases.push(["rim lands on the " + edge + " seam", () => {
      const lay = lay_of({ edge }), fr = top_frame;
      const origin_x = edge === "left" ? F.seam_of(fr, "left") - cover : F.seam_of(fr, "right") + cover - lay.depth;
      const p = apply(D.drawer_affine(lay), D.stroke_path(lay, 1)[0]);
      const seam = F.seam_of(fr, edge);
      return Math.abs(p[0] + origin_x - (seam + (edge === "left" ? -1 : 1))) < 0.1;
    }, true]);
  }
}

// A pocket fills the hole's rounded corner: the corner point just inside the square corner is inside the fill.
for (const [name, fr, edge] of [["top bar", top_frame, "top"], ["bottom bar", bottom_frame, "bottom"]]) {
  cases.push(["pocket fills the hole corner, start, " + name, () => {
    const lay = lay_of({ edge, start_kind: "pocket" });
    return in_polygon([cover + 1, cover + 1], D.fill_loop(lay));
  }, true]);
  cases.push(["pocket fills the hole corner, end, " + name, () => {
    const lay = lay_of({ edge, end_kind: "pocket" });
    return in_polygon([lay.length - cover - 1, cover + 1], D.fill_loop(lay));
  }, true]);
  cases.push(["pocket reaches the rounded corner's far side, " + name, () => {
    const lay = lay_of({ edge, start_kind: "pocket", extent: fr.radius + 3 });
    return in_polygon([cover + 0.5, cover + fr.radius], D.fill_loop(lay));
  }, true]);
}
cases.push(["fillet end leaves the corner past the body empty", () => !in_polygon([2, cover + 3], D.fill_loop(lay_of({}))), true]);
cases.push(["fillet end fills the corner against the band", () => in_polygon([11.5, cover + 0.5], D.fill_loop(lay_of({}))), true]);

// Rects in window coordinates exclude the cover and the fillets.
const rect_of = (edge, over) => { const lay = lay_of(Object.assign({ edge }, over)); return plain(D.body_rect(lay)); };
cases.push(["body_rect top", () => rect_of("top"), { x: 14, y: cover, width: 400, height: 200 }]);
cases.push(["body_rect bottom", () => rect_of("bottom"), { x: 14, y: 0, width: 400, height: 200 }]);
cases.push(["body_rect left", () => rect_of("left"), { x: cover, y: 14, width: 200, height: 400 }]);
cases.push(["body_rect right", () => rect_of("right"), { x: 0, y: 14, width: 200, height: 400 }]);
cases.push(["body_rect follows the extent", () => rect_of("top", { extent: 80 }), { x: 14, y: cover, width: 400, height: 80 }]);
cases.push(["body_rect pocket start", () => rect_of("top", { start_kind: "pocket" }).x, cover]);
cases.push(["input_rect equals the body", () => EDGES.every(e => { const lay = lay_of({ edge: e }); return JSON.stringify(D.input_rect(lay)) === JSON.stringify(D.body_rect(lay)); }), true]);
cases.push(["body_rect excludes the cover strip and the fillets", () => {
  const lay = lay_of({}), r = D.body_rect(lay);
  return r.y >= lay.cover && r.x >= lay.fillet_eff && r.x + r.width <= lay.length - lay.fillet_eff;
}, true]);

// The window corners land on the surface's corners on every edge.
for (const edge of EDGES) {
  cases.push(["drawer_affine corners, " + edge, () => {
    const lay = lay_of({ edge }), m = D.drawer_affine(lay), s = lay.surface;
    const pts = [[0, 0], [lay.length, 0], [lay.length, lay.depth], [0, lay.depth]].map(p => apply(m, p));
    const b = bbox(pts);
    const attached = { top: b.y0 === 0 && pts[0][1] === 0, bottom: pts[0][1] === s.height, left: pts[0][0] === 0, right: pts[0][0] === s.width }[edge];
    return b.x0 === 0 && b.y0 === 0 && b.x1 === s.width && b.y1 === s.height && attached;
  }, true]);
}

// Fractional positions: radii and the extent are fractions of a pixel, as at scale 1.6; nothing goes non-finite and
// the fill keeps its area.
for (const [start_kind, end_kind] of KINDS) {
  for (const extent of [0.3, 7.77, 100.5]) {
    const over = { start_kind, end_kind, extent, body_length: 333.3, body_depth: 150.6, radius: 11.2, fillet: 11.2, cover: D.cover_depth(1.5, 0.5, 1) };
    cases.push([`fractional ${start_kind}/${end_kind} extent ${extent}`, () => {
      const lay = lay_of(over);
      return finite(D.fill_loop(lay)) && finite(D.stroke_path(lay, 0.75)) && Math.abs(loop_area(D.fill_loop(lay)) - fill_area(lay)) < chord_slack(lay);
    }, true]);
  }
}

// A body narrower than two fillets must shrink the arcs, not cross them.
for (const [start_kind, end_kind] of KINDS) {
  for (const body_length of [4, 10, 23]) {
    const over = { start_kind, end_kind, body_length };
    cases.push([`narrow ${body_length} px ${start_kind}/${end_kind} does not self-intersect`, () => {
      const lay = lay_of(over);
      return !self_intersects(D.fill_loop(lay)) && !self_intersects(D.outline_path(lay)) && lay.fillet_eff <= body_length / 2;
    }, true]);
  }
}

// Placement on a 1920x1080 screen with a 6 px band: the hole is 1908 wide from x 6, the cover 3 px, the top seam at 30 and the bottom seam at 1050.
const hole = F.hole_rect(top_frame);
const full_length = 600;
cases.push(["body length keeps a narrower popup's width", () => D.body_length("center", 400, hole.w, 12), 400]);
cases.push(["centre body clips to the hole less two fillets", () => D.body_length("center", 5000, hole.w, 12), 1884]);
cases.push(["a docked body takes the whole hole", () => D.body_length("dock", 400, hole.w, 12), hole.w]);
cases.push(["a docked body takes the whole hole, wide request", () => D.body_length("dock", 5000, hole.w, 12), hole.w]);
cases.push(["docked pocket/pocket window spans the hole plus a cover each side", () => D.drawer_layout(spec({ edge: "bottom", body_length: hole.w, start_kind: "pocket", end_kind: "pocket" })).length, hole.w + 2 * cover]);
cases.push(["left body clips to the hole less one fillet", () => D.body_length("left", 5000, hole.w, 12), 1896]);
cases.push(["right body clips to the hole less one fillet", () => D.body_length("right", 5000, hole.w, 12), 1896]);
cases.push(["left margin starts under the band by the cover", () => D.margin_along("left", hole, 1920, cover, full_length), 3]);
cases.push(["right margin counts from the right screen edge", () => D.margin_along("right", hole, 1920, cover, full_length), 3]);
cases.push(["centre margin centres the window on the hole", () => D.margin_along("center", hole, 1920, cover, full_length), 660]);
cases.push(["centre margin rounds a fractional origin", () => D.margin_along("center", { x: 10.4, w: 100 }, 1920, cover, 51), 35]);
cases.push(["top margin is the seam less the cover", () => D.margin_across(false, F.seam_of(top_frame, "top"), 1080, cover), 27]);
cases.push(["bottom margin counts from the bottom screen edge", () => D.margin_across(true, F.seam_of(bottom_frame, "bottom"), 1080, cover), 27]);
cases.push(["margins are integers at fractional seams", () => Number.isInteger(D.margin_across(true, 36.4, 1079.5, 3)) && Number.isInteger(D.margin_across(false, 36.4, 1079.5, 3)), true]);

// An outline, lead included, must stay inside the window at the first and last extent, along and across the drawer.
for (const edge of EDGES) {
  for (const [start_kind, end_kind] of KINDS) {
    for (const extent of [0, 200]) {
      cases.push([`outline inside the window: ${edge} ${start_kind}/${end_kind} extent ${extent}`, () => {
        const lay = D.drawer_layout(spec({ edge, start_kind, end_kind, extent }));
        return D.outline_path(lay).every(p => p[1] <= lay.depth + 1e-9 && p[0] >= -1e-9 && p[0] <= lay.length + 1e-9);
      }, true]);
    }
  }
}

// Translucent drawers: the fill stays in the hole, and the frame's lines are left out under the window.
const area_of = loop => { let a = 0; for (let k = 0; k + 1 < loop.length; k++) a += loop[k][0] * loop[k + 1][1] - loop[k + 1][0] * loop[k][1]; return Math.abs(a) / 2; };
for (const [start_kind, end_kind] of KINDS) {
  for (const extent of [0, 50, 200]) {
    const lay = () => lay_of({ start_kind, end_kind, extent });
    cases.push([`hole fill stays in the hole ${start_kind}/${end_kind} extent ${extent}`, () => {
      const l = lay(), lo = l.cover - 0.5;
      return D.hole_fill_loop(l).every(p => p[1] >= lo - 1e-9 && p[0] >= (l.start_kind === "pocket" ? l.start_room : 0) - 1e-9 && p[0] <= l.length - (l.end_kind === "pocket" ? l.end_room : 0) + 1e-9);
    }, true]);
    cases.push([`hole fill is smaller than the opaque fill ${start_kind}/${end_kind} extent ${extent}`, () => area_of(D.hole_fill_loop(lay())) < area_of(D.fill_loop(lay())), true]);
  }
}
cases.push(["hole fill is the body at full extent, no fillets", () => plain(D.hole_fill_loop(D.drawer_layout(spec({ fillet: 0, radius: 0, extent: 200, cover: 3 })))), [[2, 2.5], [2, 3], [2, 203], [402, 203], [402, 3], [402, 2.5], [2, 2.5]]]);
cases.push(["mouth depth is the cover and the fillet", () => D.mouth_depth(D.drawer_layout(spec({ extent: 200 }))), cover + 12]);
cases.push(["mouth depth follows a shrunk fillet", () => D.mouth_depth(D.drawer_layout(spec({ extent: 8 }))), cover + 4]);
cases.push(["drawn depth follows the extent, not the reserved body depth", () => [100, 400].map(e => D.drawer_layout(spec({ body_depth: 400, extent: e })).drawn_depth), [cover + 100, cover + 400]]);
cases.push(["a pocket drawer's drawn depth keeps the pocket room", () => D.drawer_layout(spec({ body_depth: 400, extent: 100, start_kind: "pocket" })).drawn_depth - cover - 100, 14]);
cases.push(["drawn depth at full extent is the window's", () => KINDS.map(k => { const l = D.drawer_layout(spec({ start_kind: k[0], end_kind: k[1] })); return l.drawn_depth === l.depth; }), [true, true, true, true]]);
cases.push(["gap regions without a gap", () => B.gap_regions(100, 20, []), [{ x: 0, y: 0, w: 100, h: 20 }]]);
cases.push(["gap regions round a gap", () => B.gap_regions(100, 20, [{ x: 30, y: 5, w: 40, h: 10 }]), [{ x: 0, y: 0, w: 30, h: 20 }, { x: 30, y: 0, w: 40, h: 5 }, { x: 30, y: 15, w: 40, h: 5 }, { x: 70, y: 0, w: 30, h: 20 }]]);
cases.push(["gap regions drop an empty side and clamp", () => B.gap_regions(100, 20, [{ x: -10, y: -5, w: 60, h: 100 }]), [{ x: 50, y: 0, w: 50, h: 20 }]]);
cases.push(["gap regions cover everything but the gap", () => { const g = { x: 30, y: 5, w: 40, h: 10 }; return B.gap_regions(100, 20, [g]).reduce((a, r) => a + r.w * r.h, 0) + g.w * g.h; }, 2000]);
const area_left = (gaps) => B.gap_regions(100, 20, gaps).reduce((a, r) => a + r.w * r.h, 0);
cases.push(["two apart gaps leave two cut-outs", () => area_left([{ x: 10, y: 0, w: 10, h: 10 }, { x: 60, y: 0, w: 20, h: 10 }]), 2000 - 100 - 200]);
cases.push(["overlapping gaps merge, nothing is counted twice", () => area_left([{ x: 10, y: 0, w: 30, h: 10 }, { x: 30, y: 0, w: 30, h: 10 }]), 2000 - 500]);
cases.push(["gaps past the cap are folded in, never dropped", () => B.gap_regions(100, 20, [0, 1, 2, 3, 4].map(i => ({ x: i * 20, y: 0, w: 10, h: 10 }))).length <= B.region_slots(), true]);
cases.push(["a folded gap still covers every drawer", () => area_left([0, 1, 2, 3, 4].map(i => ({ x: i * 20, y: 0, w: 10, h: 10 }))) <= 2000 - 5 * 100, true]);
const reg_ab = F.drawer_windows_with(F.drawer_windows_with({}, "DP-1", "a", { x: 0, y: 0, w: 5, h: 5 }), "DP-1", "b", { x: 9, y: 0, w: 5, h: 5 });
cases.push(["both popups' windows are held on a screen", () => F.drawer_window_rects(reg_ab, "DP-1"), [{ x: 0, y: 0, w: 5, h: 5 }, { x: 9, y: 0, w: 5, h: 5 }]]);
cases.push(["a switch: the closing popup clears only its own window", () => F.drawer_window_rects(F.drawer_windows_with(reg_ab, "DP-1", "a", null), "DP-1"), [{ x: 9, y: 0, w: 5, h: 5 }]]);
cases.push(["an unload of a popup that never published changes nothing", () => F.drawer_window_rects(F.drawer_windows_with(reg_ab, "DP-1", "c", null), "DP-1").length, 2]);
const strip_win = { x: 100, y: 0, w: 300, h: 200 }, bottom_win = { x: 100, y: 800, w: 300, h: 280 };
cases.push(["a top strip gaps a drawer hung from the top", () => F.strip_gaps([strip_win], "top", 30, 1080), [{ x: 100, y: 0, w: 300, h: 30 }]]);
cases.push(["a top strip ignores a bottom-docked drawer", () => F.strip_gaps([bottom_win], "top", 30, 1080), []]);
cases.push(["a bottom strip gaps a bottom-docked drawer", () => F.strip_gaps([bottom_win], "bottom", 30, 1080), [{ x: 100, y: 0, w: 300, h: 30 }]]);
cases.push(["a bottom strip ignores a top-hung drawer", () => F.strip_gaps([strip_win], "bottom", 30, 1080), []]);
cases.push(["without a frame every window gaps the strip", () => F.strip_gaps([bottom_win], "top", 30, 0).length, 1]);
cases.push(["a window that only touches the strip's band is left out", () => F.strip_gaps([{ x: 0, y: 30, w: 50, h: 100 }], "top", 30, 1080), []]);
cases.push(["a window that only touches a bottom strip's band is left out", () => F.strip_gaps([{ x: 0, y: 900, w: 50, h: 120 }], "bottom", 30, 1080), []]);
cases.push(["a mixed list keeps only the windows that overlap the strip", () => F.strip_gaps([bottom_win, strip_win, { x: 500, y: 400, w: 10, h: 10 }], "top", 30, 1080), [{ x: 100, y: 0, w: 300, h: 30 }]]);
cases.push(["a bar-hung window whose cover overlaps the band by 1px is kept", () => F.strip_gaps([{ x: 700, y: 29, w: 200, h: 300 }], "top", 30, 1080), [{ x: 700, y: 0, w: 200, h: 30 }]]);
cases.push(["the last window clearing drops the screen", () => F.drawer_windows_with(F.drawer_windows_with({}, "DP-1", "a", { x: 0, y: 0, w: 1, h: 1 }), "DP-1", "a", null), {}]);
cases.push(["a publish leaves other screens' entries alone", () => F.drawer_windows_with(reg_ab, "DP-2", "a", null)["DP-1"] === reg_ab["DP-1"], true]);
cases.push(["canonical rect is unchanged under a top bar", () => F.to_canonical_rect(top_frame, { x: 10, y: 20, w: 30, h: 40 }), { x: 10, y: 20, w: 30, h: 40 }]);
cases.push(["canonical rect mirrors under a bottom bar", () => F.to_canonical_rect(bottom_frame, { x: 10, y: 20, w: 30, h: 40 }), { x: 10, y: bottom_frame.depth - 60, w: 30, h: 40 }]);

const wk_hole = F.hole_rect(top_frame);
const wk_seam = F.seam_of(top_frame, "top");
const wk_left = D.place("left", false, wk_hole, wk_seam, 1920, 1080, cover, full_length);
const wk_right = D.place("right", true, wk_hole, F.seam_of(bottom_frame, "bottom"), 1920, 1080, cover, full_length);
cases.push(["a side drawer pockets at its band and fillets at the other end", () => [D.end_kinds("left", false), D.end_kinds("right", false)], [{ start: "pocket", end: "fillet" }, { start: "fillet", end: "pocket" }]]);
cases.push(["a centre drawer fillets at both ends, a docked one pockets at both", () => [D.end_kinds("center", false), D.end_kinds("center", true)], [{ start: "fillet", end: "fillet" }, { start: "pocket", end: "pocket" }]]);
cases.push(["a left top drawer anchors top-left with margins from the left and the seam", () => [wk_left.anchor_top, wk_left.anchor_bottom, wk_left.anchor_left, wk_left.anchor_right, wk_left.margin_top, wk_left.margin_left, wk_left.margin_right, wk_left.margin_bottom], [true, false, true, false, wk_seam - cover, D.margin_along("left", wk_hole, 1920, cover, full_length), 0, 0]]);
cases.push(["a right bottom drawer anchors bottom-right", () => [wk_right.anchor_top, wk_right.anchor_bottom, wk_right.anchor_left, wk_right.anchor_right, wk_right.margin_top, wk_right.margin_left, wk_right.margin_bottom > 0, wk_right.margin_right > 0], [false, true, false, true, 0, 0, true, true]]);
cases.push(["a centre drawer anchors on the left and uses the along margin there", () => { const p = D.place("center", false, wk_hole, wk_seam, 1920, 1080, cover, full_length); return [p.anchor_left, p.anchor_right, p.margin_left === p.along, p.margin_right]; }, [true, false, true, 0]]);
cases.push(["without a hole the placement has no margins", () => { const p = D.place("left", false, null, 0, 0, 0, cover, 0); return [p.margin_top, p.margin_left, p.along, p.across]; }, [0, 0, 0, 0]]);
cases.push(["a top-left window rect starts at the margins and spans the drawn depth", () => D.window_rect("left", false, wk_left, 1920, 1080, 200, 50), { x: wk_left.along, y: wk_left.across, w: 200, h: 50 }]);
cases.push(["a bottom-right window rect counts from the right and bottom screen edges", () => D.window_rect("right", true, wk_right, 1920, 1080, 200, 50), { x: 1920 - wk_right.along - 200, y: 1080 - wk_right.across - 50, w: 200, h: 50 }]);
cases.push(["a top window rect reaches the strip, so it gaps a top strip", () => F.strip_gaps([D.window_rect("left", false, wk_left, 1920, 1080, 200, 50)], "top", 30, 1080).length, 1]);

// Corner profiles: every join in every layout, per profile.
const PROFILES = ["round", "chamfer", "pixel", "square"];
const SIZES = [0, 1, 3, 5, 13, 24, 60, 200];
const is_int = pts => pts.every(p => Number.isInteger(p[0]) && Number.isInteger(p[1]));
const axis_aligned = pts => pts.every((p, k) => k === 0 || p[0] === pts[k - 1][0] || p[1] === pts[k - 1][1]);
const monotone = pts => [0, 1].every(a => pts.every((p, k) => k < 2 || Math.sign(p[a] - pts[k - 1][a]) * Math.sign(pts[k - 1][a] - pts[k - 2][a]) >= 0));
const has_repeats = pts => pts.some((p, k) => k > 0 && p[0] === pts[k - 1][0] && p[1] === pts[k - 1][1]);

// The round output is what it was before profiles existed (a digest of the old code's loops, rounded to 1e-6).
cases.push(["round layouts are unchanged by profiles", () => {
  const out = [];
  for (const k of KINDS) for (const e of [0, 5, 13, 24, 60, 200]) {
    const l = D.drawer_layout({ edge: "top", body_length: 400, body_depth: 200, extent: e, radius: 12, fillet: 12, start_kind: k[0], end_kind: k[1], cover: 4 });
    out.push(D.fill_loop(l), D.hole_fill_loop(l), D.outline_path(l), D.stroke_path(l, 1));
  }
  const lay = F.frame_layout(1920, 1080, "top", 30, { corner: "round", radius: 12, thickness: 6 });
  out.push(F.hole_path(lay), F.frame_blocks(lay), F.frame_region(lay));
  return require("crypto").createHash("sha1").update(JSON.stringify(plain(out), (k, v) => typeof v === "number" ? Math.round(v * 1e6) / 1e6 : v)).digest("hex");
}, "88330700b3730de55ae9752fd4b17cc29acc7413"]);

const fit = (kind, r, step) => plain(C.fit(kind, r, step));
cases.push(["fit pixel at r 12 gives 6, 4 and 3 stairs for steps 2, 3 and 4", () => [2, 3, 4].map(s => fit("pixel", 12, s)), [{ radius: 12, step: 2, stairs: 6 }, { radius: 12, step: 3, stairs: 4 }, { radius: 12, step: 4, stairs: 3 }]]);
cases.push(["fit pixel caps the radius at 18 and the stairs at 8", () => [fit("pixel", 30, 2), fit("pixel", 12, 1)], [{ radius: 18, step: 3, stairs: 6 }, { radius: 12, step: 2, stairs: 6 }]]);
cases.push(["fit pixel rounds the radius down to whole steps", () => fit("pixel", 11, 4), { radius: 8, step: 4, stairs: 2 }]);
cases.push(["fit pixel below one step is square, a missing step is 1 px", () => [fit("pixel", 1, 2), fit("pixel", 3, undefined)], [{ radius: 0, step: 0, stairs: 0 }, { radius: 3, step: 1, stairs: 3 }]]);
cases.push(["fit chamfer caps at 12, square is 0, round is untouched", () => [fit("chamfer", 30).radius, fit("chamfer", 7).radius, fit("square", 12).radius, fit("round", 30).radius, fit("nonsense", 9).radius], [12, 7, 0, 30, 9]]);
cases.push(["hypr_color is rgba hex with clamped channels", () => [C.hypr_color({ r: 1, g: 0.5, b: 0, a: 0.8 }), C.hypr_color({ r: 2, g: -1, b: 0, a: 1 })], ["rgba(ff8000cc)", "rgba(ff0000ff)"]]);
cases.push(["hypr_border_color is empty for an invisible colour", () => [C.hypr_border_color({ r: 1, g: 0, b: 0, a: 0 }), C.hypr_border_color({ r: 0, g: 0, b: 0, a: 1 })], ["", "rgba(000000ff)"]]);

for (const step of [2, 3, 4]) for (const r of [12, 18]) {
  const f = C.fit("pixel", r, step);
  const pts = C.corner_points("pixel", f.radius, f.step, f.radius, f.radius, 270, 180);
  cases.push([`pixel stair r ${r} step ${step}: whole pixels, axis-aligned, monotone, ends on the legs`, () => is_int(pts) && axis_aligned(pts) && monotone(pts) && pts.length === 2 * f.stairs + 1
    && pts.every((p, k) => k === 0 || Math.abs(p[0] - pts[k - 1][0]) + Math.abs(p[1] - pts[k - 1][1]) === f.step)
    && near(pts[0], [f.radius, 0], 1e-9) && near(pts[pts.length - 1], [0, f.radius], 1e-9) && pts[1][0] === pts[0][0] && pts[pts.length - 2][1] === pts[pts.length - 1][1], true]);
}
cases.push(["a chamfer is two points at 45 degrees", () => { const p = C.corner_points("chamfer", 12, 0, 12, 12, 270, 180); return [p.length, Math.abs(p[1][0] - p[0][0]) === Math.abs(p[1][1] - p[0][1])]; }, [2, true]]);
cases.push(["a square corner is its one outer point", () => plain(C.corner_points("square", 12, 0, 12, 12, 270, 180)), [[0, 0]]]);

for (const corner of PROFILES) {
  const kit_c = Object.assign({}, kit, { corner: corner, step: 2 });
  for (const [name, bar_edge] of [["top", "top"], ["bottom", "bottom"], ["no bar", ""]]) {
    const lay = F.frame_layout(1920, 1080, bar_edge, 30, kit_c);
    cases.push([`hole ${corner}, ${name}: ends on the straight stretch, loop clean`, () => {
      const path = F.hole_path(lay), loop = F.hole_loop(lay);
      return finite(path) && !self_intersects(loop) && (lay.radius === 0 || (path[0][0] === lay.straight[1] && path[path.length - 1][0] === lay.straight[0] && path[0][1] === lay.near && path[path.length - 1][1] === lay.near)) && !has_repeats(path) && (corner !== "pixel" || (is_int(path) && axis_aligned(path)));
    }, true]);
    cases.push([`frame blocks ${corner}, ${name}: cover the band area the region fills`, () => {
      const area = F.frame_blocks(lay).reduce((a, r) => a + r.w * r.h, 0);
      const region = F.frame_region(lay);
      const want = lay.has_bar ? loop_area(region[0]) : lay.length * lay.depth - loop_area(region[1]);
      // Rows are sampled at their middles: exact for straight profiles, within a sliver for an arc.
      return Math.abs(area - want) < (corner === "round" ? 0.02 * lay.radius * lay.radius * 4 : 1e-6);
    }, true]);
    cases.push([`frame blocks ${corner}, ${name}: disjoint and finite`, () => {
      const b = F.frame_blocks(lay);
      return b.every(r => [r.x, r.y, r.w, r.h].every(Number.isFinite)) && b.every((r, i) => b.every((q, j) => j <= i || r.x + r.w <= q.x + 1e-9 || q.x + q.w <= r.x + 1e-9 || r.y + r.h <= q.y + 1e-9 || q.y + q.h <= r.y + 1e-9));
    }, true]);
  }
  cases.push([`hole radius ${corner}: capped to its profile and the room`, () => [F.frame_layout(1920, 1080, "top", 30, Object.assign({}, kit_c, { radius: 40 })).radius, F.frame_layout(200, 40, "top", 30, kit_c).radius <= 2], [{ round: 40, chamfer: 12, pixel: 18, square: 0 }[corner], true]]);

  for (const [start_kind, end_kind] of KINDS) for (const extent of SIZES) {
    const lay = lay_of({ corner, step: 2, start_kind, end_kind, extent });
    const label = `${corner} ${start_kind}/${end_kind} extent ${extent}`;
    const side = D.hole_side(lay);
    const f = lay.fillet_eff, r = lay.radius_eff, c = lay.cover, far = c + lay.body.d;
    const left = lay.start_room, right = lay.length - lay.end_room;
    cases.push([`joins ${label}: the ends sit on the seam and the band edge`, () => {
      const a = side[0], z = side[side.length - 1];
      const start_ok = start_kind === "pocket" ? a[0] === left && Math.abs(a[1] - (far + f)) < 1e-9 : Math.abs(a[0] - (left - f)) < 1e-9 && a[1] === c;
      const end_ok = end_kind === "pocket" ? z[0] === right && Math.abs(z[1] - (far + f)) < 1e-9 : Math.abs(z[0] - (right + f)) < 1e-9 && z[1] === c;
      return start_ok && end_ok;
    }, true]);
    cases.push([`loops ${label}: finite, closed, no crossing, no repeats, no NaN`, () => {
      const fl = D.fill_loop(lay), hl = D.hole_fill_loop(lay);
      return finite(side) && finite(fl) && finite(hl) && near(fl[0], fl[fl.length - 1], 1e-9) && !self_intersects(fl) && !self_intersects(hl) && !has_repeats(side) && finite(D.stroke_path(lay, 1));
    }, true]);
    cases.push([`profile ${label}: radii follow the profile`, () => corner === "square" ? f === 0 && r === 0 : corner === "pixel" ? (f % lay.fillet_step === 0 || f === 0) && (r % lay.radius_step === 0 || r === 0) : f >= 0 && r >= 0, true]);
    if (corner === "pixel") {
      cases.push([`pixel ${label}: whole pixels, axis-aligned, nothing between two pixels`, () => is_int(side) && axis_aligned(side) && is_int(D.fill_loop(lay)) && is_int(D.hole_fill_loop(lay).filter(p => p[1] !== c - 0.5)), true]);
      if (f > 0 && start_kind === "pocket") cases.push([`pixel ${label}: the pocket's stair leaves the band edge with a step across it`, () => side[0][0] === left && side[1][1] === side[0][1] && side[1][0] > left, true]);
    }
    if (corner === "chamfer") cases.push([`chamfer ${label}: every corner is one straight 45 degree cut`, () => {
      const diagonals = side.slice(1).map((p, k) => [p[0] - side[k][0], p[1] - side[k][1]]).filter(d => d[0] !== 0 && d[1] !== 0);
      const corners = [[start_kind, lay.start_kind], [end_kind, lay.end_kind]].reduce((n, [kind]) => n + (f > 0 ? 1 : 0) + (kind === "fillet" && r > 0 ? 1 : 0), 0);
      return diagonals.length === corners && diagonals.every(d => Math.abs(Math.abs(d[0]) - Math.abs(d[1])) < 1e-9);
    }, true]);
    if (corner === "square") cases.push([`square ${label}: the outline is the plain box, far edge included`, () => {
      const far_run = side.filter(p => p[1] === far);
      return side.every(p => p[0] === left || p[0] === right || p[1] === c || p[1] === far) && D.fill_loop(lay).every(p => Number.isInteger(p[0]) && Number.isInteger(p[1]))
        && (lay.body.d === 0 || (far_run.length >= 2 && far_run[0][0] === left && far_run[far_run.length - 1][0] === right));
    }, true]);
  }
}
// A drawer big enough for its full corners follows each profile's own size, not just a bound.
for (const [corner, want_size, want_step] of [["round", 12, 0], ["chamfer", 12, 0], ["pixel", 12, 2], ["square", 0, 0]]) {
  cases.push([`${corner}: a roomy drawer draws the profile's own radius and fillet`, () => {
    const l = lay_of({ corner, step: 2, radius: 12, fillet: 12 });
    return [l.radius_eff, l.fillet_eff, l.radius_step, l.fillet_step];
  }, [want_size, want_size, want_step, want_step]]);
}
cases.push(["a chamfer drawer asked for more than 12 draws 12; a pixel one rounds to whole steps", () => [lay_of({ corner: "chamfer", radius: 20, fillet: 20 }).fillet_eff, lay_of({ corner: "pixel", step: 4, radius: 18, fillet: 18 }).fillet_eff], [12, 16]]);
cases.push(["profile_fields hands the fitted fillet and the profile, round and zero with no frame", () => [D.profile_fields({ corner: "pixel", radius: 12, step: 4 }), D.profile_fields(null)], [{ radius: 12, fillet: 12, corner: "pixel", step: 4 }, { radius: 0, fillet: 0, corner: "round", step: 0 }]]);
cases.push(["pixel body rounds up to whole pixels", () => { const l = D.drawer_layout(spec({ corner: "pixel", step: 2, body_length: 400.4, body_depth: 200.2, extent: 100.6 })); return [l.body.w, l.body.d, l.length, l.depth]; }, [401, 101, 401 + 2 * 14, cover + 201 + 0]]);
cases.push(["a spec with no corner or step is round", () => [D.drawer_layout(spec({})).corner, D.drawer_layout(spec({ corner: "bogus" })).corner], ["round", "round"]]);
cases.push(["fillet_of fits the profile", () => [D.fillet_of({ corner: "pixel", radius: 12, step: 4 }), D.fillet_of({ corner: "square", radius: 12, step: 2 }), D.fillet_of({ corner: "chamfer", radius: 20, step: 2 })], [12, 0, 12]]);

// Texture phase: whatever the bar's edge, the drawer's edge and the side, the dither and scanlines a drawer tiles from
// texture_phase must fall on the pixels the frame's own tiling (from the canonical origin, mirrored for a bottom bar) does.
cases.push(["phase_wrap is a positive remainder", () => [B.phase_wrap(7, 4), B.phase_wrap(-1, 4), B.phase_wrap(-8, 3), B.phase_wrap(0, 3)], [3, 3, 1, 0]]);
for (const [bar, frame] of [["top", top_frame], ["bottom", bottom_frame]]) {
  for (const from_bottom of [false, true]) {
    for (const side of ["left", "center", "right"]) {
      for (const period of [2, 3]) {
        cases.push([`${bar} bar, drawer from the ${from_bottom ? "bottom" : "top"}, ${side}, period ${period}: dither and scanlines land on the frame's`, () => {
          const hole = F.hole_rect(frame), seam = F.seam_of(frame, from_bottom ? "bottom" : "top");
          const lay = lay_of({ edge: from_bottom ? "bottom" : "top", body_length: 400, extent: 150 });
          const place = D.place(side, from_bottom, hole, seam, 1920, 1080, cover, lay.length);
          const origin = D.texture_origin(side, from_bottom, bar === "bottom", place, 1920, 1080, lay.length);
          const phase = D.texture_phase(origin, period);
          const win_x = side === "right" ? 1920 - place.along - lay.length : place.along;
          const win_y = from_bottom ? 1080 - place.across - lay.depth : place.across;
          const bad = [];
          for (let u = 0; u < lay.length; u += 7) {
            for (let v = 0; v < lay.depth; v++) {
              // The pixel at drawer (u, v) is the screen pixel its centre lands on; the frame's canonical pixel is that, mirrored for a bottom bar.
              const at = apply(D.drawer_affine(lay), [u + 0.5, v + 0.5]);
              const sx = Math.floor(win_x + at[0]), sy = Math.floor(win_y + at[1]);
              const cx = sx, cy = bar === "bottom" ? 1079 - sy : sy;
              const frame_dither = (Math.floor(cx / 2) + Math.floor(cy / 2)) % 2 === 0;
              const frame_line = cy % period === 0;
              const drawer_dither = (Math.floor((u + phase.dither_x) / 2) + Math.floor((v + phase.dither_y) / 2)) % 2 === 0;
              const drawer_line = v >= phase.first_scanline && (v - phase.first_scanline) % period === 0;
              if (frame_dither !== drawer_dither || frame_line !== drawer_line) bad.push([u, v]);
            }
          }
          return bad.length;
        }, 0]);
      }
    }
  }
}
cases.push(["a flipped drawer's dither rows mirror the frame's for every origin row, including those near the screen edge", () => {
  const bad = [];
  for (let y = -3; y < 12; y++) {
    const phase = D.texture_phase({ x: 0, y: y, flipped: true }, 2);
    for (let v = 0; v < 8; v++) {
      const cy = y - v, want = ((Math.floor(cy / 2) % 2) + 2) % 2;
      if ((Math.floor((v + phase.dither_y) / 2)) % 2 !== want) bad.push([y, v]);
    }
  }
  return bad.length;
}, 0]);
{
  const lay = lay_of({ extent: 150 });
  const loop = D.fill_loop(lay);
  const body_mid = lay.cover + lay.body.d / 2;
  cases.push(["fill_row_span: the cover strip is the whole length, a body row is the body, below the fill is empty", () => [
    D.fill_row_span(loop, 0, 2),
    D.fill_row_span(loop, body_mid - 1, body_mid + 1),
    D.fill_row_span(loop, lay.cover + lay.body.d + 4, lay.cover + lay.body.d + 6)
  ], [{ x: 0, w: lay.length }, { x: lay.start_room, w: lay.body.w }, { x: 0, w: 0 }]]);
  cases.push(["fill_row_span: a fillet row is wider than the body, a pocket drawer's row starts at the side band", () => {
    const row = D.fill_row_span(loop, lay.cover + 1, lay.cover + 3);
    const pocket = lay_of({ extent: 150, start_kind: "pocket" });
    const p = D.fill_row_span(D.fill_loop(pocket), pocket.cover + pocket.body.d / 2 - 1, pocket.cover + pocket.body.d / 2 + 1);
    return [row.w > lay.body.w && row.x < lay.start_room, p.x];
  }, [true, 0]]);
}


let failed = 0;
for (const [name, fn, expected] of cases) {
  try {
    assert.deepStrictEqual(plain(fn()), expected);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + "\n  got " + JSON.stringify(plain((() => { try { return fn(); } catch (x) { return String(x); } })())) + "\n  want " + JSON.stringify(expected));
  }
}
if (failed) process.exit(1);
console.log("drawer shapes: " + cases.length + " checks passed");
