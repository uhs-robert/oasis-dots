.pragma library

// The browse picker's preview dial, card grid or list with its group headers, and quick pick (PickerProvider.layout
// "browse"), kept here so node can test them.

var sizes = ["off", "s", "m", "l", "max"];
// Share of the picker's body the preview takes at each size; the cards get whole rows of what is left. Max takes the
// whole body and hides the cards.
var fractions = { off: 0, s: 0.35, m: 0.55, l: 0.7, max: 1 };
var fallback_size = "m";

function size_of(name) {
    return sizes.indexOf(name) >= 0 ? name : fallback_size;
}

function grown(size) {
    return sizes[Math.min(sizes.length - 1, sizes.indexOf(size_of(size)) + 1)];
}

function shrunk(size) {
    return sizes[Math.max(0, sizes.indexOf(size_of(size)) - 1)];
}

// Off comes back at the last size that was on, so p is a peek-and-restore, not a reset.
function toggled(size, last_on) {
    if (size_of(size) !== "off") return "off";
    return size_of(last_on) === "off" ? fallback_size : size_of(last_on);
}

function columns(width, card_width, gap) {
    return Math.max(1, Math.floor((width + gap) / (card_width + gap)));
}

// `area` is the height under the search bar, `body` the whole body's. At least one row always shows, except at max,
// and the preview takes the rows' leftover so nothing is left blank below them.
function split(area, body, size, row_height, gap) {
    var s = size_of(size);
    if (s === "max") return { rows: 0, preview_height: Math.max(0, area) };
    if (s === "off" || area <= 0) return { rows: Math.max(1, Math.floor(area / row_height)), preview_height: 0 };
    var rows = Math.max(1, Math.floor((area - body * fractions[s] - gap) / row_height));
    return { rows: rows, preview_height: Math.max(0, area - rows * row_height - gap) };
}

// split, plus the cards' view height. When the content (`content_height`, from lines_of) runs past the rows, the view
// grows by `peek` at each end, so a faded sliver of the next row shows and the selected row still has room clear of
// both fades. With a preview the room comes out of it, so each size keeps its rows. With it off the view takes the
// whole area; `rows` is then how many sit clear of both fades.
function fit(area, body, size, row_height, gap, content_height, peek) {
    var whole = split(area, body, size, row_height, gap);
    var overflows = whole.rows > 0 && content_height > whole.rows * row_height + 0.5;
    if (!overflows) return { rows: whole.rows, preview_height: whole.preview_height, view_height: whole.rows * row_height, overflows: false };
    if (size_of(size) === "off") return { rows: Math.max(1, Math.floor((area - 2 * peek) / row_height)), preview_height: 0, view_height: Math.max(0, area), overflows: true };
    var s = whole.preview_height >= 2 * peek ? { rows: whole.rows, preview_height: whole.preview_height - 2 * peek } : split(area - 2 * peek, body, size, row_height, gap);
    return { rows: s.rows, preview_height: s.preview_height, view_height: s.rows * row_height + 2 * peek, overflows: true };
}

// "grid" or "list"; v flips between them.
function toggled_view(view) {
    return view === "list" ? "grid" : "list";
}

// Tab between the preview and the provider's alternate one: { size, alt }. With the preview off, Tab reads as asking for
// the alternate, so it comes back at its last size showing that.
function alt_swapped(size, last_on, alt_shown) {
    if (size_of(size) !== "off") return { size: size_of(size), alt: !alt_shown };
    return { size: toggled(size, last_on), alt: true };
}

// Runs of equal neighbouring keys, in order: [{ key, first, count }].
function runs_of(keys) {
    var out = [];
    for (var i = 0; i < keys.length; i++) {
        var last = out[out.length - 1];
        if (last && last.key === keys[i]) last.count++;
        else out.push({ key: keys[i], first: i, count: 1 });
    }
    return out;
}

// The browse view top to bottom, from groups of results ({ first, count, title }): a header line for each group with a
// title, then the group's items `cols` to a line, so every group starts on a line of its own. `item_line` maps each
// result index to its line; headers hold no items, so nothing selects them.
function lines_of(groups, cols, cell_height, header_height) {
    var c = Math.max(1, cols);
    var lines = [];
    var item_line = [];
    var y = 0;
    for (var g = 0; g < groups.length; g++) {
        var group = groups[g];
        if (group.count <= 0) continue;
        if (group.title) {
            lines.push({ kind: "header", title: group.title, first: group.first, count: 0, y: y, height: header_height });
            y += header_height;
        }
        for (var i = 0; i < group.count; i += c) {
            var n = Math.min(c, group.count - i);
            for (var k = 0; k < n; k++) item_line[group.first + i + k] = lines.length;
            lines.push({ kind: "items", title: "", first: group.first + i, count: n, y: y, height: cell_height });
            y += cell_height;
        }
    }
    return { lines: lines, item_line: item_line, height: y };
}

// j/k: the same column on the next line of items, skipping headers and wrapping top to bottom; a short line lands on
// its last item.
function line_moved(layout, index, delta) {
    var item_lines = [];
    for (var i = 0; i < layout.lines.length; i++) if (layout.lines[i].kind === "items") item_lines.push(i);
    var at = layout.item_line[index];
    var p = item_lines.indexOf(at);
    if (p < 0) return index;
    var n = item_lines.length;
    var next = layout.lines[item_lines[(((p + delta) % n) + n) % n]];
    return next.first + Math.min(index - layout.lines[at].first, next.count - 1);
}

// 0/$: the first or last item on the selected item's line.
function line_end(layout, index, to_end) {
    var line = layout.lines[layout.item_line[index]];
    if (!line) return index;
    return to_end ? line.first + line.count - 1 : line.first;
}

// The height of the header right above the item's line, so revealing a group's first line brings its header too.
function lead_of(layout, index) {
    var at = layout.item_line[index];
    var above = at > 0 ? layout.lines[at - 1] : null;
    return above && above.kind === "header" ? above.height : 0;
}

// The items wholly on screen, as result indices [first, end): whole lines of items inside the view, short of the
// scroll cue's fade at an edge that hides more, so a faded peek line never counts. The quick-pick digits number the
// first nine.
function on_screen(layout, content_y, view_height, gap, fade) {
    if (!layout || layout.lines.length === 0 || view_height <= 0) return { first: 0, end: 0 };
    var edges_hide = { top: content_y > 1, bottom: content_y + view_height < layout.height - 1 };
    var top = content_y + (edges_hide.top ? fade : 0) - 0.5;
    var bottom = content_y + view_height - (edges_hide.bottom ? fade : 0) + 0.5;
    var first = -1;
    var end = 0;
    for (var i = 0; i < layout.lines.length; i++) {
        var line = layout.lines[i];
        if (line.kind !== "items" || line.y < top || line.y + line.height - gap > bottom) continue;
        if (first < 0) first = line.first;
        end = line.first + line.count;
    }
    return first < 0 ? { first: 0, end: 0 } : { first: first, end: end };
}

// The result index a NORMAL-mode digit picks among the items on screen (`shown`, from on_screen): "1" is the first of
// them, up to "9"; -1 for anything else or past the last one shown.
function digit_index(text, shown) {
    if (!/^[1-9]$/.test(text || "")) return -1;
    var i = shown.first + parseInt(text, 10) - 1;
    return i < Math.min(shown.end, shown.first + 9) ? i : -1;
}

// The corner number a card or row shows: its quick-pick digit while among the first nine on screen, else "".
function hint_of(index, shown) {
    return index >= shown.first && index < Math.min(shown.end, shown.first + 9) ? String(index - shown.first + 1) : "";
}
