.pragma library

// The screen frame's token-dependent choices, kept out of Style.qml so tests/island_shapes.js can run them.

// The frame line's colour on the focused monitor or another: the style's screen_frame_panes pair when it has one, else `bar` (the bar border and its dimmed mix).
function rim_color(panes, focused, bar_focused, bar_other) {
    if (panes) return focused ? panes.active : panes.inactive;
    return focused ? bar_focused : bar_other;
}

// The line's width, drawn by ScreenFrame and sent to Hyprland as its border size by ScreenFrameSync: tmux's pane lines are one cell wide, whatever the bar border is.
function rim_width(panes, bar_border_width) {
    return panes ? 1 : bar_border_width;
}

// The Corner style row's choices: the one corner a style is fixed to (`only`), else every corner.
function row_choices(only, all) {
    return only ? [only] : all;
}

// The corner a style draws when nothing is chosen: the one it is fixed to, else its screen_frame_corners hint, else round.
function natural_corner(tokens, corners) {
    if (tokens.screen_frame_only) return tokens.screen_frame_only;
    return corners.indexOf(tokens.screen_frame_corners) >= 0 ? tokens.screen_frame_corners : "round";
}

// The corner profile a token set draws, frame on or off: the fixed one, else the chosen corner_style, else the natural corner.
function corner_of(tokens, corners) {
    if (tokens.screen_frame_only) return tokens.screen_frame_only;
    return corners.indexOf(tokens.corner_style) >= 0 ? tokens.corner_style : natural_corner(tokens, corners);
}

// Whether a Corner style was picked (saved, even the natural corner), as opposed to the style's own left untouched.
function corner_chosen(tokens, corners) {
    return corners.indexOf(tokens.corner_style) >= 0;
}

// Whether the Corner style reaches Hyprland and the apps: always with the frame on, with it off only once the user has
// picked one, so an untouched style leaves the owner's own window rounding as it is.
function corner_applies(frame_on, corner_chosen) {
    return frame_on || corner_chosen;
}

// What ScreenFrameSync tells Hyprland: "frame" when a screen draws the frame, "corner" for the Corner style alone (the
// frame off, or on but drawn on no screen, as with only side bars), else "clear" to leave the owner's own values.
function sync_mode(frame_on, any_frame, corner_sent) {
    if (frame_on && any_frame) return "frame";
    return corner_sent ? "corner" : "clear";
}

// Whether a token set draws the screen frame: a style that offers it, with it switched on.
function frame_on(tokens) {
    return offered(tokens) && tokens.screen_frame === true;
}

// Whether a style offers the screen frame at all. Lualine is offered it: it runs as a strip along the frame's bar edge (Bar).
function offered(tokens) {
    return tokens.screen_frame_offered !== false;
}

// Whether a frame forces the bar to the full-bar shape. Lualine stays as it is: it has no Island shape row and draws its own sections.
function forces_full_bar(tokens) {
    return !tokens.bar_lualine && tokens.bar_island_shape !== "full";
}

// The monitors that draw the frame, as Hyprland monitor strings for ScreenFrame.set's list: "desc:" and the
// description, which survives a replug that renames the connector, else the connector name. The connector also stands
// in for a description two screens share (Hyprland's desc: picks only the first match) or one holding "]" (it would
// end the m[] selector frame.lua puts it in). Each screen is { name, description, framed }.
function framed_monitors(screens) {
    const shared = d => screens.filter(s => s.description === d).length > 1;
    const keys = [];
    for (const s of screens) {
        if (!s.framed) continue;
        const usable = s.description && s.description.indexOf("]") < 0 && !shared(s.description);
        const key = usable ? "desc:" + s.description : s.name;
        if (key && keys.indexOf(key) < 0) keys.push(key);
    }
    return keys;
}

// A list of strings as a Lua table literal, for a Hyprland dispatch: JSON's string quoting is valid Lua for text with no control characters.
function lua_string_list(items) {
    return "{" + items.map(s => JSON.stringify(String(s))).join(", ") + "}";
}
