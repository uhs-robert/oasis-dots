.pragma library
.import "IslandOutlines.js" as Outlines
.import "Corners.js" as Corners

// A screen frame: bands round the screen's usable area, joined to the bars' full strips, with a rounded hole for the
// windows. Everything is drawn in the canonical frame, which is the band frame (BandGeometry.js) of the bar on its
// `edge`: u runs along that edge from 0 to `length`, v away from it from 0 to `depth`. A lone bottom bar mirrors v; a
// top bar, two bars or none use the top bar's frame. The near strip owns v from 0 to `near` and a far strip (a second
// bar on the opposite edge) v from `far` to `depth`; the frame's own window draws everything between, so no two
// windows fill the same pixel.

// The frame's measurements on a screen_w x screen_h screen. `bar_edges` is { top, bottom }: each the thickness of the
// bar strip on that screen edge, 0 (or absent) where the edge has no bar. It lists every bar strip on the screen, so
// whatever draws over the frame (music mode) skips exactly these; the layout carries it on as `bar_edges` with both
// keys set. `kit` is Style.plain_frame_kit with the style's corner profile laid over it (Style.screen_frame_profile:
// corner, radius, step). The hole runs from `start` to length - `end` along u and from `near` to `far` along v;
// `straight` is the stretch of its near (and far) edge between the corners, which a strip's rim draws. `has_bar` and
// `far_bar` say which of the two edges carry a strip; a far strip never comes without a near one. `zones` are the
// exclusive zones per screen edge.
function frame_layout(screen_w, screen_h, bar_edges, kit) {
    const strip = name => Math.max(0, Number(bar_edges && bar_edges[name]) || 0);
    const edges = { top: strip("top"), bottom: strip("bottom") };
    const edge = edges.top === 0 && edges.bottom > 0 ? "bottom" : "top";
    const other = edge === "top" ? "bottom" : "top";
    const has_bar = edges[edge] > 0, far_bar = edges[other] > 0;
    const t = kit.thickness;
    const near = has_bar ? edges[edge] : t, far = screen_h - (far_bar ? edges[other] : t);
    const start = t, end = t;
    const room = Math.max(0, Math.min(kit.radius, (screen_w - start - end) / 2, (far - near) / 2));
    const fitted = Corners.fit(kit.corner, room, kit.step);
    const zones = { top: edges.top || t, right: t, bottom: edges.bottom || t, left: t };
    return {
        edge: edge,
        has_bar: has_bar,
        far_bar: far_bar,
        bar_edges: edges,
        length: screen_w,
        depth: screen_h,
        thickness: t,
        near: near,
        overlap: has_bar ? (kit.fill_overlap === undefined ? default_fill_overlap : kit.fill_overlap) : 0,
        far: far,
        start: start,
        end: end,
        radius: fitted.radius,
        corner: kit.corner,
        step: fitted.step,
        zones: zones,
        straight: [start + fitted.radius, screen_w - end - fitted.radius]
    };
}

// The same frame drawn from the bar on `edge`, so that bar's strip is the near one: what a far strip's own window
// draws its part of the frame's line in. A layout already on `edge`, or an edge with no bar, comes back as it is.
function seen_from(lay, edge) {
    if (lay.edge === edge || !(lay.bar_edges[edge] > 0)) return lay;
    return Object.assign({}, lay, { edge: edge, has_bar: lay.far_bar, far_bar: lay.has_bar, near: lay.depth - lay.far, far: lay.depth - lay.near });
}

// A hole corner from its horizontal edge to its vertical one, as offsets from the square corner of a top-left
// corner: from [r, 0] to [0, r]. `r` and `step` come fit() from frame_layout.
function corner_profile(kind, r, step) {
    if (r <= 0) return [[0, 0]];
    return Corners.corner_points(kind, r, step, r, r, 270, 180);
}

// Drops points that repeat the one before, which would leave a zero-length segment for inset to mitre.
function without_repeats(points) {
    return points.filter((p, k) => k === 0 || Math.abs(p[0] - points[k - 1][0]) > 1e-9 || Math.abs(p[1] - points[k - 1][1]) > 1e-9);
}

