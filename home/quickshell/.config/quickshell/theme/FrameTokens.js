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
