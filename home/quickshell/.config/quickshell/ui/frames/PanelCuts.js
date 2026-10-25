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

// How far the cut at one side's end of the octagon reaches into a scanline row at row_y: top rows meet the top
// corners, bottom rows the bottom ones, and a square corner cuts nothing. c is the cut, edge the border's inset.
function corner_cut(sq, left, row_y, c, edge, h) {
    const top = left ? !sq.top_left : !sq.top_right, bottom = left ? !sq.bottom_left : !sq.bottom_right;
    return Math.max(top ? c + edge - row_y : 0, bottom ? c + edge - (h - row_y - 1) : 0, 0);
}

// The octagon's corner struts as [x_at_right, y_at_bottom, rotation], none for a square corner.
function struts(sq) {
    return [[0, 0, 45, sq.top_left], [1, 0, 135, sq.top_right], [0, 1, -45, sq.bottom_left], [1, 1, -135, sq.bottom_right]].filter(s => !s[3]).map(s => s.slice(0, 3));
}

// The x ranges of the visor's teeth under its notch steps: the right one, then the left, none for a square corner.
function visor_teeth(w, k, sq) {
    return (sq.bottom_right ? [] : [[w - k * 0.58, w - k * 0.36]]).concat(sq.bottom_left ? [] : [[k * 0.36, k * 0.58]]);
}

// The corners of a popup frame that touch the bar. `round` names the corners that stay round when the popup opens out
// beside a left or right bar, null under a top or bottom bar, where `rises` (the bar is below the frame) picks the
// pair. `flush` is false for a popup that floats clear of the bar or docks to the screen's bottom.
function bar_square(round, flush, rises) {
    if (round) return { top_left: !round.top_left, top_right: !round.top_right, bottom_left: !round.bottom_left, bottom_right: !round.bottom_right };
    const up = flush && rises;
    return { top_left: flush && !up, top_right: flush && !up, bottom_left: up, bottom_right: up };
}
