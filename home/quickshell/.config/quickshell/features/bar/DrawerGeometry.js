.pragma library
.import "IslandOutlines.js" as Outlines
.import "BandGeometry.js" as Band
.import "Corners.js" as Corners

// A drawer: a surface that grows out of a screen frame's edge (FrameGeometry.js) and joins it with a concave fillet
// at each end, drawn in the surface's own window. It is drawn in a band frame like BandGeometry's: u runs along the
// attached edge from 0 to `length`, v away from the window's attached edge from 0 to `depth`. The window's edge sits
// `cover` px out in the band, so the seam (the hole's edge) is at v = cover; band_affine places the frame on any edge.
//
// Each end of the attached side is a "fillet", where the drawer hangs from the band along the edge and meets it with a
// concave arc, or a "pocket", where the drawer sits in a hole corner: it fills the corner square, runs flush down the
// side band, and the concave arc is where its far edge meets that band.
//
// The surface is as big as the drawer will ever be; only the shape follows `extent`, the visible depth. At extent 0 the
// drawer is the cover strip, which looks the same as the band, so it needs nothing from the frame's window.

// How far a drawer paints into the band to hide the frame's rim and inset line along its mouth; the extra pixel
// absorbs fractional-scale rounding.
function cover_depth(rim_width, inset_gap, inset_width) {
    return Math.ceil(Math.max(rim_width, inset_gap + inset_width)) + 1;
}

// How far the rim runs on past each fillet along the frame's own line, so a window a fraction of a pixel off reads as
// a slightly fuller line, not a break.
const LEAD = 2;

// spec: { edge, body_length, body_depth, extent, radius, fillet, start_kind, end_kind, cover, corner, step }. `radius`
// rounds the body's free corners and `fillet` the concave arcs; both shrink with the extent and the body's width, so
// nothing inverts and a pocket's two arcs never cross. `corner` is the profile of both (Corners.js, "round" when
// missing) and `step` the pixel profile's stair step; a spec without them draws round corners, as before them.
function drawer_layout(spec) {
    const corner = Corners.valid(spec.corner);
    // A pixel drawer keeps every join on a whole pixel: the body rounds up (never smaller than its content) and the
    // extent to the nearest pixel, so a stair never lands between two.
    const whole = v => corner === "pixel" ? Math.ceil(v) : v;
    const body_length = whole(spec.body_length), body_depth = whole(spec.body_depth);
    const extent = Math.max(0, Math.min(corner === "pixel" ? Math.round(spec.extent) : spec.extent, body_depth));
    // The fillet's full size is what the window reserves; the one drawn shrinks with the extent.
    const fillet_full = Corners.fit(corner, spec.fillet, spec.step).radius;
    const fillet_fit = Corners.fit(corner, Math.min(fillet_full, extent / 2, body_length / 2), spec.step);
    const radius_fit = Corners.fit(corner, Math.min(spec.radius, extent / 2, body_length / 2), spec.step);
    // A fillet end also reserves the LEAD its outline runs on along the frame's line; a pocket reserves its own in `depth`.
    const start_room = spec.start_kind === "pocket" ? spec.cover : fillet_full + LEAD;
    const end_room = spec.end_kind === "pocket" ? spec.cover : fillet_full + LEAD;
    const any_pocket = spec.start_kind === "pocket" || spec.end_kind === "pocket";
    const length = start_room + body_length + end_room;
    // A pocket's outline runs LEAD px on down the side band past its arc, so the window reserves that too.
    const pocket_room = any_pocket ? fillet_full + LEAD : 0;
    const depth = spec.cover + body_depth + pocket_room;
    const vertical = spec.edge === "left" || spec.edge === "right";
    return {
        edge: spec.edge,
        length: length,
        depth: depth,
        // How deep the shape has drawn so far; `depth` is the window's, which stays at the popup's full reserve.
        drawn_depth: spec.cover + extent + pocket_room,
        cover: spec.cover,
        corner: corner,
        radius_eff: radius_fit.radius,
        radius_step: radius_fit.step,
        fillet_eff: fillet_fit.radius,
        fillet_step: fillet_fit.step,
        start_kind: spec.start_kind,
        end_kind: spec.end_kind,
        start_room: start_room,
        end_room: end_room,
        body: { u: start_room, v: spec.cover, w: body_length, d: extent },
        surface: vertical ? { width: depth, height: length } : { width: length, height: depth }
    };
}

