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
// missing) and `step` the pixel profile's stair step; a spec without them draws round corners.
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
    const vertical = is_vertical(spec.edge);
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
// body_length makes room for. A null profile (no frame) draws none.
function fillet_of(profile) {
    if (!profile) return 0;
    return Corners.fit(profile.corner, profile.radius, profile.step).radius;
}

// The corner fields of a drawer_layout spec for a frame profile: the fillet size that body_length makes room for, and
// the profile's corner and step. A null profile (no frame) is a round, zero-size corner, so a spec built while the frame
// goes away stays valid.
function profile_fields(profile) {
    const fillet = profile ? fillet_of(profile) : 0;
    return { radius: fillet, fillet: fillet, corner: profile ? profile.corner : "round", step: profile ? profile.step : 0 };
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

// A drawer's attached edge as a name: `edge` is "top", "bottom", "left" or "right", or the older from_bottom flag.
function edge_of(edge) {
    if (typeof edge === "string") return edge;
    return edge ? "bottom" : "top";
}

// Whether the edge runs down the screen. On one the drawer's body_length is the panel's height and its depth the
// panel's width, and `side` names the ends along the edge: "left" is the top one, "right" the bottom one.
function is_vertical(edge) {
    const name = edge_of(edge);
    return name === "left" || name === "right";
}

// The layer-shell placement of a drawer's window, from the frame's hole and the seam it hangs from: which screen edges
// it anchors to and its margins from them, integers. Without a hole (no frame) every margin is 0 and nothing is
// anchored beyond the side. `along` and `across` are the margins that place the window against the seam.
function place(side, edge, hole, seam, screen_width, screen_height, cover, window_length) {
    const name = edge_of(edge);
    if (is_vertical(name)) return place_vertical(side, name, hole, seam, screen_width, screen_height, cover, window_length);
    const from_bottom = name === "bottom";
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

// place for a drawer on the left or right edge: the same margins turned a quarter, with the hole's y range standing in
// for the x range.
function place_vertical(side, name, hole, seam, screen_width, screen_height, cover, window_length) {
    const along = hole ? margin_along(side, { x: hole.y, w: hole.h }, screen_height, cover, window_length) : 0;
    const across = hole ? margin_across(name === "right", seam, screen_width, cover) : 0;
    const to_end = side === "right";
    return {
        anchor_top: !to_end,
        anchor_bottom: to_end,
        anchor_left: name === "left",
        anchor_right: name === "right",
        margin_top: to_end ? 0 : along,
        margin_bottom: to_end ? along : 0,
        margin_left: name === "left" ? across : 0,
        margin_right: name === "right" ? across : 0,
        along: along,
        across: across
    };
}

// The layer-shell placement of a popup beside a left or right bar, which has no frame and so no hole to hang from: the
// window anchors to the screen edge the bar's own window reserves, and only its y needs working out. `side` is the
// island it opens from in the vocabulary of place_vertical ("left" the top end of the column, "right" the bottom one);
// the popup lines up with that island's extent (`island_y`, `island_height`, screen coordinates), not with the hovered
// module, and is clamped into the screen so a tall one never leaves it. Margins are integers.
function beside_place(side, edge, island_y, island_height, popup_length, screen_height) {
    const aligned = side === "right" ? island_y + island_height - popup_length
        : side === "center" ? island_y + (island_height - popup_length) / 2
        : island_y;
    const top = Math.round(Math.max(0, Math.min(aligned, screen_height - popup_length)));
    return {
        anchor_top: true,
        anchor_bottom: false,
        anchor_left: edge === "left",
        anchor_right: edge === "right",
        margin_top: top,
        margin_bottom: 0,
        margin_left: 0,
        margin_right: 0
    };
}

// Where the accent line starts down a popup beside a side bar: on the island's own top, which is not the popup's when the
// screen clamp moved the popup. Kept inside the popup.
function beside_line_offset(island_y, popup_top, line_length, popup_length) {
    return Math.max(0, Math.min(island_y - popup_top, popup_length - line_length));
}

// Which corners of a popup beside a left or right bar are rounded: the two on the side away from the bar, as a popup
// under a top bar rounds its bottom two. The side against the bar stays square.
function beside_corners(edge) {
    const against_left = edge === "left";
    return { top_left: !against_left, bottom_left: !against_left, top_right: against_left, bottom_right: against_left };
}

// The drawn part of a drawer's window in screen coordinates, as the rect the frame and the strip leave their lines out under.
// `window_length` is the window's size along the edge.
function window_rect(side, edge, placement, screen_width, screen_height, window_length, drawn_depth) {
    const name = edge_of(edge);
    if (is_vertical(name)) {
        return {
            x: name === "right" ? screen_width - placement.across - drawn_depth : placement.across,
            y: side === "right" ? screen_height - placement.along - window_length : placement.along,
            w: drawn_depth,
            h: window_length
        };
    }
    return {
        x: side === "right" ? screen_width - placement.along - window_length : placement.along,
        y: name === "bottom" ? screen_height - placement.across - drawn_depth : placement.across,
        w: window_length,
        h: drawn_depth
    };
}

// Where a drawer's rows lie in the canonical frame of the screen frame (FrameGeometry.js), which a bottom bar mirrors: the
// frame's dither and scanlines tile from there, so a drawer tiling from the same rows continues them across the join.
// Drawer row v is canonical row `y + dir * v`: dir is +1 when the drawer hangs from the bar's own edge and -1 from the
// opposite one (which-key at the bottom under a top bar, the OSD at the top over a bottom bar), where the rows run the
// other way. `flipped` says dir is -1. `across` is the window's distance from the screen edge it hangs from.
//
// A drawer on a side edge is drawn in its window's own orientation, not the edge's (DrawerShape: the frame's scanlines
// stay horizontal there), so its rows are the window's rows: it starts at the window's top-left corner and is flipped
// when a bottom bar mirrors the canonical rows. `window_depth` is the window's size across the edge, which a right
// drawer needs to find its left side.
function texture_origin(side, edge, bar_bottom, placement, screen_width, screen_height, window_length, window_depth) {
    const name = edge_of(edge);
    if (is_vertical(name)) {
        const top = side === "right" ? screen_height - placement.along - window_length : placement.along;
        return {
            x: name === "right" ? screen_width - placement.across - window_depth : placement.across,
            y: bar_bottom ? screen_height - 1 - top : top,
            flipped: bar_bottom
        };
    }
    const flipped = (name === "bottom") !== bar_bottom;
    return {
        x: side === "right" ? screen_width - placement.along - window_length : placement.along,
        y: flipped ? screen_height - 1 - placement.across : placement.across,
        flipped: flipped
    };
}

// The affine that places the texture layers (dither, scanlines) in the window: the drawer's own on a top or bottom edge,
// none on a side edge, where they are laid out in window coordinates (see texture_origin).
function texture_affine(lay) {
    return is_vertical(lay.edge) ? [1, 0, 0, 1, 0, 0] : drawer_affine(lay);
}

// A loop of drawer points in the frame texture_affine lays the textures out in.
function texture_loop(lay, loop) {
    if (!is_vertical(lay.edge)) return loop;
    const m = drawer_affine(lay);
    return loop.map(p => [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]]);
}

// How far the 4 px dither tile and the first scanline lie from the drawer's own origin, so the tiles land on the canonical
// frame's: `dither_x` and `dither_y` are how far before the drawer a tile grid starting on the canonical origin begins
// (0 to 3), `first_scanline` the first scanline's row in the drawer (0 to period - 1).
function texture_phase(origin, period) {
    const wrap = Band.phase_wrap;
    // A flipped drawer reads the checker's rows backwards (canonical row y - v), which pairs rows as (y-1, y-2), not
    // (y, y-1): the tile grid then starts 1 - y before the drawer.
    const dither_y = origin.flipped ? wrap(1 - origin.y, 4) : wrap(origin.y, 4);
    return {
        dither_x: wrap(origin.x, 4),
        dither_y: dither_y,
        first_scanline: wrap(origin.flipped ? origin.y : -origin.y, period)
    };
}

// The spans [{ x, w }, ...] a fill loop keeps in the row from y0 to y1, sampled at the row's middle as
// FrameGeometry.frame_blocks does, for the dither's rows. Most rows are one stretch, but past the far edge of a drawer
// pocketed at both ends a row crosses the two pockets' columns with the hole between them; a row the loop does not
// reach has none.
function fill_row_spans(loop, y0, y1) {
    const y = (y0 + y1) / 2;
    const crossings = [];
    for (let k = 0; k + 1 < loop.length; k++) {
        const a = loop[k], b = loop[k + 1];
        if (a[1] === b[1] || y < Math.min(a[1], b[1]) || y >= Math.max(a[1], b[1])) continue;
        crossings.push(a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]));
    }
    // Sorted, the row's crossings of the loop pair up as where it enters the fill and where it leaves.
    crossings.sort((p, q) => p - q);
    const spans = [];
    for (let k = 0; k + 1 < crossings.length; k += 2) {
        if (crossings[k + 1] > crossings[k]) spans.push({ x: crossings[k], w: crossings[k + 1] - crossings[k] });
    }
    return spans;
}
