.pragma library

// Cursor and scroll arithmetic for the Wallpaper filmstrip, kept free of QML so a node test can drive it.

// The cursor after a key: h and l clamp at the ends (no wrap, as in vim), gg goes to the first image and G to the last.
// `count` is the number of images; an unknown action or an empty strip leaves the cursor where it is.
function move(cursor, action, count) {
    if (count <= 0) return 0;
    const top = count - 1;
    const here = Math.max(0, Math.min(top, cursor));
    if (action === "prev") return Math.max(0, here - 1);
    if (action === "next") return Math.min(top, here + 1);
    if (action === "first") return 0;
    if (action === "last") return top;
    return here;
}

// The monitor after j/k or Tab: it wraps, since a monitor list is short and has no ends to meet.
function step_monitor(target, delta, count) {
    if (count <= 0) return 0;
    return (((target + delta) % count) + count) % count;
}

// The scroll position that puts the cell at `index` in the middle of the view, also at the first and last image
// (the view then shows empty space beside the end cell, which keeps the cursor from jumping across the strip).
function centre_x(index, cell_width, view_width) {
    return index * cell_width - (view_width - cell_width) / 2;
}

// The index of `path` in `images`, or `fallback` when it is not listed.
function index_of(images, path, fallback) {
    const at = path ? images.indexOf(path) : -1;
    return at >= 0 ? at : fallback;
}

// The monitors (1-based, in list order) whose pin is `path`.
function pinned_on(monitors, pins, path) {
    const out = [];
    monitors.forEach((m, i) => {
        if (pins[m.key] === path) out.push(i + 1);
    });
    return out;
}

// The state of a `gg` chord after a key: `pending` is true after a lone g; a second g right after it asks for `first`.
// Any other key clears the chord, so g, x, g is not gg.
function gg(pending, is_g) {
    return { pending: is_g && !pending, first: is_g && pending };
}
