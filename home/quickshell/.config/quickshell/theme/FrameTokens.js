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

// The Screen frame row's choices: Off or the one corner a style is fixed to (`only`), else Off and every corner.
function row_choices(only, all) {
    return only ? ["", only] : all;
}

// Whether a style offers the screen frame at all. Lualine is offered it: it runs as a strip along the frame's bar edge (Bar).
function offered(tokens) {
    return tokens.screen_frame_offered !== false;
}

// Whether a frame forces the bar to the full-bar shape. Lualine stays as it is: it has no Island shape row and draws its own sections.
function forces_full_bar(tokens) {
    return !tokens.bar_lualine && tokens.bar_island_shape !== "full";
}
