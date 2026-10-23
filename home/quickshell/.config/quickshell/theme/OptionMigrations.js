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
