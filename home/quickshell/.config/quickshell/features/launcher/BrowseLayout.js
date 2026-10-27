.pragma library

// The browse picker's preview dial and card grid (PickerProvider.layout "browse"), kept here so node can test them.

var sizes = ["off", "s", "m", "l"];
// Share of the picker's body the preview takes at each size; the cards get whole rows of what is left.
var fractions = { off: 0, s: 0.35, m: 0.55, l: 0.7 };
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

// `area` is the height under the search bar, `body` the whole body's. At least one card row always shows, and the
// preview takes the rows' leftover so nothing is left blank below them.
function split(area, body, size, row_height, gap) {
    var s = size_of(size);
    if (s === "off" || area <= 0) return { rows: Math.max(1, Math.floor(area / row_height)), preview_height: 0 };
    var rows = Math.max(1, Math.floor((area - body * fractions[s] - gap) / row_height));
    return { rows: rows, preview_height: Math.max(0, area - rows * row_height - gap) };
}
