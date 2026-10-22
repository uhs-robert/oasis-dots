.pragma library
.import "IslandOutlines.js" as Outlines

// A screen frame: bands round the screen's usable area, joined to the bar's full strip, with a rounded hole for the
// windows. Everything is drawn in the canonical frame, which is the bar's band frame (BandGeometry.js): u runs along
// the bar's edge from 0 to `length`, v away from it from 0 to `depth`; a bottom bar mirrors v, and a screen with no
// bar uses the top bar's frame. The strip owns v from 0 to `near`, the frame's own window everything past it, so the
// two never fill the same pixel.

// The frame's measurements on a screen_w x screen_h screen whose bar (bar_height tall) is on bar_edge, "top",
// "bottom" or "" for none; `kit` is a Style.screen_frame_kits entry. The hole runs from `start` to length - `end`
// along u and from `near` to `far` along v; `straight` is the stretch of its near edge between the corners, which the
// strip's rim draws. `zones` are the exclusive zones per screen edge.
function frame_layout(screen_w, screen_h, bar_edge, bar_height, kit) {
    const has_bar = bar_edge === "top" || bar_edge === "bottom";
    const edge = bar_edge === "bottom" ? "bottom" : "top";
    const t = kit.thickness;
    const near = has_bar ? bar_height : t, far = screen_h - t;
    const start = t, end = t;
    const radius = Math.max(0, Math.min(kit.radius, (screen_w - start - end) / 2, (far - near) / 2));
    const zones = { top: t, right: t, bottom: t, left: t };
    if (has_bar) zones[edge] = bar_height;
    return {
        edge: edge,
        has_bar: has_bar,
        length: screen_w,
        depth: screen_h,
        thickness: t,
        near: near,
        far: far,
        start: start,
        end: end,
        radius: radius,
        corner: kit.corner,
        rim: kit.rim,
        zones: zones,
        straight: [start + radius, screen_w - end - radius]
    };
}

// A hole corner from its horizontal edge to its vertical one, as offsets from the square corner of a top-left
// corner: from [r, 0] to [0, r]. Only "round" so far; the other kinds fall back to it.
function corner_profile(kind, r) {
    if (r <= 0) return [[0, 0]];
    return Outlines.arc(r, r, r, 270, 180);
}

// Drops points that repeat the one before, which would leave a zero-length segment for inset to mitre.
function without_repeats(points) {
    return points.filter((p, k) => k === 0 || Math.abs(p[0] - points[k - 1][0]) > 1e-9 || Math.abs(p[1] - points[k - 1][1]) > 1e-9);
}

// The hole's outline without the straight part of its near edge: from that part's far end (length - end - radius)
// round the far side to its near end (start + radius). Travel keeps the hole on the right, so IslandOutlines.inset
// moves it out into the bands.
function hole_path(lay) {
    const p = corner_profile(lay.corner, lay.radius);
    const left = lay.start, right = lay.length - lay.end;
    const reversed = p.slice().reverse();
    return without_repeats([].concat(
        p.map(q => [right - q[0], lay.near + q[1]]),
        reversed.map(q => [right - q[0], lay.far - q[1]]),
        p.map(q => [left + q[0], lay.far - q[1]]),
        reversed.map(q => [left + q[0], lay.near + q[1]])
    ));
}

// The hole as a closed loop.
function hole_loop(lay) {
    const path = hole_path(lay);
    return path.concat([path[0]]);
}

// The frame window's fill as closed loops for one OddEvenFill PathMultiline: with a bar, the U past the strip (one
// loop, open along the straight stretch where the strip takes over); without one, the screen minus the hole.
function frame_region(lay) {
    const w = lay.length, h = lay.depth;
    if (!lay.has_bar) return [[[0, 0], [w, 0], [w, h], [0, h], [0, 0]], hole_loop(lay)];
    return [[[0, lay.near], [0, h], [w, h], [w, lay.near]].concat(hole_path(lay), [[0, lay.near]])];
}

// A line round the hole d px out into the bands (a rim at its half width, the inset line at its gap). With a bar both
// windows draw it with complementary clips, the frame window below `near` and the strip above it, and the strip's own
// rim draws the straight stretch; without one the frame window draws the whole loop.
function frame_stroke(lay, d) {
    return Outlines.inset(lay.has_bar ? hole_path(lay) : hole_loop(lay), d);
}

// Where a corner's band edge sits in a row at local height y (0 to r): how far the band reaches in from the hole's side.
function profile_x(profile, y) {
    for (let k = 0; k + 1 < profile.length; k++) {
        const a = profile[k], b = profile[k + 1];
        if (y >= a[1] && y <= b[1] && b[1] > a[1]) return a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]);
    }
    return y <= 0 ? profile[0][0] : 0;
}

// The frame window's fill as disjoint rectangles { x, y, w, h }, for effects that clip to rectangles (dither,
// scanlines): the bands whole, and the band side of each corner in 2 px rows taken at their middles.
function frame_blocks(lay) {
    const w = lay.length, h = lay.depth, r = lay.radius;
    const left = lay.start, right = w - lay.end;
    const out = [
        { x: 0, y: lay.near, w: left, h: h - lay.near },
        { x: right, y: lay.near, w: w - right, h: h - lay.near },
        { x: left, y: lay.far, w: right - left, h: h - lay.far }
    ];
    if (!lay.has_bar) out.push({ x: 0, y: 0, w: w, h: lay.near });
    const profile = corner_profile(lay.corner, r);
    for (let y0 = 0; y0 < r; y0 += 2) {
        const y1 = Math.min(r, y0 + 2), reach = profile_x(profile, (y0 + y1) / 2);
        if (reach <= 0) continue;
        out.push({ x: left, y: lay.near + y0, w: reach, h: y1 - y0 },
            { x: right - reach, y: lay.near + y0, w: reach, h: y1 - y0 },
            { x: left, y: lay.far - y1, w: reach, h: y1 - y0 },
            { x: right - reach, y: lay.far - y1, w: reach, h: y1 - y0 });
    }
    return out.filter(b => b.w > 0 && b.h > 0);
}

// The canonical frame on the screen, as the affine [a, b, c, d, tx, ty] BandGeometry.band_affine uses.
function to_screen(lay) {
    return lay.edge === "bottom" ? [1, 0, 0, -1, 0, lay.depth] : [1, 0, 0, 1, 0, 0];
}

// The hole as a screen rect { x, y, w, h }, for placing surfaces that attach to it (drawers).
function hole_rect(lay) {
    const h = lay.far - lay.near;
    return { x: lay.start, y: lay.edge === "bottom" ? lay.depth - lay.far : lay.near, w: lay.length - lay.start - lay.end, h: h };
}

// The screen coordinate of the hole's edge on `edge` ("top", "bottom", "left" or "right"): y for the first two, x for
// the others. With a bottom bar the hole's bar side is its bottom edge.
function seam_of(lay, edge) {
    const r = hole_rect(lay);
    switch (edge) {
    case "bottom": return r.y + r.h;
    case "left": return r.x;
    case "right": return r.x + r.w;
    }
    return r.y;
}
