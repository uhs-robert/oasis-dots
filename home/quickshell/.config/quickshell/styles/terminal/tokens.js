.pragma library

function overrides(t, ctx) {
    return {
        bar_icon_set: "terminal",
        bar_meeting_marker: "bracket_tag",
        wait_anim: "cursor",
        weather_header: "wttr",
        keeptabs_layout: "wttr",
        picker_skin: "tmux",
        picker_hint_keys: "123456789",
        // tmux's pane borders: the active pane's line and the inactive ones, from the palette.
        screen_frame_only: "square",
        screen_frame_panes: { active: t.theme_primary, inactive: t.fg_muted }
    };
}
