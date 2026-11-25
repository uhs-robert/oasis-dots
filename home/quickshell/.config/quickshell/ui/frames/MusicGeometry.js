.pragma library

// Music mode's bars: audio levels drawn as short bars standing on the screen frame's hole edge and growing into the
// hole, one row per side. Pure geometry in screen coordinates; MusicFrame.qml draws the rects.
//
// The drawing code works on a `frame` description, not on FrameGeometry's layout, so a change to the layout's shape
// touches only frame_from_layout below:
//   { w, h, hole: { x, y, w, h }, radius, strips: [{ edge: "top" | "bottom", size }] }
// `hole` is the window area in screen pixels, `radius` its corner radius, and each strip a bar band that bars never
// cover (it spans the full width, `size` tall from its edge). Any number of strips on any edge works.

// Layout fields read: edge, has_bar, length, depth, near, far, start, end, radius.
function frame_from_layout(lay) {
    const bottom = lay.edge === "bottom";
    const y0 = bottom ? lay.depth - lay.far : lay.near;
    const y1 = bottom ? lay.depth - lay.near : lay.far;
    return {
        w: lay.length,
        h: lay.depth,
        hole: { x: lay.start, y: y0, w: lay.length - lay.start - lay.end, h: y1 - y0 },
        radius: lay.radius,
        strips: lay.has_bar ? [{ edge: lay.edge, size: lay.near }] : []
    };
}

const default_options = { bar_width: 4, gap: 3, max_fraction: 0.12 };

// Level at fraction t (0..1) of the levels array, linearly interpolated and clamped to 0..1.
function level_at(levels, t) {
    const n = levels.length;
    if (n === 0) return 0;
    const pos = Math.min(1, Math.max(0, t)) * (n - 1);
    const i = Math.floor(pos), j = Math.min(n - 1, i + 1);
    const a = Number(levels[i]) || 0, b = Number(levels[j]) || 0;
    return Math.min(1, Math.max(0, a + (b - a) * (pos - i)));
}

// What is left of rect r outside every strip, or null when nothing is.
function outside_strips(r, frame) {
    let top = r.y, bottom = r.y + r.h;
    for (const s of frame.strips) {
        if (s.edge === "top") top = Math.max(top, s.size);
        else if (s.edge === "bottom") bottom = Math.min(bottom, frame.h - s.size);
    }
    return bottom - top > 0 ? { x: r.x, y: top, w: r.w, h: bottom - top } : null;
}

// The bar rects { x, y, w, h, edge } for `levels` (any length, 0..1) on `frame`. The hole's four straight stretches,
// between the corners, form one clockwise perimeter starting at the top; the levels are spread over it by position,
// so a bar's height follows where it stands, not which edge it is on. All-zero levels give an empty list.
// options.grow: "band" (default) grows each bar outward from the hole's edge into the frame band, up to that band's
// depth (a band under a strip has none, so the strip's side draws nothing); "hole" grows it into the hole instead.
function music_bars(frame, levels, options) {
    const o = Object.assign({}, default_options, options || {});
    const hole = frame.hole, r = Math.max(0, frame.radius || 0);
    const into_hole = o.grow === "hole";
    const strip_size = edge => frame.strips.filter(s => s.edge === edge).reduce((m, s) => Math.max(m, s.size), 0);
    const hole_reach = o.max_fraction * Math.min(hole.w, hole.h);
    const depth = {
        top: hole.y - strip_size("top"),
        bottom: frame.h - hole.y - hole.h - strip_size("bottom"),
        left: hole.x,
        right: frame.w - hole.x - hole.w
    };
    const pitch = o.bar_width + o.gap;
    const sides = [
        { edge: "top", from: hole.x + r, to: hole.x + hole.w - r,
          rect: (at, len) => ({ x: at, y: into_hole ? hole.y : hole.y - len, w: o.bar_width, h: len }) },
        { edge: "right", from: hole.y + r, to: hole.y + hole.h - r,
          rect: (at, len) => ({ x: into_hole ? hole.x + hole.w - len : hole.x + hole.w, y: at, w: len, h: o.bar_width }) },
        { edge: "bottom", from: hole.x + r, to: hole.x + hole.w - r,
          rect: (at, len) => ({ x: at, y: into_hole ? hole.y + hole.h - len : hole.y + hole.h, w: o.bar_width, h: len }) },
        { edge: "left", from: hole.y + r, to: hole.y + hole.h - r,
          rect: (at, len) => ({ x: into_hole ? hole.x : hole.x - len, y: at, w: len, h: o.bar_width }) }
    ];
    const total = sides.reduce((sum, s) => sum + Math.max(0, s.to - s.from), 0);
    if (total <= 0) return [];
    const out = [];
    let before = 0;
    for (const s of sides) {
        const span = s.to - s.from;
        if (span <= 0) continue;
        const count = Math.floor((span + o.gap) / pitch);
        // Bottom and left run against the clockwise walk, so their bars are placed from the far end.
        const reversed = s.edge === "bottom" || s.edge === "left";
        for (let k = 0; k < count; k++) {
            const lead = (span - (count * pitch - o.gap)) / 2;
            const at = s.from + lead + k * pitch;
            const walked = reversed ? span - (at - s.from + o.bar_width / 2) : at - s.from + o.bar_width / 2;
            const len = level_at(levels, (before + walked) / total) * (into_hole ? hole_reach : Math.max(0, depth[s.edge]));
            if (len <= 0) continue;
            const rect = outside_strips(s.rect(at, len), frame);
            if (rect) out.push(Object.assign(rect, { edge: s.edge }));
        }
        before += span;
    }
    return out;
}

// Bars for a FrameGeometry.frame_layout object.
function music_bars_for_layout(lay, levels, options) {
    return music_bars(frame_from_layout(lay), levels, options);
}
