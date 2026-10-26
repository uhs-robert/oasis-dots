.pragma library

// Smallest text the bar draws on a side bar; below this a number drops its unit sign instead of shrinking further.
var min_text_px = 9;

// Breathing room the content keeps from the island's edge, inside the bar's thickness.
var air_px = 4;

// The width a module's content may use across a side bar: the bar's thickness less the island's inset and breathing room.
function cross_width(bar_height, pad) {
    return Math.max(0, bar_height - pad);
}

// A text's width at font size s is glyph_per_px * s + fixed: the glyphs scale with the size, the letter spacing (fixed px
// per character) does not. Every function below takes that pair as `metric`.

// The pixel size that makes `metric` fit `avail`, never above `base` nor below `min` (a base under `min` is kept: text is not enlarged).
function fit_size(metric, avail, base, min) {
    if (metric.glyph_per_px <= 0) return base;
    return Math.min(base, Math.max(min, Math.floor((avail - metric.fixed) / metric.glyph_per_px)));
}

// Whether fitting `metric` would need a size under `min` (or under `base` when that is smaller), which is when it should lose its unit sign.
function too_wide(metric, avail, base, min) {
    return metric.glyph_per_px > 0 && (avail - metric.fixed) / metric.glyph_per_px < Math.min(min, base);
}

// Which text a column shows and at what size. `full` and `short` (null when there is no short form) are the metrics of the
// module's widest value, not of the live one, so the answer does not change as the digits do.
function fit_text(full, short, avail, base, min) {
    const use_short = !!short && too_wide(full, avail, base, min);
    return { short: use_short, size: fit_size(use_short ? short : full, avail, base, min) };
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
