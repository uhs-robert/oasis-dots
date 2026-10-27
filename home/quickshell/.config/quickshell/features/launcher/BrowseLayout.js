.pragma library

// The browse picker's preview dial, card grid or list, quick pick and type filter (PickerProvider.layout "browse"),
// kept here so node can test them.

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

// split, plus the cards' view height. When the items run past the rows, the view grows by `peek` at each end, so a
// faded sliver of the next row shows and the selected row still has room clear of both fades. With a preview the room
// comes out of it, so each size keeps its rows. With it off the view takes the whole area; `rows` is then how many sit
// clear of both fades.
function fit(area, body, size, row_height, gap, count, cols, peek) {
    var whole = split(area, body, size, row_height, gap);
    var overflows = whole.rows > 0 && Math.ceil(count / Math.max(1, cols)) > whole.rows;
    if (!overflows) return { rows: whole.rows, preview_height: whole.preview_height, view_height: whole.rows * row_height, overflows: false };
    if (size_of(size) === "off") return { rows: Math.max(1, Math.floor((area - 2 * peek) / row_height)), preview_height: 0, view_height: Math.max(0, area), overflows: true };
    var s = whole.preview_height >= 2 * peek ? { rows: whole.rows, preview_height: whole.preview_height - 2 * peek } : split(area - 2 * peek, body, size, row_height, gap);
    return { rows: s.rows, preview_height: s.preview_height, view_height: s.rows * row_height + 2 * peek, overflows: true };
}

// "grid" or "list"; v flips between them.
function toggled_view(view) {
    return view === "list" ? "grid" : "list";
}

// The items wholly on screen, as result indices [first, end): whole rows inside the view, short of the scroll cue's
// fade at an edge that hides more, so a faded peek row never counts. The quick-pick digits number the first nine.
function on_screen(content_y, view_height, content_height, cell_height, item_height, fade, cols, count) {
    var c = Math.max(1, cols);
    if (count <= 0 || view_height <= 0 || cell_height <= 0) return { first: 0, end: 0 };
    var edges_hide = { top: content_y > 1, bottom: content_y + view_height < content_height - 1 };
    var top = content_y + (edges_hide.top ? fade : 0) - 0.5;
    var bottom = content_y + view_height - (edges_hide.bottom ? fade : 0) + 0.5;
    var first_row = Math.max(0, Math.ceil(top / cell_height));
    var end_row = Math.floor((bottom - item_height) / cell_height) + 1;
    if (end_row <= first_row) return { first: 0, end: 0 };
    return { first: Math.min(count, first_row * c), end: Math.min(count, end_row * c) };
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

// The clipboard's type filter; binary entries are neither text nor images, so only "all" keeps them.
var filters = ["all", "text", "image"];
var filter_labels = { all: "ALL", text: "TEXT", image: "IMAGES" };

function cycled_filter(filter) {
    var i = filters.indexOf(filter);
    return filters[(i + 1) % filters.length];
}

function kept_by_filter(kind, filter) {
    return filters.indexOf(filter) <= 0 || kind === filter;
}