// The fillet a frame's corner profile ({ corner, radius, step }, Style.screen_frame_profile) draws at full size, which
// body_length makes room for.
function fillet_of(profile) {
    return Corners.fit(profile.corner, profile.radius, profile.step).radius;
}

// Drops points that repeat the one before, which would leave a zero-length segment for inset to mitre.
function without_repeats(points) {
    return points.filter((p, k) => k === 0 || Math.abs(p[0] - points[k - 1][0]) > 1e-9 || Math.abs(p[1] - points[k - 1][1]) > 1e-9);
}

// The material's edge against the hole, from the start end's fillet to the end's, travelling with the hole on the
// right (as FrameGeometry.hole_path, so Outlines.inset moves a line into the material). Fillet ends start and finish
// on the seam; pocket ends on the far edge's side of the side band, below the fillet.
function hole_side(lay) {
    const c = lay.cover, f = lay.fillet_eff, r = lay.radius_eff, far = c + lay.body.d;
    const left = lay.start_room, right = lay.length - lay.end_room;
    const k = lay.corner, fs = lay.fillet_step, rs = lay.radius_step;
    const start = lay.start_kind === "pocket"
        ? Corners.corner_points(k, f, fs, left + f, far + f, 180, 270)
        : [].concat(Corners.corner_points(k, f, fs, left - f, c + f, 270, 360), Corners.corner_points(k, r, rs, left + r, far - r, 180, 90));
    const end = lay.end_kind === "pocket"
        ? Corners.corner_points(k, f, fs, right - f, far + f, 270, 360)
        : [].concat(Corners.corner_points(k, r, rs, right - r, far - r, 90, 0), Corners.corner_points(k, f, fs, right + f, c + f, 180, 270));
    return without_repeats(start.concat(end));
}

// The drawer's fill as one closed loop: the cover strip, the fillets and the body.
function fill_loop(lay) {
    const c = lay.cover, f = lay.fillet_eff, far = c + lay.body.d;
    const first = lay.start_kind === "pocket" ? [0, far + f] : [0, c];
    const last = lay.end_kind === "pocket" ? [lay.length, far + f] : [lay.length, c];
    return without_repeats([[0, 0], first].concat(hole_side(lay), [last, [lay.length, 0], [0, 0]]));
}

// The fill for a translucent drawer: only what lies in the hole, so it never stacks on the translucent frame under the
// cover strip and a pocket's column. It starts SEAM_OVERLAP px into the band so a fractional seam leaves no hairline.
const SEAM_OVERLAP = 0.5;
function hole_fill_loop(lay) {
    const c = lay.cover, f = lay.fillet_eff, far = c + lay.body.d, top = c - SEAM_OVERLAP;
    const hole = hole_side(lay);
    const first = lay.start_kind === "pocket" ? [[lay.start_room, top], [lay.start_room, far + f]] : [[hole[0][0], top]];
    const last = lay.end_kind === "pocket" ? [[lay.length - lay.end_room, far + f], [lay.length - lay.end_room, top]] : [[hole[hole.length - 1][0], top]];
    return without_repeats(first.concat(hole, last, [first[0]]));
}

// The line round the material against the hole, open on the attached side. It runs LEAD px on past each end along the
// frame's own line, so it overlaps that line's rim.
function outline_path(lay) {
    const c = lay.cover, f = lay.fillet_eff, far = c + lay.body.d;
    const left = lay.start_room, right = lay.length - lay.end_room;
    const first = lay.start_kind === "pocket" ? [left, far + f + LEAD] : [left - f - LEAD, c];
    const last = lay.end_kind === "pocket" ? [right, far + f + LEAD] : [right + f + LEAD, c];
    return without_repeats([first].concat(hole_side(lay), [last]));
}

// A line d px into the material from the outline (the rim at half its width, the inset line at its gap), as
// FrameGeometry.frame_stroke moves the hole's outline into the bands.
function stroke_path(lay, d) {
    return Outlines.inset(outline_path(lay), d);
}

