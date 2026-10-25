.pragma library

// The cut-corner outlines of popup panels (oasis's slant foot, tie's octagon, metroid's visor, a chamfered frame) as
// point lists, so a corner against the bar can be left square. `sq` names the square corners:
// { top_left, top_right, bottom_right, bottom_left }, each true for a corner that touches the bar.

const none = { top_left: false, top_right: false, bottom_right: false, bottom_left: false };

// The slant foot's bottom edge from its left end to its right end, for the box inset by i.
function slant_foot(w, h, i, sq) {
    const x0 = i, x1 = w - i, y1 = h - i, cap = Math.max(1, h * 0.45);
    const cut = depth => Math.max(0, Math.min(depth, cap) - i * 0.6);
    const l = sq.bottom_left ? 0 : cut(10), r = sq.bottom_right ? 0 : cut(36);
    return [[x0, y1 - l], [x0 + l / 2, y1], [x1 - r / 2, y1], [x1, y1 - r]];
}

// An octagon of cut k, inset by i, with the square corners kept whole.
function octagon(w, h, i, k, sq) {
    const tl = sq.top_left ? 0 : k, tr = sq.top_right ? 0 : k, br = sq.bottom_right ? 0 : k, bl = sq.bottom_left ? 0 : k;
    const r = w - i, b = h - i;
    return [[i + tl, i], [r - tr, i], [r, i + tr], [r, b - br], [r - br, b], [i + bl, b], [i, b - bl], [i, i + tl], [i + tl, i]];
}

// The visor pane: top cuts t, bottom notches of depth k whose step sits at y, inset by i.
function visor(w, h, i, k, t, y, sq) {
    const ti = Math.max(0, t - i * 0.41);
    const tl = sq.top_left ? 0 : ti, tr = sq.top_right ? 0 : ti;
    const pts = [[i + tl, i], [w - i - tr, i], [w - i, i + tr]];
    if (sq.bottom_right) pts.push([w - i, h - i]);
    else pts.push([w - i, h - k], [w - k * 0.36, y], [w - k * 0.58, y], [w - k, h - i]);
    if (sq.bottom_left) pts.push([i, h - i]);
    else pts.push([k, h - i], [k * 0.58, y], [k * 0.36, y], [i, h - k]);
    pts.push([i, i + tl], [i + tl, i]);
    return pts;
}

// A frame whose bottom corners are cut at 45 degrees by c; o grows the box outward on every side but the right and bottom.
function chamfer(w, h, c, o, sq) {
    const l = sq.bottom_left ? 0 : c, r = sq.bottom_right ? 0 : c;
    return [[-o, -o], [w, -o], [w, h - r], [w - r, h], [l - o, h], [-o, h - l], [-o, -o]];
}
