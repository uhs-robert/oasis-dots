.pragma library

// What a saved Theme option becomes when its row changed shape; Style.load_options runs each on a theme_options.json older than the version that introduced it,
// before the value is checked against the row's choices (an old value is not one yet).

// The Screen frame row used to hold "plain" with the corner profile in a separate Corners row. "plain" becomes the
// corner that style was drawing: its saved Corners choice, else the style's own hint, else round.
function screen_frame_from_plain(saved_corner, hint_corner, corners) {
    if (corners.indexOf(saved_corner) >= 0) return saved_corner;
    if (corners.indexOf(hint_corner) >= 0) return hint_corner;
    return "round";
}

// Version 4 split the Screen frame row: it became On/Off and its corner moved to the Corner style row. A style's saved
// options `saved` (screen_frame already a corner, see above) give { screen_frame: true, corner_style: v } for a saved
// corner and nothing for Off, which is the default. An unknown value is dropped as before, leaving the frame off.
function frame_to_bool(saved, corners) {
    const v = saved.screen_frame;
    if (typeof v === "boolean") return {};
    if (typeof v === "string" && corners.indexOf(v) >= 0) return { screen_frame: true, corner_style: v };
    return {};
}

// Flush single windows moved from each style to one global setting: off if any style had saved it off, so a choice to
// turn it off is never undone, and on otherwise.
function flush_from_styles(data) {
    for (const name in data) {
        if (data[name] && typeof data[name] === "object" && data[name].screen_frame_flush === false) return false;
    }
    return true;
}
