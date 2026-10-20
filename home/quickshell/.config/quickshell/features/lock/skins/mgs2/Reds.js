.pragma library

// Moves MGS2's reds onto the lock tint. The molecule red maps exactly onto the tint's base colour, and every other red
// keeps its place relative to it: saturation in proportion, so a near-grey tint such as white stays near grey, and
// lightness piecewise linear (0 and 1 stay put), so the dark smears stay dark and the bright error tone brighter.

function hsl(r, g, b) {
    r /= 255;
    g /= 255;
    b /= 255;
    const hi = Math.max(r, g, b), lo = Math.min(r, g, b), l = (hi + lo) / 2, d = hi - lo;
    if (d === 0) return [0, 0, l];
    const s = d / (1 - Math.abs(2 * l - 1));
    const h = hi === r ? ((g - b) / d + 6) % 6 : hi === g ? (b - r) / d + 2 : (r - g) / d + 4;
    return [h / 6, s, l];
}

function rgb(h, s, l) {
    const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs((h * 6) % 2 - 1)), m = l - c / 2;
    const k = Math.floor(h * 6) % 6;
    const t = [[c, x, 0], [x, c, 0], [0, c, x], [0, x, c], [x, 0, c], [c, 0, x]][k];
    return [Math.round((t[0] + m) * 255), Math.round((t[1] + m) * 255), Math.round((t[2] + m) * 255)];
}

const classic_mol_red = hsl(214, 49, 38);

function remap_lightness(v, from, to) {
    if (v <= from) return from > 0 ? v / from * to : to;
    return to + (1 - to) * (v - from) / (1 - from);
}

// The tint colour `col` as the [h, s, l] the reds move to; null (no tint) keeps the classic reds.
function tint_hsl_of(col) {
    return col ? hsl(col.r * 255, col.g * 255, col.b * 255) : null;
}

// The classic red r, g, b (0-255) moved onto `tint_hsl`, as [r, g, b]; unchanged when `tint_hsl` is null.
function shade(tint_hsl, r, g, b) {
    if (!tint_hsl) return [r, g, b];
    const c = hsl(r, g, b);
    return rgb(tint_hsl[0], Math.min(1, c[1] / classic_mol_red[1] * tint_hsl[1]), remap_lightness(c[2], classic_mol_red[2], tint_hsl[2]));
}

// A canvas rgba() string for the classic red r, g, b at alpha a.
function css(tint_hsl, r, g, b, a) {
    const o = shade(tint_hsl, r, g, b);
    return "rgba(" + o[0] + "," + o[1] + "," + o[2] + "," + a + ")";
}
