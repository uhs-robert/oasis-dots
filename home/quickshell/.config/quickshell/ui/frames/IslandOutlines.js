.pragma library

// The island shapes Island.qml draws as one outline: a fill polygon, a rim traced inside it and the fill's span
// at a height, all from each open end's profile. Everything is in the top-bar frame (y = 0 on the screen edge,
// y = h on the open edge); Island mirrors the drawing under a bottom bar.

const names = ["chevron", "lean", "hex", "ticket", "tab", "pixel", "notch", "rect"];

function has(shape) {
    return names.indexOf(shape) >= 0;
}

// Shapes with no plate: `none` draws nothing, `underline` and `brackets` only a stroke. `has` stays false for them,
// since an outline here is a filled polygon.
const stroke_names = ["none", "underline", "brackets"];

function stroke_only(shape) {
    return stroke_names.indexOf(shape) >= 0;
}

// Points per quarter circle; enough that the antialiased polygon reads as a curve at bar sizes.
const ARC_STEPS = 10;

function pixel_step(h) {
    return Math.max(2, Math.round(h / 12));
}

const PIXEL_STEPS = 3;

// The share of the height the hex's flat tip takes. A cut under a quarter vanishes into the rim at 1x.
const HEX_FLAT = 0.3;

function notch_flare(h) {
    return Math.round(h * 0.2);
}

// How far each open end reaches in from the island's side: the content starts past it.
function cap_width(shape, h) {
    switch (shape) {
    // No outline to clear, so a pad that keeps the modules off the bare edge (the brackets' arm plus a gap).
    case "none":
    case "underline": return Math.round(h * 0.3);
    case "brackets": return bracket_arm(h) + Math.round(h * 0.1);
    case "chevron": return Math.round(h * 0.5);
    case "round": return Math.round(h * 0.3);
    // The hexagon's 120 degree corners, their tip cut flat: the slanted edge reaches (1 - HEX_FLAT) / 2 * h / tan(60) in.
    case "hex": return Math.round(h * (1 - HEX_FLAT) / 2 / Math.tan(Math.PI / 3));
    case "lean": return Math.round(h * 0.4);
    case "ticket": return Math.round(h * 0.27);
    case "tab": return Math.round(h * 0.4);
    case "pixel": return pixel_step(h) * PIXEL_STEPS;
    case "notch": return notch_flare(h) + Math.round(h * 0.33);
    case "rect": return Math.round(h * 0.3);
    }
    return 0;
}

function bracket_arm(h) {
    return Math.max(4, Math.round(h * 0.3));
}

// The underline as an open polyline along the open edge (y = h), `t` thick, centred so the stroke lies inside the island.
function underline_path(w, h, t) {
    return [[0, h - t / 2], [w, h - t / 2]];
}

// The four corner brackets as 3-point polylines with arms `arm` long, inset by half of `t` so the stroke lies inside the box.
function bracket_paths(w, h, arm, t) {
    const i = t / 2;
    return [
        [[i, i + arm], [i, i], [i + arm, i]],
        [[w - i - arm, i], [w - i, i], [w - i, i + arm]],
        [[w - i, h - i - arm], [w - i, h - i], [w - i - arm, h - i]],
        [[i + arm, h - i], [i, h - i], [i, h - i - arm]]
    ];
}

// Points on the circle around (cx, cy) from angle a0 to a1 in degrees, y down.
function arc(cx, cy, r, a0, a1) {
    const out = [];
    for (let k = 0; k <= ARC_STEPS; k++) {
        const a = (a0 + (a1 - a0) * k / ARC_STEPS) * Math.PI / 180;
        out.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
    }
    return out;
}

// An open end's outline from the screen edge (y = 0) to the open edge (y = h), as [inset from the island's side, y].
// `trailing` is the right end, which mirrors the left one except on the lean, whose ends run parallel.
function end_profile(shape, h, c, trailing) {
    switch (shape) {
    // Both corners rounded, for the floating strip's plate; not an island shape, so `names` leaves it out.
    case "round":
        return arc(c, c, c, -90, -180).concat(arc(c, h - c, c, 180, 90));
    case "chevron":
        return [[c, 0], [0, h / 2], [c, h]];
    case "hex":
        return [[c, 0], [0, h * (1 - HEX_FLAT) / 2], [0, h * (1 + HEX_FLAT) / 2], [c, h]];
    case "lean":
        return trailing ? [[0, 0], [c, h]] : [[c, 0], [0, h]];
    // Concave quarter circles cut into all four corners of the end.
    case "ticket":
        return arc(0, 0, c, 0, 90).concat(arc(0, h, c, -90, 0));
    // Square where it hangs from the screen edge, rounded at the open edge.
    case "tab":
        return [[0, 0]].concat(arc(c, h - c, c, 180, 90));
    // A concave flare where it meets the screen edge, then a convex corner at the open edge.
    case "notch": {
        const f = notch_flare(h), r = c - f;
        return arc(0, f, f, -90, 0).concat(arc(f + r, h - r, r, 180, 90));
    }
    // A 45 degree staircase in whole steps at each corner.
    case "pixel": {
        const s = pixel_step(h), top = [];
        for (let k = PIXEL_STEPS; k > 0; k--) top.push([k * s, (PIXEL_STEPS - k) * s], [k * s, (PIXEL_STEPS - k + 1) * s]);
        top.push([0, PIXEL_STEPS * s]);
        return top.concat(top.map(p => [p[0], h - p[1]]).reverse());
    }
    }
    return [[0, 0], [0, h]];
}

