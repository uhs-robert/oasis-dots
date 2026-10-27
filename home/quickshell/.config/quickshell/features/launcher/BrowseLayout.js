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
// faded sliver of the next row shows and the selected row still has room clear of both fades. The room comes from
// the preview, so each size keeps its rows; only an off preview, with no room to give, loses a row to it.
function fit(area, body, size, row_height, gap, count, cols, peek) {
    var whole = split(area, body, size, row_height, gap);
    var overflows = whole.rows > 0 && Math.ceil(count / Math.max(1, cols)) > whole.rows;
    if (!overflows) return { rows: whole.rows, preview_height: whole.preview_height, view_height: whole.rows * row_height, overflows: false };
    var spare = whole.preview_height > 0 ? 0 : area - whole.rows * row_height;
    var take = Math.max(0, 2 * peek - spare);
    var s = take === 0 || whole.preview_height >= take ? { rows: whole.rows, preview_height: whole.preview_height - take } : split(area - 2 * peek, body, size, row_height, gap);
    return { rows: s.rows, preview_height: s.preview_height, view_height: s.rows * row_height + 2 * peek, overflows: true };
}

// "grid" or "list"; v flips between them.
function toggled_view(view) {
    return view === "list" ? "grid" : "list";
}

// The result index a NORMAL-mode digit picks: "1" is the first, up to "9"; -1 for anything else or past the end.
function digit_index(text, count) {
    if (!/^[1-9]$/.test(text || "")) return -1;
    var i = parseInt(text, 10) - 1;
    return i < count ? i : -1;
}

// The corner number a card or row shows: its quick-pick digit, or "" past the ninth.
function hint_of(index) {
    return index >= 0 && index < 9 ? String(index + 1) : "";
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