// The hole's corners in loop order, each from its horizontal edge to its vertical one or back: near right, far right,
// far left, near left. Travel keeps the hole on the right, so IslandOutlines.inset moves a line out into the bands.
function hole_corners(lay) {
    const p = corner_profile(lay.corner, lay.radius, lay.step);
    const left = lay.start, right = lay.length - lay.end;
    const reversed = p.slice().reverse();
    return [
        p.map(q => [right - q[0], lay.near + q[1]]),
        reversed.map(q => [right - q[0], lay.far - q[1]]),
        p.map(q => [left + q[0], lay.far - q[1]]),
        reversed.map(q => [left + q[0], lay.near + q[1]])
    ];
}

// The hole's outline without the straight part of its near edge: from that part's far end (length - end - radius)
// round the far side to its near end (start + radius).
function hole_path(lay) {
    return without_repeats([].concat(...hole_corners(lay)));
}

// The hole's outline less the straight stretches the strips draw, as open paths: one round the far side with a near
// strip only, the right side and the left side with a far strip too. Each starts and ends on a strip's edge.
function hole_pieces(lay) {
    if (!lay.far_bar) return [hole_path(lay)];
    const c = hole_corners(lay);
    return [without_repeats(c[0].concat(c[1])), without_repeats(c[2].concat(c[3]))];
}

// The hole as a closed loop.
function hole_loop(lay) {
    const path = hole_path(lay);
    return path.concat([path[0]]);
}

// How far the frame window's fill reaches up under the strip when the kit does not say (`fill_overlap`). At a fractional
// scale the strip's edge at `near` lands mid-pixel and neither surface fully covers that pixel row; 1 px is at least a
// whole physical pixel at any scale >= 1. Translucent islands pass 0: the overlap would be filled twice and show darker.
const default_fill_overlap = 1;

// The frame window's fill as closed loops for one OddEvenFill PathMultiline. With a near strip only, the U past it (one
// loop, open along the straight stretch where the strip takes over; its top edge reaches `overlap` under the strip).
// With a far strip too, the two side bands, each reaching `overlap` under both strips. Without a bar, the screen minus
// the hole.
function frame_region(lay) {
    const w = lay.length, h = lay.depth;
    if (!lay.has_bar) return [[[0, 0], [w, 0], [w, h], [0, h], [0, 0]], hole_loop(lay)];
    const top = lay.near - lay.overlap;
    if (!lay.far_bar) {
        const path = hole_path(lay), first = path[0], last = path[path.length - 1];
        return [without_repeats([[0, top], [0, h], [w, h], [w, top], [first[0], top]].concat(path, [[last[0], top], [0, top]]))];
    }
    const bottom = lay.far + lay.overlap, pieces = hole_pieces(lay), right = pieces[0], left = pieces[1];
    return [
        without_repeats([[w, top], [right[0][0], top]].concat(right, [[right[right.length - 1][0], bottom], [w, bottom], [w, top]])),
        without_repeats([[0, bottom], [left[0][0], bottom]].concat(left, [[left[left.length - 1][0], top], [0, top], [0, bottom]]))
    ];
}

// Where the frame window's own stroke clip starts. The frame window may stack above the strip, and then its fill's
// overlap row hides the strip's half of the corner's rim and inset line unless it draws them again itself, so the clip
// starts 1 px above the fill: a clip snaps to whole device pixels, and at a fractional scale the fill's top edge lands
// mid-pixel. With no overlap it stays at `near`, so a translucent rim is never drawn twice.
function stroke_clip_top(lay) {
    return lay.overlap > 0 ? lay.near - lay.overlap - 1 : lay.near;
}

// Where it ends: as stroke_clip_top, mirrored at a far strip, else the screen's far edge.
function stroke_clip_bottom(lay) {
    if (!lay.far_bar) return lay.depth;
    return lay.overlap > 0 ? lay.far + lay.overlap + 1 : lay.far;
}