// The outline minus the screen edge, as [x, y] from the left end round the open edge to the right end. An end
// without a cap meets the screen's side, which is left open like the screen edge.
function rim_path(shape, w, h, c, cap_left, cap_right) {
    const left = cap_left ? end_profile(shape, h, c, false) : [[0, h]];
    const right = cap_right ? end_profile(shape, h, c, true).map(p => [w - p[0], p[1]]).reverse() : [[w, h]];
    return left.concat(right);
}

// The closed fill: the rim path, then back along the screen edge (and the screen's sides for uncapped ends).
function fill_path(path, w, cap_left, cap_right) {
    // A Loader's component still binds for a moment after the shape changes away, with an empty rim.
    if (path.length === 0) return [];
    const out = path.slice();
    if (!cap_right) out.push([w, 0]);
    if (!cap_left) out.push([0, 0]);
    out.push(path[0]);
    return out;
}

// `path` moved d px inward (to the left of travel, y down), each corner mitred so every segment stays parallel.
// An end that leaves the screen edge steeply slides along its segment back onto that edge, so the rim reaches it;
// a near-tangent one (the notch's flare) keeps the plain offset, which would otherwise slide far past the end.
function inset(path, d) {
    const n = path.length;
    const dirs = [];
    for (let k = 0; k + 1 < n; k++) {
        const dx = path[k + 1][0] - path[k][0], dy = path[k + 1][1] - path[k][1], len = Math.hypot(dx, dy) || 1;
        dirs.push([dx / len, dy / len]);
    }
    const normal = u => [u[1], -u[0]];
    const out = [];
    for (let k = 0; k < n; k++) {
        const a = dirs[Math.max(0, k - 1)], b = dirs[Math.min(dirs.length - 1, k)];
        const na = normal(a), nb = normal(b);
        const mitre = d / (1 + na[0] * nb[0] + na[1] * nb[1]);
        let x = path[k][0] + (na[0] + nb[0]) * mitre, y = path[k][1] + (na[1] + nb[1]) * mitre;
        const end = k === 0 || k === n - 1;
        if (end && Math.abs(b[1]) >= Math.abs(b[0]) && Math.abs(a[1]) >= Math.abs(a[0])) {
            const u = k === 0 ? b : a, t = (path[k][1] - y) / u[1];
            x += u[0] * t;
            y = path[k][1];
        }
        out.push([x, y]);
    }
    return out;
}

// The closed outline `path` (its last point joins its first) moved d px inward, every corner mitred; `inset` leaves a
// path's two ends open to the screen edge, which a plate set in from it has no use for.
function inset_ring(path, d) {
    const n = path.length;
    const normal = k => {
        const a = path[k], b = path[(k + 1) % n], len = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
        return [(b[1] - a[1]) / len, -(b[0] - a[0]) / len];
    };
    return path.map((p, k) => {
        const na = normal((k + n - 1) % n), nb = normal(k);
        const mitre = d / (1 + na[0] * nb[0] + na[1] * nb[1]);
        return [p[0] + (na[0] + nb[0]) * mitre, p[1] + (na[1] + nb[1]) * mitre];
    });
}

// The left and right x where the row at y crosses `inner` (an inset rim path) closed above the screen edge; [0, 0]
// past its open edge.
function span_at(inner, y) {
    const first = inner[0], last = inner[inner.length - 1];
    const ring = inner.concat([[last[0], -1], [first[0], -1], first]);
    let lo = Infinity, hi = -Infinity;
    for (let k = 0; k + 1 < ring.length; k++) {
        const p = ring[k], q = ring[k + 1];
        if (p[1] === q[1] || y < Math.min(p[1], q[1]) || y >= Math.max(p[1], q[1])) continue;
        const x = p[0] + (q[0] - p[0]) * (y - p[1]) / (q[1] - p[1]);
        lo = Math.min(lo, x);
        hi = Math.max(hi, x);
    }
    return lo < hi ? [lo, hi] : [0, 0];
}
