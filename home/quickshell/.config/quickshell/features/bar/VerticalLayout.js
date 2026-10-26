.pragma library

// Smallest text the bar draws on a side bar; below this a number drops its unit sign instead of shrinking further.
var min_text_px = 9;

// The width a module's content may use across a side bar: the bar's thickness less the island's inset and breathing room.
function cross_width(bar_height, pad) {
    return Math.max(0, bar_height - pad);
}

// The pixel size that makes `chars` characters fit `avail`, never above `base` nor below `min`.
// advance_per_px is the text's width per character per pixel of font size.
function fit_size(chars, advance_per_px, avail, base, min) {
    if (chars <= 0 || advance_per_px <= 0) return base;
    return Math.max(min, Math.min(base, Math.floor(avail / (chars * advance_per_px))));
}

// Whether fitting the text would need a size under `min`, which is when it should lose its unit sign.
function too_wide(chars, advance_per_px, avail, min) {
    return chars > 0 && advance_per_px > 0 && avail / (chars * advance_per_px) < min;
}

// The two lines of a stacked clock, hours over minutes. 24-hour pads the hour; 12-hour does not (9 over 05).
function clock_lines(hours, minutes, h24) {
    const two = n => (n < 10 ? "0" : "") + n;
    return [h24 ? two(hours) : String(hours % 12 === 0 ? 12 : hours % 12), two(minutes)];
}

// The height of parts (heights, hidden ones 0) stacked with `spacing` between the visible ones.
function stack_height(parts, spacing) {
    const shown = parts.filter(p => p > 0);
    return shown.reduce((sum, p) => sum + p, 0) + Math.max(0, shown.length - 1) * spacing;
}
