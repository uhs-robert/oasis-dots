// home/quickshell/.config/quickshell/theme/Style.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string name: "default"
    // The saved choice; `name` differs from it only while the style picker previews.
    property string saved_name: "default"
    readonly property var names: Object.keys(root.styles)

    readonly property var styles: {
        const terminal = {
            text_muted: Theme.fg_muted,
            text_dim: Theme.fg_dim,
            text_fg: Theme.fg_core,
            text_strong: Theme.fg_strong,
            text_primary: Theme.theme_primary,
            text_accent: Theme.theme_secondary,
            font_family: "JetBrainsMono Nerd Font",
            font_size: Theme.popup_font_size + 2,
            number_font: "",
            title_font_family: "",
            rounded: false,
            frame_follows_island: false,
            frame_color: Theme.bg_crust,
            frame_radius: 0,
            frame_border_width: 1,
            frame_border_color: Theme.fg_muted,
            frame_chamfer: 0,
            frame_visor: false,
            frame_brackets: "transparent",
            frame_inset_gap: 0,
            frame_inset_width: 0,
            frame_inset_color: "transparent",
            frame_pad: 0,
            frame_drop: 0,
            lcd_top: "transparent",
            lcd_bottom: "transparent",
            lcd_scan: "transparent",
            lcd_margin: 0,
            frame_engraving: "",
            accent_color: Theme.theme_secondary,
            accent_height: 3,
            accent_full_width: true,
            frame_top_rule: false,
            selection_bg: "transparent",
            selection_inverse: false,
            selection_fg: Theme.bg_crust,
            caret_color: Theme.theme_secondary,
            caret_blink: true,
            selection_outline: Qt.alpha(Theme.theme_secondary, 0.6),
            tab_active_bg: Theme.theme_secondary,
            tab_active_fg: Theme.bg_crust,
            tab_fg: Theme.fg_muted,
            tab_caps: false,
            tab_underline: "transparent",
            key_bg: "transparent",
            key_fg: Theme.fg_muted,
            key_border: Theme.bg_surface,
            section_fg: Theme.fg_muted,
            section_rule: true,
            label_caps: false,
            label_spacing: 0,
            section_fade: "transparent",
            footer_fg: Theme.fg_muted,
            footer_key_fg: Theme.theme_secondary,
            footer_rule: true,
            footer_rule_color: Theme.bg_surface,
            meter_on: Theme.theme_primary,
            meter_off: Theme.bg_surface,
            meter_hot: Theme.theme_label,
            meter_radius: 0,
            meter_outline: "transparent",
            scale: 1.15,
            popup_min_width: 0,
            show_title: true,
            title_bg: Theme.theme_secondary,
            title_fg: Theme.bg_crust,
            show_footer: true,
            footer_wrap: true,
            row_cursor: ">",
            segmented_levels: true,
            tab_keys: true,
            row_keys: true,
            boxed_cards: true,
            chip_brackets: true,
            chip_active_bg: "transparent",
            chip_active_fg: Theme.theme_primary,
            chip_pick: Theme.theme_secondary,
            chip_border: "transparent",
            card_edge: "transparent",
            toggle_brackets: true,
            toggle_on: Theme.ok,
            toggle_off: Theme.fg_muted,
            marker_fill: true,
            selection_bar: false,
            title_prefix: "",
            title_suffix: "",
            title_spacing: 2,
            title_glow: "transparent",
            title_readout: "",
            title_readout_fg: "transparent",
            title_rule: "transparent",
            frame_glow: "transparent",
            scanlines: false,
            scanline_color: "transparent",
            glow: false,
            glow_color: "transparent",
            glow_tint: 0,
            frame_shade: "transparent",
            shade_vertical: false,
            dither: "transparent",
            text_shadow: "transparent",
            fade_fills: false,
            selection_border: "transparent",
            selection_glow: "transparent",
            slant: 0,
            meter_shade: "transparent",
            meter_slant: 0,
            meter_bloom: false,
            chart_slant: 0,
            chart_fill: Theme.yellow,
            corner_scale: 1,
            bar_font_family: "JetBrainsMono Nerd Font",
            bar_font_size: Theme.font_size,
            bar_caps: false,
            bar_letter_spacing: 0,
            bar_side_bg: Theme.bg_crust,
            bar_center_bg: Theme.bg_crust,
            bar_fg: Theme.fg_core,
            bar_clock_bg: "transparent",
            bar_clock_fg: Theme.fg_core,
            bar_clock_font: "",
            bar_border_width: 1,
            bar_border_color: Theme.fg_muted,
            bar_rounded: false,
            bar_workspace_focused: Theme.theme_secondary,
            bar_workspace_active: Theme.theme_primary,
            bar_workspace_idle: Theme.bg_surface,
            bar_workspace_ring: "transparent",
            bar_inset_gap: 0,
            bar_inset_width: 0,
            bar_inset_color: "transparent",
            bar_hover_bg: Theme.bg_surface,
            bar_glow_color: "transparent",
            bar_text_raised: false,
            done_anim: "hearts",
            bar_scanline_color: "transparent"
        };
        return {
            "default": {
                text_muted: Theme.fg_muted,
                text_dim: Theme.fg_dim,
                text_fg: Theme.fg_core,
                text_strong: Theme.fg_strong,
                text_primary: Theme.theme_primary,
                text_accent: Theme.theme_secondary,
                font_family: Theme.font_family,
                font_size: Theme.popup_font_size,
                number_font: "",
                title_font_family: "",
                rounded: true,
                frame_follows_island: true,
                frame_color: Theme.bg_mantle,
                frame_radius: 10,
                frame_border_width: 0,
                frame_border_color: "transparent",
                frame_chamfer: 0,
                frame_visor: false,
                frame_brackets: "transparent",
                frame_inset_gap: 0,
                frame_inset_width: 0,
                frame_inset_color: "transparent",
                frame_pad: 0,
                frame_drop: 0,
                lcd_top: "transparent",
                lcd_bottom: "transparent",
                lcd_scan: "transparent",
                lcd_margin: 0,
                frame_engraving: "",
                accent_color: Theme.theme_primary,
                accent_height: 3,
                accent_full_width: false,
                frame_top_rule: false,
                selection_bg: Theme.bg_surface,
                selection_inverse: false,
                selection_fg: Theme.bg_crust,
                caret_color: Theme.theme_primary,
                caret_blink: false,
                selection_outline: "transparent",
                tab_active_bg: Theme.bg_surface,
                tab_active_fg: Theme.theme_secondary,
                tab_fg: Theme.fg_muted,
                tab_caps: false,
                tab_underline: "transparent",
                key_bg: Theme.bg_mantle,
                key_fg: Theme.fg_dim,
                key_border: Theme.ui_border,
                section_fg: Theme.fg_muted,
                section_rule: false,
                label_caps: false,
                label_spacing: 0,
                section_fade: "transparent",
                footer_fg: Theme.fg_dim,
                footer_key_fg: Theme.theme_secondary,
                footer_rule: false,
                footer_rule_color: Theme.bg_surface,
                meter_on: Theme.theme_primary,
                meter_off: Theme.bg_surface,
                meter_hot: Theme.theme_label,
                meter_radius: 1,
                meter_outline: "transparent",
                scale: 1,
                popup_min_width: 0,
                show_title: false,
                title_bg: Theme.theme_secondary,
                title_fg: Theme.bg_crust,
                show_footer: false,
                footer_wrap: false,
                row_cursor: "",
                segmented_levels: false,
                tab_keys: false,
                row_keys: false,
                boxed_cards: false,
                chip_brackets: false,
                chip_active_bg: Theme.bg_surface,
                chip_active_fg: Theme.theme_secondary,
                chip_pick: Theme.theme_secondary,
                chip_border: "transparent",
                card_edge: "transparent",
                toggle_brackets: false,
                toggle_on: Theme.theme_primary,
                toggle_off: Theme.fg_dim,
                marker_fill: false,
                selection_bar: false,
                title_prefix: "",
                title_suffix: "",
                title_spacing: 2,
                title_glow: "transparent",
                title_readout: "",
                title_readout_fg: "transparent",
                title_rule: "transparent",
                frame_glow: "transparent",
                scanlines: false,
                scanline_color: "transparent",
                glow: false,
                glow_color: "transparent",
                glow_tint: 0,
                frame_shade: "transparent",
                shade_vertical: false,
                dither: "transparent",
                text_shadow: "transparent",
                fade_fills: false,
                selection_border: "transparent",
                selection_glow: "transparent",
                slant: 0,
                meter_shade: "transparent",
                meter_slant: 0,
                meter_bloom: false,
                chart_slant: 0,
                chart_fill: Theme.yellow,
                corner_scale: 1,
                bar_font_family: Theme.font_family,
                bar_font_size: Theme.font_size,
                bar_caps: false,
                bar_letter_spacing: 0,
                bar_side_bg: Theme.bg_core,
                bar_center_bg: Theme.bg_mantle,
                bar_fg: Theme.fg_core,
                bar_clock_bg: "transparent",
                bar_clock_fg: Theme.fg_core,
                bar_clock_font: "",
                bar_border_width: 1,
                bar_border_color: Qt.alpha(Theme.ui_border, 0.5),
                bar_rounded: true,
                bar_workspace_focused: Theme.theme_secondary,
                bar_workspace_active: Theme.theme_primary,
                bar_workspace_idle: Theme.bg_surface,
                bar_workspace_ring: "transparent",
                bar_inset_gap: 0,
                bar_inset_width: 0,
                bar_inset_color: "transparent",
            bar_inset_gap: 0,
            bar_inset_width: 0,
            bar_inset_color: "transparent",
                bar_hover_bg: Theme.bg_surface,
                bar_glow_color: "transparent",
                bar_text_raised: false,
                done_anim: "hearts",
                bar_scanline_color: "transparent"
            },
            "terminal": terminal,
            "crt": Object.assign({}, terminal, {
                text_muted: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.35)),
                text_dim: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.6)),
                // VT323 is tall and narrow; 24 matches the old cap height with room to spare across.
                font_family: "VT323",
                font_size: Theme.popup_font_size + 9,
                frame_border_color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.theme_primary, 0.35)),
                frame_glow: Theme.ui_visual_bg,
                accent_color: Theme.theme_primary,
                selection_bg: Qt.alpha(Theme.theme_primary, 0.14),
                selection_outline: "transparent",
                selection_bar: true,
                row_cursor: "\u25b6",
                tab_active_bg: Qt.alpha(Theme.theme_primary, 0.2),
                tab_active_fg: Theme.theme_secondary,
                tab_fg: Theme.theme_primary_strong,
                key_fg: Theme.theme_secondary,
                key_border: Qt.alpha(Theme.theme_secondary, 0.35),
                section_fg: Theme.theme_primary_strong,
                footer_fg: Theme.theme_primary_strong,
                footer_rule_color: Qt.alpha(Theme.theme_primary, 0.3),
                meter_off: Qt.alpha(Theme.theme_primary, 0.15),
                meter_hot: Theme.theme_label,
                title_bg: "transparent",
                title_fg: Theme.theme_secondary,
                title_prefix: "> ",
                title_suffix: "_",
                chip_active_fg: Theme.theme_secondary,
                scanlines: true,
                scanline_color: Qt.alpha(Theme.bg_shadow, 0.3),
                glow: true,
                glow_color: Theme.theme_primary,
                glow_tint: 0.25,
                bar_font_family: "VT323",
                bar_font_size: Theme.font_size + 5,
                bar_fg: Theme.theme_primary_light,
                bar_border_color: Qt.alpha(Theme.theme_primary, 0.5),
                bar_hover_bg: Qt.alpha(Theme.theme_primary, 0.4),
                bar_glow_color: Qt.alpha(Theme.theme_primary, 0.3),
                bar_scanline_color: Qt.alpha(Theme.theme_primary, 0.07)
            }),
            "nes": Object.assign({}, terminal, {
                done_anim: "pixel",
                text_muted: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.35)),
                text_dim: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.6)),
                // Press Start 2P draws on an 8px grid and runs 1em wide; 14 sits between its 1.5x and 2x sizes, with a wider frame.
                font_family: "Press Start 2P",
                font_size: 14,
                scale: 1.2,
                popup_min_width: 295,
                frame_color: Theme.bg_crust,
                frame_border_width: 0,
                frame_border_color: "transparent",
                frame_inset_gap: 4,
                frame_inset_width: 3,
                frame_inset_color: Theme.fg_strong,
                accent_color: Theme.theme_primary,
                accent_height: 4,
                selection_bg: "transparent",
                selection_outline: "transparent",
                caret_color: Theme.theme_primary,
                row_cursor: "\u25b6",
                tab_active_bg: Theme.theme_primary,
                tab_active_fg: Theme.bg_crust,
                tab_fg: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.35)),
                key_bg: "transparent",
                key_fg: Theme.theme_secondary,
                key_border: "transparent",
                section_fg: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.35)),
                section_rule: false,
                footer_fg: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.35)),
                footer_rule: false,
                meter_on: Theme.theme_primary,
                meter_off: Theme.bg_surface,
                meter_hot: Theme.theme_label,
                meter_radius: 0,
                title_bg: "transparent",
                title_fg: Theme.theme_primary,
                chip_brackets: false,
                chip_active_bg: Theme.theme_primary,
                chip_active_fg: Theme.bg_crust,
                toggle_on: Theme.theme_primary,
                toggle_off: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.35)),
                bar_font_family: "Press Start 2P",
                bar_font_size: 14,
                bar_side_bg: Theme.bg_crust,
                bar_center_bg: Theme.bg_crust,
                bar_fg: Theme.fg_strong,
                bar_border_width: 0,
                bar_border_color: "transparent",
                bar_inset_gap: 2,
                bar_inset_width: 2,
                bar_inset_color: Theme.fg_strong
            }),
            "snes": Object.assign({}, terminal, {
                done_anim: "pixel",
                // Greys lifted toward primary_light so they read on the shaded window.
                text_muted: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.4)),
                text_dim: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.65)),
                // Silkscreen sits on an 8px grid; 16 is its 2x size.
                font_family: "Silkscreen",
                font_size: 16,
                frame_color: Theme.bg_crust,
                frame_shade: Theme.bg_mantle,
                shade_vertical: true,
                frame_radius: 6,
                frame_border_width: 3,
                frame_border_color: Theme.theme_primary,
                frame_inset_width: 2,
                frame_inset_color: Theme.fg_muted,
                frame_drop: 4,
                accent_color: Theme.theme_secondary,
                accent_height: 4,
                selection_bg: Qt.alpha(Theme.fg_strong, 0.12),
                selection_outline: "transparent",
                caret_color: Theme.theme_secondary,
                caret_blink: false,
                row_cursor: "\uf0a4",
                tab_active_bg: Qt.alpha(Theme.fg_strong, 0.12),
                tab_active_fg: Theme.theme_secondary,
                tab_fg: Theme.theme_primary_light,
                key_fg: Theme.theme_secondary,
                key_border: "transparent",
                section_fg: Theme.theme_primary_light,
                section_rule: false,
                footer_fg: Theme.theme_primary_light,
                footer_rule: false,
                meter_shade: Theme.theme_primary_light,
                meter_radius: 1,
                title_bg: "transparent",
                title_fg: Theme.theme_secondary,
                chip_brackets: false,
                chip_active_bg: Qt.alpha(Theme.fg_strong, 0.12),
                chip_active_fg: Theme.theme_secondary,
                toggle_brackets: false,
                toggle_on: Theme.theme_secondary,
                toggle_off: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.65)),
                text_shadow: Theme.bg_shadow,
                bar_font_family: "Silkscreen",
                bar_font_size: 16,
                bar_side_bg: Theme.bg_core,
                bar_center_bg: Theme.bg_core,
                bar_border_width: 2,
                bar_border_color: Theme.theme_primary,
                bar_workspace_idle: Theme.bg_mantle,
                bar_workspace_ring: Theme.theme_primary,
                bar_hover_bg: Qt.alpha(Theme.theme_primary, 0.3),
                bar_glow_color: Theme.bg_shadow,
                bar_text_raised: true
            }),
            "ps1": Object.assign({}, terminal, {
                done_anim: "pixel",
                // Muted text brightened; the shaded, dithered frame swallows the theme greys.
                text_muted: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.35)),
                text_dim: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.6)),
                font_family: "Terminess Nerd Font",
                font_size: Theme.popup_font_size + 6,
                frame_color: Theme.bg_crust,
                frame_shade: Theme.bg_mantle,
                frame_radius: 10,
                frame_border_width: 2,
                frame_border_color: Theme.fg_dim,
                accent_color: Theme.theme_primary,
                selection_bg: Qt.alpha(Theme.theme_primary, 0.35),
                selection_outline: "transparent",
                fade_fills: true,
                caret_color: Theme.theme_primary_light,
                row_cursor: "◆",
                tab_active_bg: Qt.alpha(Theme.theme_primary, 0.35),
                tab_active_fg: Theme.fg_strong,
                tab_fg: Theme.theme_primary_light,
                key_fg: Theme.theme_secondary,
                key_border: "transparent",
                section_fg: Theme.theme_primary_light,
                section_rule: false,
                footer_fg: Theme.theme_primary_light,
                footer_rule: false,
                meter_shade: Theme.theme_primary_light,
                meter_off: Theme.bg_shadow,
                title_bg: Qt.alpha(Theme.theme_primary, 0.3),
                title_fg: Theme.fg_strong,
                chip_brackets: false,
                chip_active_bg: Qt.alpha(Theme.theme_primary, 0.35),
                chip_active_fg: Theme.fg_strong,
                dither: Qt.alpha(Theme.bg_shadow, 0.22),
                text_shadow: Theme.bg_shadow,
                bar_font_family: "Terminess Nerd Font",
                bar_font_size: Theme.font_size + 4,
                bar_side_bg: Theme.bg_core,
                bar_center_bg: Theme.bg_mantle,
                bar_border_color: Theme.fg_dim,
                bar_workspace_idle: Qt.alpha(Theme.fg_dim, 0.35),
                bar_hover_bg: Qt.alpha(Theme.theme_primary, 0.35),
                bar_glow_color: Theme.bg_shadow,
                bar_text_raised: true
            }),
            // Perfect Dark panels; `small` turns the small popups into the Q-branch watch LCD.
            "goldeneye": Object.assign({}, terminal, {
                done_anim: "lcd",
                text_muted: Qt.tint(Theme.fg_muted, Qt.alpha(Theme.fg_core, 0.3)),
                text_dim: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.2)),
                font_family: "Share Tech Mono",
                title_font_family: "Michroma",
                number_font: "DSEG7 Classic",
                frame_color: Theme.bg_crust,
                frame_shade: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.ui_visual_bg, 0.6)),
                frame_border_color: Qt.alpha(Theme.theme_label, 0.6),
                frame_chamfer: 14,
                accent_color: Theme.theme_label,
                accent_height: 2,
                frame_top_rule: true,
                selection_bg: Qt.alpha(Theme.theme_label, 0.16),
                selection_outline: "transparent",
                selection_bar: true,
                caret_color: Theme.theme_label,
                caret_blink: false,
                row_cursor: "",
                tab_active_bg: "transparent",
                tab_active_fg: Theme.fg_strong,
                tab_fg: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.2)),
                tab_caps: true,
                tab_underline: Theme.theme_label,
                key_fg: Theme.theme_secondary,
                key_border: Qt.alpha(Theme.theme_secondary, 0.5),
                section_fg: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.2)),
                section_rule: false,
                section_fade: Qt.alpha(Theme.theme_label, 0.5),
                label_caps: true,
                label_spacing: 2,
                footer_fg: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.2)),
                footer_rule_color: Qt.alpha(Theme.theme_label, 0.25),
                meter_on: Theme.theme_primary_light,
                meter_off: Theme.bg_surface,
                meter_slant: 0.36,
                chart_slant: 0.21,
                chart_fill: Theme.theme_secondary,
                title_bg: "transparent",
                title_fg: Theme.fg_strong,
                title_spacing: 4,
                title_readout: "CI · {code}-07",
                title_readout_fg: Theme.theme_label,
                chip_brackets: false,
                chip_active_bg: Theme.theme_label,
                chip_active_fg: Theme.bg_crust,
                chip_pick: Theme.theme_label,
                chip_border: Qt.alpha(Theme.theme_label, 0.5),
                card_edge: Theme.theme_label,
                toggle_on: Theme.theme_primary_light,
                toggle_off: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.2)),
                marker_fill: false,
                bar_font_family: "Michroma",
                bar_font_size: Theme.font_size - 3,
                bar_caps: true,
                bar_letter_spacing: 1.5,
                bar_side_bg: Theme.bg_crust,
                bar_center_bg: Theme.bg_crust,
                bar_border_color: Qt.alpha(Theme.theme_label, 0.5),
                bar_hover_bg: Qt.alpha(Theme.theme_label, 0.18),
                bar_clock_bg: Theme.theme_primary_light,
                bar_clock_fg: Theme.bg_core,
                bar_clock_font: "DSEG7 Classic",
                small: {
                    text_fg: Theme.theme_primary_light,
                    text_strong: Theme.fg_strong,
                    text_primary: Theme.theme_primary,
                    text_accent: Theme.theme_label,
                    text_muted: Qt.alpha(Theme.theme_primary_light, 0.6),
                    text_dim: Qt.alpha(Theme.theme_primary_light, 0.78),
                    title_font_family: "Share Tech Mono",
                    frame_shade: Theme.bg_surface,
                    shade_vertical: true,
                    frame_radius: 22,
                    frame_chamfer: 0,
                    frame_border_width: 2,
                    frame_border_color: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_muted, 0.4)),
                    frame_inset_width: 3,
                    frame_inset_color: Theme.bg_shadow,
                    lcd_top: Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.theme_primary, 0.2)),
                    lcd_bottom: Qt.tint(Theme.bg_core, Qt.alpha(Theme.theme_primary, 0.12)),
                    lcd_scan: Qt.alpha(Theme.bg_shadow, 0.3),
                    lcd_margin: 7,
                    frame_engraving: "Q BRANCH",
                    accent_color: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_muted, 0.4)),
                    frame_top_rule: false,
                    selection_bg: Theme.theme_primary_light,
                    selection_inverse: true,
                    selection_fg: Theme.bg_core,
                    selection_bar: false,
                    caret_color: Theme.bg_core,
                    row_cursor: "▸",
                    tab_active_bg: Theme.theme_primary_light,
                    tab_active_fg: Theme.bg_core,
                    tab_fg: Qt.alpha(Theme.theme_primary_light, 0.6),
                    tab_caps: false,
                    tab_underline: "transparent",
                    key_fg: Theme.theme_primary_light,
                    key_border: Qt.alpha(Theme.theme_primary_light, 0.6),
                    section_fg: Theme.theme_primary_light,
                    section_fade: Qt.alpha(Theme.theme_primary_light, 0.35),
                    footer_fg: Qt.alpha(Theme.theme_primary_light, 0.6),
                    footer_key_fg: Theme.theme_primary_light,
                    footer_rule_color: Qt.alpha(Theme.theme_primary_light, 0.3),
                    meter_on: Theme.theme_primary_light,
                    meter_off: Qt.alpha(Theme.theme_primary_light, 0.15),
                    meter_hot: Theme.theme_label,
                    meter_slant: 0.32,
                    title_bg: Theme.theme_primary_light,
                    title_fg: Theme.bg_core,
                    title_spacing: 2,
                    title_readout: "WATCH   MAG",
                    title_readout_fg: Qt.alpha(Theme.theme_primary_light, 0.7),
                    title_rule: Qt.alpha(Theme.theme_primary_light, 0.3),
                    chip_active_bg: Theme.theme_primary_light,
                    chip_active_fg: Theme.bg_core,
                    chip_pick: Theme.theme_primary_light,
                    chip_border: Qt.alpha(Theme.theme_primary_light, 0.6),
                    card_edge: "transparent",
                    toggle_on: Theme.theme_primary_light,
                    toggle_off: Qt.alpha(Theme.theme_primary_light, 0.45)
                }
            }),
            "scifi":Object.assign({}, terminal, {
                text_muted: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.35)),
                text_dim: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.6)),
                frame_color: Theme.bg_crust,
                frame_shade: Theme.bg_mantle,
                shade_vertical: true,
                frame_border_width: 0,
                frame_border_color: "transparent",
                frame_chamfer: 14,
                frame_brackets: Theme.theme_primary,
                accent_color: Theme.theme_primary,
                accent_height: 2,
                selection_bg: Qt.alpha(Theme.theme_primary, 0.18),
                selection_outline: "transparent",
                slant: 0.28,
                caret_color: Theme.theme_primary,
                caret_blink: false,
                row_cursor: "\u00bb",
                tab_active_bg: Qt.alpha(Theme.theme_primary, 0.18),
                tab_active_fg: Theme.fg_strong,
                tab_fg: Theme.theme_primary_light,
                key_fg: Theme.theme_primary,
                key_border: Qt.alpha(Theme.theme_primary, 0.6),
                section_fg: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.35)),
                section_rule: false,
                section_fade: Qt.alpha(Theme.theme_primary, 0.6),
                label_caps: true,
                label_spacing: 2,
                footer_fg: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.35)),
                footer_rule: false,
                meter_off: Theme.ui_visual_bg,
                meter_slant: 0.45,
                meter_bloom: true,
                title_bg: "transparent",
                title_fg: Theme.theme_primary,
                title_spacing: 4,
                title_glow: Qt.alpha(Theme.theme_primary, 0.45),
                title_readout: "SYS 07.3 \u25a0\u25a0\u25a1",
                chip_brackets: false,
                chip_active_bg: Qt.alpha(Theme.theme_primary, 0.18),
                chip_active_fg: Theme.fg_strong,
                toggle_on: Theme.theme_primary,
                toggle_off: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.35)),
                bar_caps: true,
                bar_letter_spacing: 1,
                bar_fg: Theme.theme_primary_light,
                bar_border_color: Theme.theme_primary,
                bar_workspace_idle: Theme.ui_visual_bg,
                bar_hover_bg: Qt.alpha(Theme.theme_primary, 0.18),
                bar_glow_color: Qt.alpha(Theme.theme_primary, 0.2)
            }),
            "metroid": Object.assign({}, terminal, {
                // Greys lifted toward primary_light so they read on the visor glass.
                text_muted: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.4)),
                text_dim: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.65)),
                font_family: "Share Tech Mono",
                font_size: Theme.popup_font_size + 2,
                number_font: "Orbitron",
                rounded: true,
                frame_visor: true,
                frame_pad: 6,
                frame_color: Theme.bg_crust,
                frame_radius: 14,
                frame_border_width: 1,
                frame_border_color: Qt.alpha(Theme.theme_primary, 0.45),
                accent_color: Theme.theme_primary,
                accent_height: 0,
                selection_bg: Qt.alpha(Theme.theme_primary, 0.2),
                selection_outline: "transparent",
                selection_bar: true,
                fade_fills: true,
                caret_color: Theme.theme_secondary,
                caret_blink: false,
                row_cursor: "",
                tab_active_bg: Qt.alpha(Theme.theme_primary, 0.15),
                tab_active_fg: Theme.fg_strong,
                tab_fg: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.4)),
                key_fg: Theme.theme_secondary,
                key_border: Qt.alpha(Theme.theme_secondary, 0.45),
                section_fg: Theme.theme_primary,
                section_rule: false,
                section_fade: Qt.alpha(Theme.theme_primary, 0.5),
                label_caps: true,
                label_spacing: 2.5,
                footer_fg: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.4)),
                footer_rule: false,
                meter_off: Qt.alpha(Theme.theme_primary, 0.06),
                meter_radius: 1,
                meter_outline: Qt.alpha(Theme.theme_primary, 0.55),
                title_bg: "transparent",
                title_fg: Theme.theme_primary,
                title_spacing: 3,
                title_readout: "SCAN VISOR",
                title_readout_fg: Theme.theme_primary,
                chip_brackets: false,
                chip_active_bg: Theme.theme_secondary,
                chip_active_fg: Theme.bg_crust,
                toggle_brackets: false,
                toggle_on: Theme.theme_primary,
                toggle_off: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.4)),
                bar_font_family: "Share Tech Mono",
                bar_font_size: Theme.font_size + 1,
                bar_side_bg: Qt.alpha(Theme.bg_crust, 0.95),
                bar_center_bg: Qt.alpha(Theme.bg_crust, 0.95),
                bar_fg: Theme.theme_primary_light,
                bar_border_color: Qt.alpha(Theme.theme_primary, 0.5),
                bar_workspace_idle: Qt.alpha(Theme.theme_primary, 0.18),
                bar_hover_bg: Qt.alpha(Theme.theme_primary, 0.18),
                small: {
                    title_readout: "COMBAT VISOR"
                }
            }),
            "ps2": Object.assign({}, terminal, {
                done_anim: "pixel",
                font_family: "Exo 2",
                font_size: Theme.popup_font_size + 1,
                rounded: true,
                corner_scale: 2.5,
                frame_color: Theme.bg_mantle,
                frame_radius: 14,
                frame_border_width: 0,
                frame_border_color: "transparent",
                accent_color: Theme.theme_primary,
                accent_height: 2,
                selection_bg: Qt.alpha(Theme.theme_primary, 0.14),
                selection_outline: "transparent",
                selection_border: Qt.alpha(Theme.theme_primary_light, 0.35),
                selection_glow: Qt.alpha(Theme.theme_primary, 0.35),
                caret_color: Theme.theme_primary_light,
                caret_blink: false,
                row_cursor: "",
                tab_active_bg: Qt.alpha(Theme.theme_primary, 0.14),
                tab_active_fg: Theme.fg_strong,
                tab_fg: Theme.theme_primary_light,
                key_fg: Theme.theme_primary,
                key_border: Qt.alpha(Theme.theme_primary, 0.4),
                section_fg: Theme.theme_primary,
                section_rule: false,
                footer_fg: Theme.theme_primary_strong,
                footer_rule: false,
                meter_shade: Theme.theme_primary_light,
                meter_off: Qt.alpha(Theme.theme_primary, 0.1),
                meter_radius: 2,
                title_bg: "transparent",
                title_fg: Theme.fg_strong,
                chip_brackets: false,
                chip_active_bg: Qt.alpha(Theme.theme_primary, 0.14),
                chip_active_fg: Theme.fg_strong,
                toggle_brackets: false,
                toggle_on: Theme.theme_primary,
                toggle_off: Theme.fg_dim,
                marker_fill: false,
                bar_font_family: "Exo 2",
                bar_font_size: Theme.font_size,
                bar_side_bg: Theme.bg_mantle,
                bar_center_bg: Theme.bg_mantle,
                bar_fg: Theme.theme_primary_light,
                bar_border_width: 0,
                bar_border_color: "transparent",
                bar_rounded: true,
                bar_workspace_idle: Qt.alpha(Theme.theme_primary, 0.12),
                bar_hover_bg: Qt.alpha(Theme.theme_primary, 0.2)
            })
        };
    }

    readonly property var active: root.styles[root.name] || root.styles["default"]
    // Small popups read this token set; it is the singleton itself unless the style has a `small` block.
    readonly property var small: root.active.small ? root.resolve(Object.assign({}, root.active, root.active.small)) : root

    // The token set for an item: small inside a popup whose size_class is small, else this singleton.
    function for_item(item) {
        for (let p = item; p; p = p.parent) {
            if (p.size_class !== undefined) return p.size_class === "small" ? root.small : root;
        }
        return root;
    }

    // A raw style object with its colors typed and its derived tokens filled, like the properties below.
    function resolve(d) {
        const o = {};
        for (const k in d) {
            const v = d[k];
            o[k] = typeof v === "string" && (v === "transparent" || v.startsWith("#")) ? Qt.tint(v, "transparent") : v;
        }
        o.title_font_family = o.title_font_family || o.font_family;
        o.number_font = o.number_font || o.font_family;
        o.inset_pad = o.frame_inset_width > 0 ? o.frame_border_width + o.frame_inset_gap + o.frame_inset_width : o.frame_pad;
        return o;
    }

    readonly property string font_family: root.active.font_family
    readonly property int font_size: root.active.font_size
    // Big readouts (weather temperature, OSD percentage); empty uses font_family.
    readonly property string number_font: root.active.number_font !== "" ? root.active.number_font : root.font_family
    readonly property color text_muted: root.active.text_muted
    readonly property color text_dim: root.active.text_dim
    readonly property color text_fg: root.active.text_fg
    readonly property color text_strong: root.active.text_strong
    // Primary and secondary colored text in popups.
    readonly property color text_primary: root.active.text_primary
    readonly property color text_accent: root.active.text_accent
    readonly property string title_font_family: root.active.title_font_family || root.font_family
    readonly property bool rounded: root.active.rounded
    readonly property bool frame_follows_island: root.active.frame_follows_island
    readonly property color frame_color: root.active.frame_color
    readonly property real frame_radius: root.active.frame_radius
    readonly property int frame_border_width: root.active.frame_border_width
    readonly property color frame_border_color: root.active.frame_border_color
    // A 1px rule along the bottom edge of every frame.
    // Bottom corners cut at 45 degrees by this many px.
    readonly property real frame_chamfer: root.active.frame_chamfer
    // Frames drawn as visor glass (VisorGlass) instead of a plain rectangle.
    readonly property bool frame_visor: root.active.frame_visor
    readonly property color frame_brackets: root.active.frame_brackets
    // An inner ring frame_inset_gap inside the border; content keeps inset_pad clear of the frame edge.
    readonly property int frame_inset_gap: root.active.frame_inset_gap
    readonly property int frame_inset_width: root.active.frame_inset_width
    readonly property color frame_inset_color: root.active.frame_inset_color
    readonly property int inset_pad: root.frame_inset_width > 0 ? root.frame_border_width + root.frame_inset_gap + root.frame_inset_width : root.active.frame_pad
    // A hard shadow this many px below floating frames.
    readonly property int frame_drop: root.active.frame_drop
    // A panel lcd_margin inside the frame, shaded lcd_top to lcd_bottom, that holds the title, body and footer.
    readonly property color lcd_top: root.active.lcd_top
    readonly property color lcd_bottom: root.active.lcd_bottom
    readonly property color lcd_scan: root.active.lcd_scan
    readonly property int lcd_margin: root.active.lcd_margin
    // Lettering on the frame under the panel.
    readonly property string frame_engraving: root.active.frame_engraving
    readonly property color accent_color: root.active.accent_color
    readonly property int accent_height: root.active.accent_height
    readonly property bool accent_full_width: root.active.accent_full_width
    // Frames without a popup accent line (OSD, toasts) draw one along their top edge.
    readonly property bool frame_top_rule: root.active.frame_top_rule
    readonly property color selection_bg: root.active.selection_bg
    readonly property bool selection_inverse: root.active.selection_inverse
    readonly property color selection_fg: root.active.selection_fg
    readonly property color caret_color: root.active.caret_color
    readonly property bool caret_blink: root.active.caret_blink
    readonly property color selection_outline: root.active.selection_outline
    // Toggled by the open popup's blink timer; the caret is solid whenever it rests true.
    property bool caret_phase: true
    readonly property color tab_active_bg: root.active.tab_active_bg
    readonly property color tab_active_fg: root.active.tab_active_fg
    readonly property color tab_fg: root.active.tab_fg
    readonly property bool tab_caps: root.active.tab_caps
    readonly property color tab_underline: root.active.tab_underline
    readonly property color key_bg: root.active.key_bg
    readonly property color key_fg: root.active.key_fg
    readonly property color key_border: root.active.key_border
    readonly property color section_fg: root.active.section_fg
    readonly property bool section_rule: root.active.section_rule
    // Section headers and footer descriptions in tracked caps.
    readonly property bool label_caps: root.active.label_caps
    readonly property real label_spacing: root.active.label_spacing
    // A rule after section labels that fades out to the right.
    readonly property color section_fade: root.active.section_fade
    readonly property color footer_fg: root.active.footer_fg
    readonly property color footer_key_fg: root.active.footer_key_fg
    readonly property bool footer_rule: root.active.footer_rule
    readonly property color footer_rule_color: root.active.footer_rule_color
    readonly property color meter_on: root.active.meter_on
    readonly property color meter_off: root.active.meter_off
    readonly property color meter_hot: root.active.meter_hot
    readonly property real meter_radius: root.active.meter_radius
    // Outlines every meter segment; lit hot segments take meter_hot instead.
    readonly property color meter_outline: root.active.meter_outline
    readonly property real scale: root.active.scale
    // Floor for every popup's width, for wide fonts that overrun the small popups.
    readonly property real popup_min_width: root.active.popup_min_width
    readonly property bool show_title: root.active.show_title
    readonly property color title_bg: root.active.title_bg
    readonly property color title_fg: root.active.title_fg
    readonly property bool show_footer: root.active.show_footer
    readonly property bool footer_wrap: root.active.footer_wrap
    readonly property string row_cursor: root.active.row_cursor
    // Closes the cursor at the selected row's right end, before its key badge.
    readonly property bool segmented_levels: root.active.segmented_levels
    readonly property bool tab_keys: root.active.tab_keys
    readonly property bool row_keys: root.active.row_keys
    readonly property bool boxed_cards: root.active.boxed_cards
    readonly property bool chip_brackets: root.active.chip_brackets
    readonly property color chip_active_bg: root.active.chip_active_bg
    readonly property color chip_active_fg: root.active.chip_active_fg
    // A picked action chip's fill; chip_border outlines the rest, key_border when transparent.
    readonly property color chip_pick: root.active.chip_pick
    readonly property color chip_border: root.active.chip_border
    readonly property color card_edge: root.active.card_edge
    readonly property bool toggle_brackets: root.active.toggle_brackets
    readonly property color toggle_on: root.active.toggle_on
    readonly property color toggle_off: root.active.toggle_off
    readonly property bool marker_fill: root.active.marker_fill
    readonly property bool selection_bar: root.active.selection_bar
    readonly property string title_prefix: root.active.title_prefix
    readonly property string title_suffix: root.active.title_suffix
    readonly property real title_spacing: root.active.title_spacing
    readonly property color title_glow: root.active.title_glow
    // A static system readout drawn at the right end of the title row.
    readonly property string title_readout: root.active.title_readout
    // Transparent draws the readout in text_muted; {code} in the readout becomes the title's first three letters.
    readonly property color title_readout_fg: root.active.title_readout_fg
    readonly property color title_rule: root.active.title_rule
    readonly property color frame_glow: root.active.frame_glow
    readonly property bool scanlines: root.active.scanlines
    readonly property color scanline_color: root.active.scanline_color
    readonly property bool glow: root.active.glow
    readonly property color glow_color: root.active.glow_color
    readonly property real glow_tint: root.active.glow_tint
    // A diagonal shade from this color at the top left into frame_color.
    readonly property color frame_shade: root.active.frame_shade
    // Runs frame_shade top to bottom instead of diagonally.
    readonly property bool shade_vertical: root.active.shade_vertical
    readonly property color dither: root.active.dither
    readonly property color text_shadow: root.active.text_shadow
    // Selection and title fills fade out to the right.
    readonly property bool fade_fills: root.active.fade_fills
    readonly property color selection_border: root.active.selection_border
    readonly property color selection_glow: root.active.selection_glow
    // Leans selections, tabs and key badges into parallelograms; the shear per px of height.
    readonly property real slant: root.active.slant
    readonly property color meter_shade: root.active.meter_shade
    // Leans meter and waveform tops right by this shear per px of height.
    readonly property real meter_slant: root.active.meter_slant
    // A blurred copy of the whole meter behind it.
    readonly property bool meter_bloom: root.active.meter_bloom
    // Leans chart bars like meter_slant.
    readonly property real chart_slant: root.active.chart_slant
    readonly property color chart_fill: root.active.chart_fill
    // Multiplies every radius a rounded style draws.
    readonly property real corner_scale: root.active.corner_scale
    // The keeptabs done celebration: hearts, pixel (stepped) or lcd (blinks).
    readonly property string done_anim: root.active.done_anim || "hearts"

    property bool cava_line: true
    readonly property var bar: root.active
    readonly property string bar_font_family: root.bar.bar_font_family
    readonly property int bar_font_size: root.bar.bar_font_size
    // Text labels only; glyphs are unaffected.
    readonly property int bar_capitalization: root.bar.bar_caps ? Font.AllUppercase : Font.MixedCase
    readonly property real bar_letter_spacing: root.bar.bar_letter_spacing
    readonly property color bar_side_bg: root.bar.bar_side_bg
    readonly property color bar_center_bg: root.bar.bar_center_bg
    readonly property color bar_fg: root.bar.bar_fg
    // The clock's time sits on a chip of this color when it is not transparent.
    readonly property color bar_clock_bg: root.bar.bar_clock_bg
    readonly property color bar_clock_fg: root.bar.bar_clock_fg
    readonly property string bar_clock_font: root.bar.bar_clock_font || root.bar_font_family
    readonly property int bar_border_width: root.bar.bar_border_width
    readonly property color bar_border_color: root.bar.bar_border_color
    readonly property bool bar_rounded: root.bar.bar_rounded
    // Focused is the workspace you are on; active is the one shown on each other monitor.
    readonly property color bar_workspace_focused: root.bar.bar_workspace_focused
    readonly property color bar_workspace_active: root.bar.bar_workspace_active
    readonly property color bar_workspace_idle: root.bar.bar_workspace_idle
    readonly property color bar_workspace_ring: root.bar.bar_workspace_ring
    // An inner line along each island's slants and bottom edge.
    readonly property int bar_inset_gap: root.bar.bar_inset_gap
    readonly property int bar_inset_width: root.bar.bar_inset_width
    readonly property color bar_inset_color: root.bar.bar_inset_color
    readonly property color bar_hover_bg: root.bar.bar_hover_bg
    readonly property color bar_glow_color: root.bar.bar_glow_color
    readonly property color bar_scanline_color: root.bar.bar_scanline_color
    readonly property int bar_text_style: root.bar.bar_text_raised ? Text.Raised : root.bar_glow_color.a > 0 ? Text.Outline : Text.Normal

    // Corner radius for a shape that is rounded by `r` in the default look.
    function radius(r) {
        return root.rounded ? r * root.corner_scale : 0;
    }

    // Corner radius for a bar shape that is rounded by `r` in the default look.
    function bar_radius(r) {
        return root.bar_rounded ? r : 0;
    }

    // A layout size that grows with the style's larger type.
    function px(n) {
        return root.scale === 1 ? n : Math.round(n * root.scale);
    }

    function set(style_name) {
        if (!(style_name in root.styles)) {
            console.warn("Style: unknown style " + style_name);
            return false;
        }
        root.name = style_name;
        root.saved_name = style_name;
        root.save();
        return true;
    }

    function set_cava_line(on) {
        root.cava_line = on;
        root.save();
    }

    function save() {
        state_file.setText(JSON.stringify({ style: root.saved_name, cava_line: root.cava_line }));
    }

    function preview(style_name) {
        if (style_name in root.styles) root.name = style_name;
    }

    function cycle() {
        const i = root.names.indexOf(root.name);
        root.set(root.names[(i + 1) % root.names.length]);
    }

    readonly property string state_dir: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg && xdg !== "" ? xdg : Quickshell.env("HOME") + "/.local/state") + "/quickshell";
    }

    Process {
        id: ensure_state_dir
        command: ["mkdir", "-p", root.state_dir]
    }

    FileView {
        id: state_file
        path: root.state_dir + "/style.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                const saved = data.style;
                root.cava_line = data.cava_line !== false;
                if (typeof saved === "string" && saved in root.styles) {
                    root.name = saved;
                    root.saved_name = saved;
                }
            } catch (e) {
                console.warn("Style: invalid style.json (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }

    Component.onCompleted: {
        ensure_state_dir.running = true;
        state_file.reload();
    }
}
