.pragma library

// Text rules for the media well, pure so a node test covers them.

// Cuts to `max_chars` characters, the last being an ellipsis when anything was cut.
function clip(text, max_chars) {
    if (text.length <= max_chars) return text;
    return text.slice(0, Math.max(0, max_chars - 1)).replace(/\s+$/, "") + "…";
}

// The lines the well shows, from the shown fields: "inline" joins them as "Artist - Title" on one line, "stacked"
// puts the title over a smaller artist line. Empty fields and hidden fields leave no line.
// With neither title nor artist (a radio stream, a player that sends no metadata) it shows the player's `identity`.
function lines(title, artist, show_title, show_artist, layout, identity) {
    if (!title && !artist && identity && (show_title || show_artist)) return [{ text: identity, small: false }];
    const t = show_title && title ? title : "";
    const a = show_artist && artist ? artist : "";
    if (layout === "stacked") {
        const out = [];
        if (t) out.push({ text: t, small: false });
        if (a) out.push({ text: a, small: !!t });
        return out;
    }
    const joined = [a, t].filter(s => s !== "").join(" - ");
    return joined ? [{ text: joined, small: false }] : [];
}

// Pixel sizes of a stacked title and artist whose two text lines fit `inner` px. A line is taller than its pixel size
// (`ratio` times it, measured from the font; `LINE` when unknown), so sizing by the pixel size alone let the block
// overflow the plate. QML rounds each Text's height up on its own, so the fit is checked on the per-line rounded heights,
// not their unrounded sum. The title keeps up to `base` and the larger share; the artist is smaller and never
// below 6 px, so an `inner` too small to fit both is the caller's to enlarge.
const LINE = 1.3;
function stacked_sizes(inner, base, ratio) {
    const room = Math.floor(inner / Math.max(1, ratio || LINE));
    const title = Math.max(6, Math.min(base, Math.ceil(room * 0.56)));
    const artist = Math.max(6, Math.min(base - 3, room - title));
    const line_ratio = Math.max(1, ratio || LINE);
    const rounded_height = size => Math.ceil(size * line_ratio);
    let fitted_title = title;
    while (fitted_title > 6 && rounded_height(fitted_title) + rounded_height(artist) > inner) fitted_title--;
    return { title: fitted_title, artist: artist };
}

function format_time(seconds) {
    const s = Math.max(0, Math.floor(seconds || 0));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const r = s % 60;
    const pad = n => (n < 10 ? "0" + n : "" + n);
    return h > 0 ? h + ":" + pad(m) + ":" + pad(r) : m + ":" + pad(r);
}

function ratio(position, length) {
    if (!(length > 0)) return 0;
    return Math.max(0, Math.min(1, position / length));
}

// One marquee cycle, in ms: wait at the start, slide left by `overflow` px at `speed` px/s, wait at the end, then jump
// back to the start. One direction only, so the text is always read left to right.
function marquee_cycle(overflow, speed, pause_ms) {
    return { start_pause: pause_ms, travel: Math.round(Math.max(0, overflow) / Math.max(1, speed) * 1000), end_pause: pause_ms };
}

// Whether the marquee should run: wanted, visible and the text really overflows its window.
function marquee_running(wanted, visible, overflow) {
    return !!wanted && !!visible && overflow > 0;
}

// Horizontal room the contents keep from the plate's side so a square corner of the art (at `pad` px from the top and
// bottom) stays inside the plate's corner. A chamfer or pixel corner cuts `size` px off, so the art clears the diagonal;
// a round corner is a circle of radius min(size, height / 2), so the art clears the arc at its height, plus a pixel for the 1px outline drawn inside it. Other corners are
// square and need only `pad`.
function side_inset(corner, size, pad, height) {
    if (corner === "chamfer" || corner === "pixel") return Math.max(pad, size - pad + 2);
    if (corner !== "round") return pad;
    const r = Math.min(size, height / 2);
    if (!(r > pad)) return pad;
    const x_on_arc = r - Math.sqrt(r * r - (r - pad) * (r - pad));
    return Math.max(pad, Math.ceil(x_on_arc) + 2);
}
