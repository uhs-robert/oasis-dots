.pragma library
.import "FrameGeometry.js" as Frame

// Music mode's bars: audio levels drawn as short bars standing on the screen frame's hole edge and growing out into the
// frame band (or into the hole, see grow), one row per side. Pure geometry in screen coordinates; MusicFrame.qml draws the rects.
//
// The drawing code works on a `frame` description, not on FrameGeometry's layout, so a change to the layout's shape
// touches only frame_from_layout below:
//   { w, h, hole: { x, y, w, h }, radius, strips: [{ edge: "top" | "bottom", size }] }
// `hole` is the window area in screen pixels, `radius` its corner radius, and each strip a bar band that bars never
// cover (it spans the full width, `size` tall from its edge). Any number of strips on any edge works.

// Layout fields read: edge, has_bar, length, depth, near, far, start, end, radius (the hole itself comes from
// FrameGeometry.hole_rect, which reads edge, depth, near, far, start, end and length).
function frame_from_layout(lay) {
    return {
        w: lay.length,
        h: lay.depth,
        hole: Frame.hole_rect(lay),
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
function outside_strips(r, frame) {  // `frame` needs only strips and h
    let top = r.y, bottom = r.y + r.h;
    for (const s of frame.strips) {
        if (s.edge === "top") top = Math.max(top, s.size);
        else if (s.edge === "bottom") bottom = Math.min(bottom, frame.h - s.size);
    }
    return bottom - top > 0 ? { x: r.x, y: top, w: r.w, h: bottom - top } : null;
}

// The bar slots for `frame`: where every bar stands, which side it is on, where it falls along the perimeter (`t`, 0..1)
// and how tall it can get (`max_len`). They depend on the frame alone, so compute them once per layout and call
// bars_from_slots on every cava tick. The hole's four straight stretches, between the corners, form one clockwise
// perimeter starting at the top. options.grow: "band" (default) grows each bar outward from the hole's edge into the
// frame band, up to that band's depth; "hole" grows it into the hole instead. In band mode a side with no band (under
// a strip) is left out of the perimeter, so every level lands on a side that is drawn.
function music_slots(frame, options) {
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
    ].filter(s => s.to - s.from > 0 && (into_hole ? hole_reach : depth[s.edge]) >= 1);
    const total = sides.reduce((sum, s) => sum + (s.to - s.from), 0);
    const slots = [];
    let before = 0;
    for (const s of sides) {
        const span = s.to - s.from;
        const count = Math.floor((span + o.gap) / pitch);
        // Whole pixels, so the bars sit on the pixel grid at any span.
        const lead = Math.floor((span - (count * pitch - o.gap)) / 2);
        // Bottom and left run against the clockwise walk, so the walk position is measured from the far end.
        const reversed = s.edge === "bottom" || s.edge === "left";
        for (let k = 0; k < count; k++) {
            const at = s.from + lead + k * pitch;
            const mid = at - s.from + o.bar_width / 2;
            slots.push({ edge: s.edge, rect: s.rect, at: at, t: (before + (reversed ? span - mid : mid)) / total, max_len: into_hole ? hole_reach : depth[s.edge] });
        }
        before += span;
    }
    return { slots: slots, strips: frame.strips, h: frame.h };
}

// The bar rects { x, y, w, h, edge } for music_slots' result and `levels` (any length, 0..1), spread over the perimeter
// by position, so a bar's height follows where it stands, not which edge it is on. Lengths are whole pixels. All-zero
// levels give an empty list.
function bars_from_slots(plan, levels) {
    const out = [];
    for (const slot of plan.slots) {
        const len = Math.round(level_at(levels, slot.t) * slot.max_len);
        if (len <= 0) continue;
        const rect = outside_strips(slot.rect(slot.at, len), plan);
        if (rect) out.push(Object.assign(rect, { edge: slot.edge }));
    }
    return out;
}

// Both steps in one call, for callers that do not cache.
function music_bars(frame, levels, options) {
    return bars_from_slots(music_slots(frame, options), levels);
}

// Bars for a FrameGeometry.frame_layout object.
function music_bars_for_layout(lay, levels, options) {
    return music_bars(frame_from_layout(lay), levels, options);
}
