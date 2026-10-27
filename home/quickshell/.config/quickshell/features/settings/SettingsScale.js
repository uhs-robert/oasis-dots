.pragma library

// The 1080p line: at or below it Settings keeps the style's own sizes and colors.
const base_height = 1080;
const max_bump = 3;

// Extra font pixels over the style's own sizes: none up to 1080p, +2 at 1440p, +3 from about 1800p.
function text_bump(screen_height) {
    if (!(screen_height > base_height)) return 0;
    const raw = screen_height <= 1440 ? 2 * (screen_height - base_height) / 360 : 2 + (screen_height - 1440) / 720;
    return Math.min(max_bump, Math.round(raw));
}

// The largest bump up to `wanted` at which the section list still fits `avail` px. A style whose list is already tall
// (Game Boy's shell leaves the body little room) would otherwise clip its last rows once the pitch grows.
// `heading_px` is a group heading's line height plus its paddings; headings gain about 1.5 px per font px.
function fitted_bump(wanted, rows, groups, row_px, heading_px, avail) {
    for (let b = wanted; b > 0; b--) {
        const height = rows * (row_px + pitch_extra(b) + 4) + groups * (heading_px + 1.5 * b + 4);
        if (height <= avail) return b;
    }
    return 0;
}

// Extra row height for a font bump, in unscaled px (the caller adds it to a Style.px() pitch).
function pitch_extra(bump) {
    return bump * 2;
}

// The bump Settings published: the nearest ancestor holding `text_bump`; 0 outside Settings.
function bump_of(item) {
    for (let node = item; node; node = node.parent) {
        if (node.text_bump !== undefined) return node.text_bump;
    }
    return 0;
}

// The scale up to `wanted` at which something `natural` px wide fits `room` px. No floor, so it never spills out of a
// narrow pane; `wanted` while nothing has been measured yet.
function fit_zoom(wanted, room, natural) {
    if (!(natural > 0)) return wanted;
    return Math.min(wanted, Math.max(0, room) / natural);
}

// `base` moved `amount` of the way to `toward`, as [r, g, b, a]. Computed here rather than as a style token to keep it out of shared files.
function lifted(base, toward, amount) {
    return [base.r + (toward.r - base.r) * amount, base.g + (toward.g - base.g) * amount, base.b + (toward.b - base.b) * amount, base.a + (toward.a - base.a) * amount];
}