// The frame as the affine [a, b, c, d, tx, ty] taking a drawer point (u, v) to (a u + c v + tx, b u + d v + ty) in the
// window.
function drawer_affine(lay) {
    return Band.band_affine(lay.edge, lay.depth);
}

// The body in window coordinates as { x, y, width, height }. It leaves out the cover strip and the fillets.
function body_rect(lay) {
    const m = drawer_affine(lay), b = lay.body;
    const at = (u, v) => [m[0] * u + m[2] * v + m[4], m[1] * u + m[3] * v + m[5]];
    const p = at(b.u, b.v), q = at(b.u + b.w, b.v + b.d);
    return { x: Math.min(p[0], q[0]), y: Math.min(p[1], q[1]), width: Math.abs(q[0] - p[0]), height: Math.abs(q[1] - p[1]) };
}

// Where clicks land: the body, so the band and the transparent fillet corners pass them through.
function input_rect(lay) {
    return body_rect(lay);
}

// The body's length: the popup's own width, clipped to what the hole leaves once each fillet has its room (a centre drawer
// has one at both ends, a side drawer's pocket needs none). A "dock" drawer pockets at both ends and takes the whole hole.
function body_length(side, base_width, hole_width, fillet) {
    if (side === "dock") return hole_width;
    return Math.min(base_width, hole_width - fillet * (side === "center" ? 2 : 1));
}

// The window's layer margin along the seam, an integer, from the screen edge it is anchored to: the left for a left or centre
// drawer, the right for a right one. The cover pushes a side drawer's window out over its band; a centre one sits on the hole.
function margin_along(side, hole, screen_width, cover, window_length) {
    if (side === "left") return Math.round(hole.x - cover);
    if (side === "right") return Math.round(screen_width - (hole.x + hole.w) - cover);
    return Math.round(hole.x + (hole.w - window_length) / 2);
}

// The window's layer margin from the screen edge the drawer hangs from, an integer: the seam, less the cover under the bar.
function margin_across(rises, seam, screen_height, cover) {
    return rises ? Math.round(screen_height - seam - cover) : Math.round(seam - cover);
}

// How deep from the attached edge a drawer's rim and inset line are kept when its body draws its own edge: the mouth
// and its fillets, no further.
function mouth_depth(lay) {
    return lay.cover + lay.fillet_eff;
}

// The two end kinds of a drawer on `side` of its hole ("left", "right", "center"): a side drawer pockets at the end
// against its band and fillets at the other; a centre one fillets at both; a "dock" drawer fills the hole and pockets at both.
function end_kinds(side, dock) {
    return {
        start: side === "left" || dock ? "pocket" : "fillet",
        end: side === "right" || dock ? "pocket" : "fillet"
    };
}

// The layer-shell placement of a drawer's window, from the frame's hole and the seam it hangs from: which screen edges
// it anchors to and its margins from them, integers. Without a hole (no frame) every margin is 0 and nothing is
// anchored beyond the side. `along` and `across` are the margins that place the window against the seam.
function place(side, from_bottom, hole, seam, screen_width, screen_height, cover, window_length) {
    const along = hole ? margin_along(side, hole, screen_width, cover, window_length) : 0;
    const across = hole ? margin_across(from_bottom, seam, screen_height, cover) : 0;
    return {
        anchor_top: !from_bottom,
        anchor_bottom: from_bottom,
        anchor_left: side !== "right",
        anchor_right: side === "right",
        margin_top: from_bottom ? 0 : across,
        margin_bottom: from_bottom ? across : 0,
        margin_left: side === "right" ? 0 : along,
        margin_right: side === "right" ? along : 0,
        along: along,
        across: across
    };
}

// The drawn part of a drawer's window in screen coordinates, as the rect the frame and the strip leave their lines out under.
function window_rect(side, from_bottom, placement, screen_width, screen_height, window_width, drawn_depth) {
    return {
        x: side === "right" ? screen_width - placement.along - window_width : placement.along,
        y: from_bottom ? screen_height - placement.across - drawn_depth : placement.across,
        w: window_width,
        h: drawn_depth
    };
}
