// Runs DrawerGeometry.js and FrameGeometry's hole_rect/seam_of under node: the drawer's layout, fill, outline and
// placement on every edge, and that its rim lands where the screen frame's own line is.
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
const F = load("features/bar/FrameGeometry.js", { Outlines: O });
const D = load("features/bar/DrawerGeometry.js", { Outlines: O, Band: B });
const plain = v => JSON.parse(JSON.stringify(v));

const kit = { corner: "round", radius: 12, thickness: 6, rim: 0, ornament: "" };
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
  const length = 400 + (start_kind === "pocket" ? cover : 12) + (end_kind === "pocket" ? cover : 12);
  const depth = cover + 200 + (pockets ? 12 : 0);
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
cases.push(["body_rect top", () => rect_of("top"), { x: 12, y: cover, width: 400, height: 200 }]);
cases.push(["body_rect bottom", () => rect_of("bottom"), { x: 12, y: 0, width: 400, height: 200 }]);
cases.push(["body_rect left", () => rect_of("left"), { x: cover, y: 12, width: 200, height: 400 }]);
cases.push(["body_rect right", () => rect_of("right"), { x: 0, y: 12, width: 200, height: 400 }]);
cases.push(["body_rect follows the extent", () => rect_of("top", { extent: 80 }), { x: 12, y: cover, width: 400, height: 80 }]);
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
