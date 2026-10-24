.pragma library
.import "IslandOutlines.js" as Outlines

// A band: a strip along one screen edge, drawn by BandFill. It knows no bar or islands; the full-bar strip is one,
// and a screen frame (FrameGeometry.js) draws in the band frame of the bar's edge. Everything is drawn in the band
// frame, which IslandOutlines' top-bar frame generalises: x runs along the edge from 0 to `length`, y = 0 lies on the
// screen edge and y = thickness on the open edge. band_frame and band_affine place that frame on any of the four edges.

// The band's rectangle on a screen_w x screen_h screen, as { x, y, width, height }.
function band_rect(edge, screen_w, screen_h, thickness) {
    switch (edge) {
    case "bottom": return { x: 0, y: screen_h - thickness, width: screen_w, height: thickness };
    case "left": return { x: 0, y: 0, width: thickness, height: screen_h };
    case "right": return { x: screen_w - thickness, y: 0, width: thickness, height: screen_h };
    }
    return { x: 0, y: 0, width: screen_w, height: thickness };
}

// How the band frame lands on `edge`: its length, then (mirror) y flipped across the band, then a clockwise
// rotation in degrees. A vertical band's x runs down the screen.
function band_frame(edge, screen_w, screen_h) {
    switch (edge) {
    case "bottom": return { length: screen_w, rotation: 0, mirror: true };
    case "left": return { length: screen_h, rotation: 90, mirror: true };
    case "right": return { length: screen_h, rotation: 90, mirror: false };
    }
    return { length: screen_w, rotation: 0, mirror: false };
}

// band_frame as the affine [a, b, c, d, tx, ty] taking a band-frame point (u, v) to (a u + c v + tx, b u + d v + ty)
// inside band_rect, for a QML Matrix4x4.
function band_affine(edge, thickness) {
    const frame = band_frame(edge, 0, 0);
    const vy = frame.mirror ? -1 : 1, ty = frame.mirror ? thickness : 0;
    if (frame.rotation === 90) return [0, 1, -vy, 0, thickness - ty, 0];
    return [1, 0, 0, vy, 0, ty];
}

// A positive remainder of v by `period`: where a pattern tiled from the canonical origin starts inside a band or drawer
// whose own origin sits at v, so every surface shows the same tiles.
function phase_wrap(v, period) {
    return ((v % period) + period) % period;
}

// The rim along the open edge, as IslandOutlines' rim paths; the ends stop inset_start and inset_end short of the
// band's ends, where a frame's corners take over.
function band_rim(length, thickness, inset_start, inset_end) {
    return [[inset_start, thickness], [length - inset_end, thickness]];
}

// A plate (a band set in from the screen edge, `ends` an IslandOutlines profile, "" for an ordinary band): its outline
// from the left end round the open edge to the right end, the ends `cap` px deep. The top edge closes it.
function plate_rim(ends, length, thickness, cap) {
    return Outlines.rim_path(ends, length, thickness, cap, true, true);
}

// The plate's rim stroke `width` wide as a closed loop, so the stroke lies inside the outline all the way round.
function plate_rim_stroke(ends, length, thickness, cap, width) {
    const loop = Outlines.inset_ring(plate_rim(ends, length, thickness, cap), width / 2);
    return loop.concat([loop[0]]);
}

// The rim's centre line for a stroke `width` wide, so the stroke lies inside the band.
function band_rim_stroke(length, thickness, inset_start, inset_end, width) {
    return Outlines.inset(band_rim(length, thickness, inset_start, inset_end), width / 2);
}

// The closed fill, always the band's whole length whatever the rim's insets.
function band_fill(length, thickness, ends, cap) {
    if (ends) return Outlines.fill_path(plate_rim(ends, length, thickness, cap), length, true, true);
    return Outlines.fill_path(band_rim(length, thickness, 0, 0), length, false, false);
}

// The left and right x of the fill at height y inside a rim `border` wide; [0, 0] past it.
function band_span(length, thickness, border, y, ends, cap) {
    if (ends) return y < border ? [0, 0] : Outlines.span_at(Outlines.inset(plate_rim(ends, length, thickness, cap), border), y);
    return Outlines.span_at(Outlines.inset(band_rim(length, thickness, 0, 0), border), y);
}

// Gaps GapClip keeps apart; any beyond are folded into the last one's bounding box (an over-wide gap, never a line left
// under a drawer). Two drawers overlap while one closes and another opens, so three is already generous.
const MAX_GAPS = 3;

// How many rects gap_regions can return: a column before each gap and one after, and a rect above and below each gap.
function region_slots() {
    return MAX_GAPS * 3 + 1;
}

// The rects covering a w by h area but for `gaps` (each { x, y, w, h }, clamped to the area), left to right: the column
// before each gap, then the rects above and below it between its columns, and the last column. Gaps that overlap along x
// merge into their bounding box. With no gap, the whole area.
function gap_regions(w, h, gaps) {
    const cut = [];
    for (const g of gaps || []) {
        const x0 = Math.max(0, Math.min(w, g.x)), x1 = Math.max(x0, Math.min(w, g.x + g.w));
        const y0 = Math.max(0, Math.min(h, g.y)), y1 = Math.max(y0, Math.min(h, g.y + g.h));
        if (x1 > x0 && y1 > y0) cut.push({ x0: x0, x1: x1, y0: y0, y1: y1 });
    }
    cut.sort((a, b) => a.x0 - b.x0);
    const merged = [];
    for (const c of cut) {
        const last = merged[merged.length - 1];
        if (last && (merged.length >= MAX_GAPS || c.x0 <= last.x1)) {
            last.x1 = Math.max(last.x1, c.x1);
            last.y0 = Math.min(last.y0, c.y0);
            last.y1 = Math.max(last.y1, c.y1);
        } else {
            merged.push(c);
        }
    }
    const out = [];
    let cursor = 0;
    for (const m of merged) {
        out.push({ x: cursor, y: 0, w: m.x0 - cursor, h: h });
        out.push({ x: m.x0, y: 0, w: m.x1 - m.x0, h: m.y0 });
        out.push({ x: m.x0, y: m.y1, w: m.x1 - m.x0, h: h - m.y1 });
        cursor = m.x1;
    }
    out.push({ x: cursor, y: 0, w: w - cursor, h: h });
    return out.filter(r => r.w > 0 && r.h > 0);
}
