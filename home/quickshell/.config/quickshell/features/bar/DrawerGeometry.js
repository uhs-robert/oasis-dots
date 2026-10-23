.pragma library
.import "IslandOutlines.js" as Outlines
.import "BandGeometry.js" as Band

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

// spec: { edge, body_length, body_depth, extent, radius, fillet, start_kind, end_kind, cover }. `radius` rounds the
// body's free corners and `fillet` the concave arcs; both shrink with the extent and the body's width, so nothing
// inverts and a pocket's two arcs never cross.
function drawer_layout(spec) {
    const extent = Math.max(0, Math.min(spec.extent, spec.body_depth));
    const fillet_eff = Math.min(spec.fillet, extent / 2, spec.body_length / 2);
    const radius_eff = Math.min(spec.radius, extent / 2, spec.body_length / 2);
    // A fillet end also reserves the LEAD its outline runs on along the frame's line; a pocket reserves its own in `depth`.
    const start_room = spec.start_kind === "pocket" ? spec.cover : spec.fillet + LEAD;
    const end_room = spec.end_kind === "pocket" ? spec.cover : spec.fillet + LEAD;
    const any_pocket = spec.start_kind === "pocket" || spec.end_kind === "pocket";
    const length = start_room + spec.body_length + end_room;
    // A pocket's outline runs LEAD px on down the side band past its arc, so the window reserves that too.
    const pocket_room = any_pocket ? spec.fillet + LEAD : 0;
    const depth = spec.cover + spec.body_depth + pocket_room;
    const vertical = spec.edge === "left" || spec.edge === "right";
    return {
        edge: spec.edge,
        length: length,
        depth: depth,
        // How deep the shape has drawn so far; `depth` is the window's, which stays at the popup's full reserve.
        drawn_depth: spec.cover + extent + pocket_room,
        cover: spec.cover,
        radius_eff: radius_eff,
        fillet_eff: fillet_eff,
        start_kind: spec.start_kind,
        end_kind: spec.end_kind,
        start_room: start_room,
        end_room: end_room,
        body: { u: start_room, v: spec.cover, w: spec.body_length, d: extent },
        surface: vertical ? { width: depth, height: length } : { width: length, height: depth }
    };
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
    const start = lay.start_kind === "pocket"
        ? Outlines.arc(left + f, far + f, f, 180, 270)
        : [].concat(Outlines.arc(left - f, c + f, f, 270, 360), Outlines.arc(left + r, far - r, r, 180, 90));
    const end = lay.end_kind === "pocket"
        ? Outlines.arc(right - f, far + f, f, 270, 360)
        : [].concat(Outlines.arc(right - r, far - r, r, 90, 0), Outlines.arc(right + f, c + f, f, 180, 270));
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
// has one at both ends, a side drawer's pocket needs none).
function body_length(side, base_width, hole_width, fillet) {
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
