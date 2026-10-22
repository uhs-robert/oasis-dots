.pragma library
.import "IslandOutlines.js" as Outlines

// A band: a strip along one screen edge, drawn by BandFill. It knows no bar or islands, so the full-bar strip and
// a screen frame's side bands share it. Everything is drawn in the band frame, which IslandOutlines' top-bar frame
// generalises: x runs along the edge from 0 to `length`, y = 0 lies on the screen edge and y = thickness on the open
// edge. band_frame and band_affine place that frame on any of the four edges.
// The screen frame will add corner_profile(kind, r) here: the outline of a corner joining two bands.

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

// The rim along the open edge, as IslandOutlines' rim paths; the ends stop inset_start and inset_end short of the
// band's ends, where a frame's corners take over.
function band_rim(length, thickness, inset_start, inset_end) {
    return [[inset_start, thickness], [length - inset_end, thickness]];
}

// The rim's centre line for a stroke `width` wide, so the stroke lies inside the band.
function band_rim_stroke(length, thickness, inset_start, inset_end, width) {
    return Outlines.inset(band_rim(length, thickness, inset_start, inset_end), width / 2);
}

// The closed fill, always the band's whole length whatever the rim's insets.
function band_fill(length, thickness) {
    return Outlines.fill_path(band_rim(length, thickness, 0, 0), length, false, false);
}

// The left and right x of the fill at height y inside a rim `border` wide; [0, 0] past it.
function band_span(length, thickness, border, y) {
    return Outlines.span_at(Outlines.inset(band_rim(length, thickness, 0, 0), border), y);
}
