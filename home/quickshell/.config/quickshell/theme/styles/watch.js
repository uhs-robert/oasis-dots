.pragma library
.import "../Watch.js" as Watch

// The palette slots shared components draw with; goldeneye remaps them to the watch's fixed colours.
function palette(t) {
    return {
        error: t.error,
        warning: t.warning,
        ok: t.ok,
        info: t.info,
        hint: t.hint,
        primary: t.theme_primary,
        primary_light: t.theme_primary_light,
        primary_strong: t.theme_primary_strong,
        secondary: t.theme_secondary,
        secondary_strong: t.theme_secondary_strong,
        accent: t.theme_accent,
        today: t.theme_accent,
        label: t.theme_label,
        danger: t.theme_label,
        cursor: t.theme_cursor,
        fg: t.fg_core,
        fg_strong: t.fg_strong,
        fg_muted: t.fg_muted,
        fg_dim: t.fg_dim,
        border: t.ui_border,
        visual_bg: t.ui_visual_bg,
        bg_shadow: t.bg_shadow,
        bg_core: t.bg_core,
        bg_crust: t.bg_crust,
        bg_mantle: t.bg_mantle,
        bg_surface: t.bg_surface,
        magenta: t.magenta,
        bright_yellow: t.bright_yellow,
        bright_blue: t.bright_blue,
        bright_green: t.bright_green,
        bright_magenta: t.bright_magenta,
        bright_red: t.bright_red,
        cyan: t.cyan,
        bright_cyan: t.bright_cyan,
        red: t.red,
        green: t.green,
        yellow: t.yellow,
        blue: t.blue
    };
}

function tokens(pal, r) {
    return {
        wk: { lit: r.lit, mid: r.mid, soft: r.soft, dim: r.dim, bar_on: r.bar_on, bar_off: r.bar_off, panel_top: r.panel_top, panel_bottom: r.panel_bottom, edge: r.edge, frame: r.frame, rim: r.rim },
        pal: Object.assign({}, pal, {
            error: r.error,
            warning: r.warning,
            ok: r.state,
            info: r.info,
            hint: r.mid,
            primary: r.lit,
            primary_light: r.state,
            primary_strong: r.mid,
            secondary: r.secondary,
            secondary_strong: r.secondary_strong,
            accent: r.accent,
            today: r.today,
            label: r.lit,
            danger: r.error,
            cursor: r.lit,
            fg: r.mid,
            fg_strong: r.lit,
            fg_muted: r.soft,
            fg_dim: r.dim,
            border: Qt.alpha(r.lit, 0.5),
            visual_bg: Qt.alpha(r.lit, 0.22),
            bg_shadow: r.shadow,
            bg_core: r.ink,
            bg_crust: r.crust,
            bg_mantle: r.mantle,
            bg_surface: r.surface,
            magenta: Watch.cold_lit[2],
            bright_yellow: Watch.warm[7],
            bright_blue: Watch.cold_lit[6],
            bright_green: r.lit,
            bright_magenta: Watch.cold_lit[4],
            bright_red: Watch.red,
            cyan: Watch.cold_lit[5],
            bright_cyan: Watch.cold_lit[7],
            red: Watch.red,
            green: r.state,
            yellow: Watch.warm[5],
            blue: Watch.cold_lit[4]
        }),
        text_fg: r.mid,
        text_strong: r.lit,
        text_primary: r.lit,
        text_accent: r.state,
        text_muted: r.soft,
        text_dim: r.dim,
        frame_color: r.frame,
        frame_border_color: r.rim,
        lcd_top: r.panel_top,
        lcd_bottom: r.panel_bottom,
        accent_color: r.lit,
        selection_bg: Qt.alpha(r.lit, 0.22),
        selection_border: Qt.alpha(r.lit, 0.7),
        caret_color: r.lit,
        tab_active_bg: Qt.alpha(r.lit, 0.22),
        tab_active_fg: r.lit,
        tab_fg: r.mid,
        tab_underline: r.lit,
        key_fg: r.lit,
        key_border: Qt.alpha(r.lit, 0.5),
        section_fg: r.soft,
        section_fade: Qt.alpha(r.lit, 0.4),
        footer_fg: r.soft,
        footer_key_fg: r.lit,
        footer_rule_color: Qt.alpha(r.lit, 0.25),
        meter_on: r.bar_on,
        meter_off: r.bar_off,
        chart_fill: r.mid,
        title_fg: r.lit,
        title_readout_fg: r.dim,
        chip_active_bg: Qt.alpha(r.lit, 0.22),
        chip_active_fg: r.lit,
        chip_pick: r.lit,
        chip_border: Qt.alpha(r.lit, 0.5),
        card_edge: r.mid,
        toggle_on: r.state,
        toggle_off: r.dim,
        bar_clock_bg: r.clock_bg,
        bar_clock_fg: r.lit
    };
}

function classic_ramp() {
    return {
        lit: Watch.green, mid: Watch.green_mid, soft: Watch.green_soft, dim: Watch.green_dim, bar_on: Watch.bar_on, bar_off: Watch.bar_off,
        panel_top: Qt.rgba(Watch.panel_top[0], Watch.panel_top[1], Watch.panel_top[2], Watch.panel_top[3]),
        panel_bottom: Qt.rgba(Watch.panel_bottom[0], Watch.panel_bottom[1], Watch.panel_bottom[2], Watch.panel_bottom[3]),
        frame: Watch.black, rim: Watch.rim, edge: "transparent", shadow: Watch.black, ink: Watch.black, crust: Watch.black, mantle: "#031505", surface: "#0a2a10", clock_bg: "#04200a",
        state: Watch.white, accent: Watch.green, info: Watch.cold_lit[5], secondary: Watch.cold_lit[6], secondary_strong: Watch.cold_lit[4],
        error: Watch.red, warning: Watch.warm[5], today: Watch.red
    };
}

// The watch ramp from the palette's primary hue on a dark tinted panel, a little lighter than classic to keep its contrast on any palette.
function theme_ramp(t) {
    const rgba = a => Qt.rgba(a[0], a[1], a[2], a.length > 3 ? a[3] : 1);
    const rgb_of = c => [Qt.color(c).r, Qt.color(c).g, Qt.color(c).b];
    const theme_base = Qt.color(t.theme_primary);
    const wr = Watch.theme_ramp(Math.max(0, theme_base.hslHue), Watch.sat_of(theme_base), rgb_of(t.bg_surface), rgb_of(t.bg_mantle), Qt.color(t.bg_crust).hslLightness > 0.5 ? 0.96 : 0.8, rgb_of(t.bg_crust));
    return {
        lit: rgba(wr.lit), mid: rgba(wr.mid), soft: rgba(wr.soft), dim: rgba(wr.dim), bar_on: rgba(wr.bar_on), bar_off: rgba(wr.bar_off),
        panel_top: rgba(wr.panel_top), panel_bottom: rgba(wr.panel_bottom), edge: rgba(wr.edge),
        frame: t.bg_crust, rim: Qt.tint(t.bg_crust, Qt.alpha(t.fg_muted, 0.5)), shadow: t.bg_shadow, ink: t.bg_core, crust: t.bg_crust, mantle: t.bg_mantle, surface: t.bg_surface, clock_bg: rgba(wr.clock_bg),
        state: t.theme_accent, accent: t.theme_accent, info: t.theme_secondary, secondary: t.theme_secondary, secondary_strong: t.theme_secondary_strong,
        error: t.error, warning: t.warning, today: t.error
    };
}