// The lines round the hole d px out into the bands (a rim at its half width, the inset line at its gap), one polyline
// per hole_pieces path. With a bar the frame window and the strips draw them with complementary clips, the frame window
// between stroke_clip_top and stroke_clip_bottom and each strip past its own edge, and the strips' own rims draw the
// straight stretches; without one the frame window draws the whole loop.
function frame_strokes(lay, d) {
    if (!lay.has_bar) return [Outlines.inset(hole_loop(lay), d)];
    // Lead-ins of d along the strip's edge make inset mitre each open end onto the straight stretch's line (d out, in
    // the strip) rather than cut it square at the edge. Each lead-in is then cut back to end exactly where the strip's
    // line starts (the straight stretch's end): without it the stroke's end cap is square to the corner's last segment
    // and leaves a notch before the strip's line; at full length it draws over that line (a translucent rim shows it).
    // An open end on the right half leads in from the left and the other way round.
    const middle = lay.length / 2, lead = p => [p[0] + (p[0] > middle ? -d : d), p[1]];
    return hole_pieces(lay).map(path => {
        const first = path[0], last = path[path.length - 1];
        const stroke = Outlines.inset([lead(first)].concat(path, [lead(last)]), d);
        stroke[0][0] = first[0];
        stroke[stroke.length - 1][0] = last[0];
        return stroke;
    });
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
// scanlines): the bands whole, and the band side of each corner in 2 px rows taken at their middles (a stair's own
// step tall, so a row never straddles two stairs).
function frame_blocks(lay) {
    const w = lay.length, h = lay.depth, r = lay.radius;
    const left = lay.start, right = w - lay.end;
    const top = lay.near - lay.overlap, bottom = lay.far_bar ? lay.far + lay.overlap : h;
    const out = [
        { x: 0, y: top, w: left, h: bottom - top },
        { x: right, y: top, w: w - right, h: bottom - top }
    ];
    if (!lay.far_bar) out.push({ x: left, y: lay.far, w: right - left, h: h - lay.far });
    if (lay.has_bar) out.push({ x: left, y: top, w: lay.straight[0] - left, h: lay.overlap }, { x: lay.straight[1], y: top, w: right - lay.straight[1], h: lay.overlap });
    else out.push({ x: 0, y: 0, w: w, h: lay.near });
    if (lay.far_bar) out.push({ x: left, y: lay.far, w: lay.straight[0] - left, h: lay.overlap }, { x: lay.straight[1], y: lay.far, w: right - lay.straight[1], h: lay.overlap });
    const profile = corner_profile(lay.corner, r, lay.step);
    const row = lay.corner === "pixel" && lay.step > 0 ? lay.step : 2;
    for (let y0 = 0; y0 < r; y0 += row) {
        const y1 = Math.min(r, y0 + row), reach = profile_x(profile, (y0 + y1) / 2);
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

// A screen rect { x, y, w, h } in the canonical frame (to_screen is its own inverse).
function to_canonical_rect(lay, r) {
    return lay.edge === "bottom" ? { x: r.x, y: lay.depth - r.y - r.h, w: r.w, h: r.h } : { x: r.x, y: r.y, w: r.w, h: r.h };
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

// The translucent drawers' windows, as { screen_name: { popup_key: rect } }. Each popup sets and clears only its own key,
// so a popup closing never clears the one that replaced it on the screen. Both return a new registry (the old one is
// left alone) that shares every other screen's entry.
function drawer_windows_with(reg, screen_name, key, rect) {
    const screen = Object.assign({}, reg[screen_name]);
    if (rect) screen[key] = rect;
    else delete screen[key];
    const next = Object.assign({}, reg);
    if (Object.keys(screen).length > 0) next[screen_name] = screen;
    else delete next[screen_name];
    return next;
}

// A screen's drawer windows as screen rects, in the order they were published.
function drawer_window_rects(reg, screen_name) {
    return Object.values(reg[screen_name] || {});
}

// The margin a popup or tooltip keeps from the `edge` ("left"/"right") screen side: the floating strip's side inset when
// it hangs from that side's island (`popup_side`), else none.
function side_popup_inset(strip_side, popup_side, edge) {
    return popup_side === edge ? strip_side : 0;
}

// The strip's line gaps (strip-local, x and w only) for the drawer windows that reach the strip's band: a bottom-docked
// drawer under a top bar leaves the strip's lines whole. screen_h is 0 without a frame, where nothing says which edge a
// window sits on, so every window counts.
function strip_gaps(rects, edge, thickness, screen_h) {
    return rects
        .filter(r => screen_h <= 0 || (edge === "bottom" ? r.y + r.h > screen_h - thickness : r.y < thickness))
        .map(r => ({ x: r.x, y: 0, w: r.w, h: thickness }));
}
