.pragma library

// Where the tmux preview (TmuxWindowView.qml) draws a window, kept here so node can test it. Places and sizes are in
// cells, as tmux reports them; the view multiplies them by its cell size.

function rect_of(pane, x, y) {
    return { pane_id: pane.pane_id, x: x, y: y, w: pane.width, h: pane.height };
}

// The panes drawn for a window. A zoomed window shows the shown pane alone from the top left: the zoomed pane fills
// the window, and another one keeps the size it has behind the zoom.
function drawn_panes(item, shown) {
    if (!item) return [];
    if (item.zoomed && shown) return [rect_of(shown, 0, 0)];
    return item.panes.map(function (p) { return rect_of(p, p.left, p.top); });
}

// The window's size in cells; from its panes when tmux gave none.
function grid_size(item) {
    if (!item) return { cols: 0, rows: 0 };
    var cols = item.width || 0;
    var rows = item.height || 0;
    item.panes.forEach(function (p) {
        if (!item.width) cols = Math.max(cols, p.left + p.width);
        if (!item.height) rows = Math.max(rows, p.top + p.height);
    });
    return { cols: cols, rows: rows };
}

// The largest whole font size whose cols x rows grid fits area_w x area_h, given the font's advance and line pitch
// per pixel of size; 1% slack for hinting. 0 for an empty grid or area.
function font_px_to_fit(cols, rows, area_w, area_h, advance_ratio, line_ratio) {
    if (cols <= 0 || rows <= 0 || area_w <= 0 || area_h <= 0 || advance_ratio <= 0 || line_ratio <= 0) return 0;
    return Math.max(1, Math.floor(Math.min(area_w / (cols * advance_ratio), area_h / (rows * line_ratio)) * 0.99));
}

// A w x h box centred in the area, whole pixels, never above or left of it.
function letterbox(w, h, area_w, area_h) {
    return { x: Math.max(0, Math.floor((area_w - w) / 2)), y: Math.max(0, Math.floor((area_h - h) / 2)), w: w, h: h };
}

// tmux draws a border in the cell row or column between two panes. Each pane's right and bottom border runs through
// the middle of those cells, reaching into the corners it shares, so every border between panes is drawn and the
// window's own edges get none. Segments are { x1, y1, x2, y2 }, one of them flat.
function borders(panes, cols, rows) {
    var out = [];
    panes.forEach(function (p) {
        var right = p.x + p.w;
        var bottom = p.y + p.h;
        if (right < cols) out.push({ x1: right + 0.5, y1: p.y > 0 ? p.y - 0.5 : 0, x2: right + 0.5, y2: bottom < rows ? bottom + 0.5 : rows });
        if (bottom < rows) out.push({ x1: p.x > 0 ? p.x - 0.5 : 0, y1: bottom + 0.5, x2: right < cols ? right + 0.5 : cols, y2: bottom + 0.5 });
    });
    return out;
}

// The outline around one pane, on the borders it shares and at the window's edges elsewhere.
function frame(pane, cols, rows) {
    var x1 = pane.x > 0 ? pane.x - 0.5 : 0;
    var y1 = pane.y > 0 ? pane.y - 0.5 : 0;
    var x2 = pane.x + pane.w < cols ? pane.x + pane.w + 0.5 : cols;
    var y2 = pane.y + pane.h < rows ? pane.y + pane.h + 0.5 : rows;
    return { x: x1, y: y1, w: x2 - x1, h: y2 - y1 };
}

// The first `rows` captured lines of a pane, as its screen shows them from the top.
function screen_text(lines, rows) {
    return (lines || []).slice(0, Math.max(0, rows)).join("\n");
}
