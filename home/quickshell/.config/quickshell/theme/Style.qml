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
    readonly property var order: ["default", "terminal", "crt", "nes", "snes", "gameboy", "goldeneye", "ps1", "ff7", "ps2", "halflife", "tie", "metroid", "oblivion", "mech"]
    readonly property var names: root.order.filter(n => n in root.styles).concat(Object.keys(root.styles).filter(n => root.order.indexOf(n) < 0))
    readonly property var labels: ({ crt: "CRT", nes: "NES", snes: "SNES", gameboy: "Gameboy", goldeneye: "Goldeneye", ps1: "PSX", ff7: "FFVII", ps2: "PS2", halflife: "Half Life", tie: "Tie Fighter" })

    function label(style_name) {
        return root.labels[style_name] || style_name.charAt(0).toUpperCase() + style_name.slice(1);
    }

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
            meter_shade: "transparent",
            meter_slant: 0,
            meter_bloom: false,
            chart_slant: 0,
            chart_fill: Theme.yellow,
            corner_scale: 1,
            mono_font: "",
            frame_cut: 0,
            frame_notch: 0,
            frame_line: "transparent",
            frame_marks: "transparent",
            title_band: "transparent",
            title_ids: ({}),
            row_marker: "",
            row_rule: "transparent",
            selection_rule: "transparent",
            corner_tick: "transparent",
            key_cut: 0,
            tab_bg: "transparent",
            tab_cut: 0,
            chip_bg: "transparent",
            section_marker: "transparent",
            meter_major: "transparent",
            meter_height: 0,
            footer_key_bg: "transparent",
            footer_separator: " \u00b7 ",
            footer_rule_solid: false,
            slider_readout: false,
            hazard: "transparent",
            schematic: "transparent",
            status_strip: false,
            osd_layout: "",
            card_layout: "",
            weather_header: "",
            bar_pill_square: false,
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
            wait_anim: "bubble",
            bar_scanline_color: "transparent",
            label_font_family: "",
            frame_octagon: 0,
            frame_struts: "transparent",
            lcd_radius: 8,
            lcd_border: Qt.alpha(Theme.bg_shadow, 0.6),
            lcd_brackets: "transparent",
            selection_brackets: "transparent",
            tab_brackets: "transparent",
            tab_rule: "transparent",
            title_reticle: "transparent",
            chart_outline: "transparent",
            bar_workspace_diamond: false,
            bar_clock_brackets: "transparent",
            hairline: "transparent",
            hairline_dim: "transparent",
            frame_ticks: "",
            tick_ruler: false,
            range_line: false,
            key_round: false,
            pill_chips: false,
            title_index: [],
            title_weight: 0,
            title_trail: "transparent",
            bar_ticks: "transparent",
            title_strip: "transparent",
            caps_tracking: 0,
            tab_outline: "transparent",
            shade_0: "transparent",
            shade_1: "transparent",
            shade_2: "transparent",
            shade_3: "transparent",
            pixel_border: "transparent",
            device_shell: false,
            window_gradient: [],
            materia: ({}),
            hand_cursor: false,
            meter_solid: false,
            controller: "",
            meter_art: ({}),
            toast_enter: "",
            console_views: ""
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
                meter_shade: "transparent",
                meter_slant: 0,
                meter_bloom: false,
                chart_slant: 0,
                chart_fill: Theme.yellow,
                corner_scale: 1,
                mono_font: "",
                frame_cut: 0,
                frame_notch: 0,
                frame_line: "transparent",
                frame_marks: "transparent",
                title_band: "transparent",
                title_ids: ({}),
                row_marker: "",
                row_rule: "transparent",
                selection_rule: "transparent",
                corner_tick: "transparent",
                key_cut: 0,
                tab_bg: "transparent",
                tab_cut: 0,
                chip_bg: "transparent",
                section_marker: "transparent",
                meter_major: "transparent",
                meter_height: 0,
                footer_key_bg: "transparent",
                footer_separator: " \u00b7 ",
                footer_rule_solid: false,
                slider_readout: false,
                hazard: "transparent",
                schematic: "transparent",
                status_strip: false,
                osd_layout: "",
                card_layout: "",
                weather_header: "",
                bar_pill_square: false,
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
                bar_hover_bg: Theme.bg_surface,
                bar_glow_color: "transparent",
                bar_text_raised: false,
                done_anim: "hearts",
                wait_anim: "bubble",
                bar_scanline_color: "transparent",
                label_font_family: "",
                frame_octagon: 0,
                frame_struts: "transparent",
                lcd_radius: 8,
                lcd_border: Qt.alpha(Theme.bg_shadow, 0.6),
                lcd_brackets: "transparent",
                selection_brackets: "transparent",
                tab_brackets: "transparent",
                tab_rule: "transparent",
                title_reticle: "transparent",
                chart_outline: "transparent",
                bar_workspace_diamond: false,
                bar_clock_brackets: "transparent",
                hairline: "transparent",
                hairline_dim: "transparent",
                frame_ticks: "",
                tick_ruler: false,
                range_line: false,
                key_round: false,
                pill_chips: false,
                title_index: [],
                title_weight: 0,
                title_trail: "transparent",
                bar_ticks: "transparent",
                title_strip: "transparent",
                caps_tracking: 0,
                tab_outline: "transparent",
                shade_0: "transparent",
                shade_1: "transparent",
                shade_2: "transparent",
                shade_3: "transparent",
                pixel_border: "transparent",
                device_shell: false,
                window_gradient: [],
                materia: ({}),
                hand_cursor: false,
                meter_solid: false,
                controller: "",
                    meter_art: ({}),
                    toast_enter: "",
                console_views: ""
            },
            "terminal": Object.assign({}, terminal, {
                wait_anim: "cursor",
                weather_header: "wttr"
            }),
            "crt": Object.assign({}, terminal, {
                wait_anim: "pressanykey",
                weather_header: "weatherstar",
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
                wait_anim: "advance",
                done_anim: "pixel",
                weather_header: "battle",
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
                bar_inset_color: Theme.fg_strong,
                card_layout: "dq",
                controller: "nes",
                console_views: "nes",
                toast_enter: "type",
                meter_art: ({ volume: "nes/HeartMeter.qml", battery: "nes/EnergyBar.qml", osd: "nes/EnergyBar.qml", media: "nes/PianoRoll.qml" })
            }),
            "snes": Object.assign({}, terminal, {
                wait_anim: "hand",
                done_anim: "pixel",
                weather_header: "mode7",
                controller: "snes",
                console_views: "snes",
                osd_layout: "rpg",
                card_layout: "dialogue",
                toast_enter: "mode7",
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
                controller: "ps1",
                toast_enter: "wobble",
                console_views: "ps1",
                osd_layout: "alert",
                wait_anim: "alert",
                done_anim: "pixel",
                weather_header: "memcard",
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
                wait_anim: "transmission",
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
                weather_header: "watch",
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
            "metroid": Object.assign({}, terminal, {
                wait_anim: "scan",
                weather_header: "scan",
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
                wait_anim: "rumble",
                weather_header: "towers",
                done_anim: "pixel",
                // Muted text lifted so it still reads on the lit selection pill.
                text_muted: Qt.tint(Theme.fg_muted, Qt.alpha(Theme.theme_primary_light, 0.35)),
                text_dim: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.3)),
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
                bar_hover_bg: Qt.alpha(Theme.theme_primary, 0.2),
                frame_shade: Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.theme_primary, 0.14)),
                shade_vertical: true,
                bar_inset_gap: 2,
                bar_inset_width: 1,
                bar_inset_color: Qt.alpha(Theme.theme_primary_light, 0.22),
                card_layout: "dialog",
                osd_layout: "glow",
                controller: "ps2",
                console_views: "ps2",
                toast_enter: "bloom"
            }),
            // TIE Fighter cockpit: large popups in the octagonal viewport, `small` ones the targeting computer.
            "tie": (() => {
                const vec = Theme.ok;
                const vec_d = Qt.alpha(vec, 0.4);
                const lock = Theme.theme_label;
                return Object.assign({}, terminal, {
                    wait_anim: "comms",
                    text_muted: Qt.alpha(vec, 0.55),
                    text_dim: Qt.alpha(vec, 0.7),
                    text_fg: Qt.tint(Theme.fg_core, Qt.alpha(vec, 0.72)),
                    text_strong: Theme.fg_strong,
                    text_primary: vec,
                    text_accent: Theme.theme_secondary,
                    font_family: "B612 Mono",
                    font_size: Theme.popup_font_size - 1,
                    title_font_family: "Oxanium",
                    label_font_family: "Oxanium",
                    number_font: "Oxanium",
                    frame_color: Theme.bg_crust,
                    frame_shade: Theme.bg_mantle,
                    shade_vertical: true,
                    frame_border_color: vec,
                    frame_octagon: 20,
                    frame_struts: vec,
                    frame_pad: 12,
                    accent_color: vec,
                    accent_height: 0,
                    selection_bg: Qt.alpha(lock, 0.08),
                    selection_outline: "transparent",
                    selection_brackets: lock,
                    caret_color: lock,
                    caret_blink: false,
                    row_cursor: "\u25b8",
                    tab_active_bg: Qt.alpha(vec, 0.09),
                    tab_active_fg: Theme.fg_strong,
                    tab_fg: Qt.alpha(vec, 0.55),
                    tab_caps: true,
                    tab_underline: vec,
                    tab_brackets: lock,
                    tab_rule: vec_d,
                    key_fg: Theme.theme_secondary,
                    key_border: Qt.alpha(Theme.theme_secondary, 0.45),
                    section_fg: vec,
                    section_rule: false,
                    section_fade: vec_d,
                    label_caps: true,
                    label_spacing: 2.5,
                    footer_fg: Qt.alpha(vec, 0.55),
                    footer_rule_color: vec_d,
                    meter_on: Qt.alpha(vec, 0.75),
                    meter_off: Qt.alpha(vec, 0.1),
                    meter_hot: lock,
                    meter_bloom: true,
                    title_bg: "transparent",
                    title_fg: vec,
                    title_spacing: 3.5,
                    title_readout: "SCAN",
                    title_readout_fg: Theme.theme_secondary,
                    title_reticle: vec,
                    title_trail: vec_d,
                    chip_brackets: false,
                    chip_active_bg: lock,
                    chip_active_fg: Theme.bg_crust,
                    chip_pick: lock,
                    chip_border: vec_d,
                    toggle_on: vec,
                    toggle_off: Qt.alpha(vec, 0.45),
                    scanlines: true,
                    scanline_color: Qt.alpha(vec, 0.05),
                    chart_fill: Qt.alpha(vec, 0.09),
                    chart_outline: vec,
                    weather_header: "scope",
                    bar_font_family: "B612 Mono",
                    bar_font_size: Theme.font_size - 1,
                    bar_side_bg: Theme.bg_crust,
                    bar_center_bg: Theme.bg_crust,
                    bar_fg: vec,
                    bar_border_color: vec,
                    bar_workspace_focused: Theme.theme_secondary,
                    bar_workspace_active: vec,
                    bar_workspace_idle: "transparent",
                    bar_workspace_ring: vec,
                    bar_workspace_diamond: true,
                    bar_pill_square: true,
                    bar_clock_brackets: lock,
                    bar_hover_bg: Qt.alpha(vec, 0.15),
                    small: {
                        frame_octagon: 0,
                        frame_radius: 5,
                        frame_border_color: Theme.bg_surface,
                        frame_pad: 0,
                        lcd_top: Qt.tint(Theme.bg_core, Qt.alpha(vec, 0.06)),
                        lcd_bottom: Theme.bg_crust,
                        lcd_scan: Qt.alpha(vec, 0.05),
                        lcd_margin: 9,
                        lcd_radius: 16,
                        lcd_border: vec_d,
                        lcd_brackets: vec,
                        scanlines: false,
                        title_readout: "TRGT CMP"
                    }
                });
            })(),
            // The Tet and bubble-ship displays: pale hairlines on near-black, thin caps, tick scales and ring gauges.
            "oblivion": Object.assign({}, terminal, {
                wait_anim: "ping",
                text_muted: Qt.alpha(Theme.fg_strong, 0.55),
                text_dim: Qt.alpha(Theme.fg_strong, 0.7),
                text_fg: Qt.alpha(Theme.fg_strong, 0.86),
                text_strong: Theme.fg_strong,
                text_primary: Theme.theme_primary_light,
                text_accent: Theme.theme_primary_light,
                font_family: "Jura",
                font_size: Theme.popup_font_size + 2,
                title_font_family: "Jura",
                number_font: "Saira",
                scale: 1.1,
                frame_color: Qt.alpha(Theme.bg_crust, 0.97),
                frame_shade: Qt.alpha(Theme.bg_core, 0.97),
                shade_vertical: true,
                frame_border_width: 0,
                frame_border_color: Qt.alpha(Theme.fg_strong, 0.24),
                frame_pad: 10,
                accent_color: Qt.alpha(Theme.fg_strong, 0.55),
                accent_height: 1,
                frame_top_rule: true,
                hairline: Qt.alpha(Theme.fg_strong, 0.55),
                hairline_dim: Qt.alpha(Theme.fg_strong, 0.24),
                frame_ticks: "top",
                selection_bg: Qt.alpha(Theme.theme_primary_light, 0.14),
                selection_outline: "transparent",
                selection_rule: Qt.alpha(Theme.theme_primary_light, 0.6),
                fade_fills: true,
                caret_color: Theme.theme_primary_light,
                caret_blink: false,
                row_cursor: "○",
                tab_active_bg: "transparent",
                tab_active_fg: Theme.fg_strong,
                tab_fg: Qt.alpha(Theme.fg_strong, 0.55),
                tab_caps: true,
                tab_underline: Theme.fg_strong,
                tab_rule: Qt.alpha(Theme.fg_strong, 0.12),
                key_fg: Theme.theme_primary_light,
                key_border: Qt.alpha(Theme.fg_strong, 0.24),
                key_round: true,
                section_fg: Qt.alpha(Theme.fg_strong, 0.55),
                section_rule: false,
                section_fade: Qt.alpha(Theme.fg_strong, 0.18),
                label_caps: true,
                label_spacing: 3,
                footer_fg: Qt.alpha(Theme.fg_strong, 0.55),
                footer_key_fg: Theme.theme_primary_light,
                footer_rule_color: Qt.alpha(Theme.fg_strong, 0.18),
                meter_on: Theme.fg_strong,
                meter_off: Qt.alpha(Theme.fg_strong, 0.1),
                meter_hot: Theme.theme_label,
                tick_ruler: true,
                title_bg: "transparent",
                title_fg: Theme.fg_strong,
                title_spacing: 5,
                title_weight: Font.Light,
                title_index: ["start", "volume", "notifications", "weather", "media", "clock", "battery", "network", "bluetooth", "system", "updates", "tray", "keeptabs", "style"],
                title_trail: Qt.alpha(Theme.fg_strong, 0.24),
                title_readout: "TET · LINK",
                title_readout_fg: Qt.alpha(Theme.fg_strong, 0.55),
                chip_brackets: false,
                chip_active_bg: Theme.fg_strong,
                chip_active_fg: Theme.bg_crust,
                chip_pick: Theme.fg_strong,
                chip_border: Qt.alpha(Theme.fg_strong, 0.24),
                pill_chips: true,
                card_layout: "rule",
                toggle_brackets: false,
                toggle_on: Theme.fg_strong,
                toggle_off: Qt.alpha(Theme.fg_strong, 0.55),
                marker_fill: false,
                osd_layout: "ring",
                weather_header: "ring",
                range_line: true,
                bar_font_family: "Jura",
                bar_font_size: Theme.font_size,
                bar_letter_spacing: 1.5,
                bar_side_bg: Qt.alpha(Theme.bg_core, 0.85),
                bar_center_bg: Qt.alpha(Theme.bg_core, 0.85),
                bar_fg: Qt.alpha(Theme.fg_strong, 0.86),
                bar_clock_fg: Qt.alpha(Theme.fg_strong, 0.86),
                bar_border_color: Qt.alpha(Theme.fg_strong, 0.24),
                bar_workspace_focused: Theme.fg_strong,
                bar_workspace_active: Qt.alpha(Theme.theme_secondary, 0.45),
                bar_workspace_idle: "transparent",
                bar_workspace_ring: Qt.alpha(Theme.fg_strong, 0.55),
                bar_hover_bg: Qt.alpha(Theme.fg_strong, 0.08),
                bar_ticks: Qt.alpha(Theme.fg_strong, 0.24),
                small: {
                    frame_ticks: "left",
                    frame_color: Qt.alpha(Theme.bg_core, 0.96),
                    frame_shade: "transparent",
                    frame_border_width: 1,
                    accent_color: Qt.alpha(Theme.fg_strong, 0.24),
                    frame_pad: 6,
                    title_readout: ""
                }
            }),
            // Mecha hangar panels in the manner of Armored Core VI and MechWarrior 5.
            "mech": Object.assign({}, terminal, {
                wait_anim: "orders",
                text_fg: Qt.alpha(Theme.fg_core, 0.92),
                text_muted: Qt.alpha(Theme.theme_primary_light, 0.66),
                text_dim: Qt.alpha(Theme.theme_primary_light, 0.8),
                text_primary: Theme.theme_primary_light,
                font_family: "Barlow Condensed",
                font_size: Theme.popup_font_size + 4,
                title_font_family: "Barlow Condensed",
                number_font: "Saira Stencil One",
                mono_font: "Share Tech Mono",
                frame_color: Theme.bg_crust,
                frame_shade: Qt.tint(Theme.bg_core, Qt.alpha(Theme.ui_visual_bg, 0.3)),
                shade_vertical: true,
                frame_border_color: Qt.alpha(Theme.theme_primary_light, 0.55),
                frame_line: Qt.alpha(Theme.theme_primary_light, 0.24),
                frame_marks: Qt.alpha(Theme.theme_primary_light, 0.66),
                frame_cut: 14,
                frame_notch: 4,
                frame_pad: 4,
                accent_color: Theme.theme_secondary,
                accent_height: 0,
                selection_bg: Qt.alpha(Theme.theme_secondary, 0.17),
                selection_outline: "transparent",
                selection_bar: true,
                selection_rule: Qt.alpha(Theme.theme_secondary, 0.45),
                fade_fills: true,
                caret_color: Theme.theme_secondary,
                caret_blink: false,
                row_cursor: "",
                row_marker: "box",
                row_rule: Qt.alpha(Theme.theme_primary_light, 0.09),
                corner_tick: Qt.alpha(Theme.theme_primary_light, 0.24),
                tab_bg: Qt.alpha(Theme.theme_primary_light, 0.09),
                tab_active_bg: Qt.tint(Theme.bg_core, Qt.alpha(Theme.theme_primary_strong, 0.55)),
                tab_active_fg: Theme.fg_strong,
                tab_fg: Qt.alpha(Theme.theme_primary_light, 0.66),
                tab_caps: true,
                tab_underline: Theme.theme_secondary,
                tab_cut: 9,
                key_bg: Qt.alpha(Theme.theme_secondary, 0.09),
                key_fg: Theme.theme_secondary,
                key_border: Qt.alpha(Theme.theme_secondary, 0.45),
                key_cut: 4,
                section_fg: Qt.alpha(Theme.theme_primary_light, 0.66),
                section_rule: false,
                section_fade: Qt.alpha(Theme.theme_primary_light, 0.24),
                section_marker: Theme.theme_secondary,
                label_caps: true,
                label_spacing: 2.5,
                footer_fg: Qt.alpha(Theme.theme_primary_light, 0.66),
                footer_key_fg: Theme.bg_crust,
                footer_key_bg: Theme.theme_primary_light,
                footer_separator: "",
                footer_rule_solid: true,
                footer_rule_color: Qt.alpha(Theme.theme_primary_light, 0.24),
                meter_on: Theme.theme_primary_light,
                meter_off: Qt.alpha(Theme.theme_primary_light, 0.09),
                meter_major: Qt.alpha(Theme.theme_primary_light, 0.24),
                meter_hot: Theme.theme_label,
                meter_height: 7,
                slider_readout: true,
                chart_fill: Theme.theme_primary_light,
                title_bg: "transparent",
                title_fg: Theme.fg_strong,
                title_spacing: 3,
                title_band: Qt.tint(Theme.bg_core, Qt.alpha(Theme.theme_primary_strong, 0.55)),
                title_readout_fg: Qt.alpha(Theme.theme_primary_light, 0.66),
                title_ids: {
                    start: ["01", "HANGAR"],
                    volume: ["02", "LOADOUT"],
                    notifications: ["03", "COMMS"],
                    weather: ["04", "RECON"],
                    media: ["05", "AUDIO"],
                    battery: ["06", "POWER"],
                    system: ["07", "DIAG"],
                    network: ["08", "UPLINK"],
                    bluetooth: ["09", "LINK"],
                    tray: ["10", "AUX"],
                    updates: ["11", "PARTS"],
                    keeptabs: ["12", "TABS"],
                    clock: ["13", "CHRONO"],
                    style: ["14", "PAINT"],
                    osd: ["OSD", "OUTPUT"],
                    whichkey: ["KEY", "BINDS"]
                },
                chip_brackets: false,
                chip_bg: Qt.alpha(Theme.theme_primary_light, 0.09),
                chip_active_bg: Theme.theme_secondary,
                chip_active_fg: Theme.bg_crust,
                chip_pick: Theme.theme_secondary,
                chip_border: Qt.alpha(Theme.theme_primary_light, 0.24),
                toggle_brackets: false,
                toggle_on: Theme.theme_primary_light,
                toggle_off: Qt.alpha(Theme.theme_primary_light, 0.5),
                hazard: Theme.theme_secondary,
                schematic: Qt.alpha(Theme.theme_primary_light, 0.16),
                status_strip: true,
                osd_layout: "readout",
                card_layout: "channel",
                weather_header: "spec",
                bar_font_family: "Barlow Condensed",
                bar_font_size: Theme.font_size + 1,
                bar_caps: true,
                bar_letter_spacing: 1.5,
                bar_side_bg: Theme.bg_crust,
                bar_center_bg: Theme.bg_crust,
                bar_fg: Theme.fg_core,
                bar_clock_font: "Share Tech Mono",
                bar_border_width: 2,
                bar_border_color: Qt.alpha(Theme.theme_primary_light, 0.24),
                bar_workspace_focused: Theme.theme_secondary,
                bar_workspace_active: Qt.alpha(Theme.theme_primary_strong, 0.6),
                bar_workspace_idle: Qt.alpha(Theme.theme_primary_light, 0.09),
                bar_workspace_ring: Qt.alpha(Theme.theme_primary_light, 0.24),
                bar_pill_square: true,
                bar_hover_bg: Qt.alpha(Theme.theme_primary_light, 0.24)
            }),
            // Half-Life's VGUI windows and HEV HUD: dark panels on a primary hairline, Exo 2 text, Chakra Petch readouts.
            "halflife": (() => {
                const hl = Theme.theme_primary;
                const hl_t = Qt.alpha(hl, 0.72);
                const hl_l = Qt.alpha(hl, 0.55);
                const hl_hair = Qt.alpha(hl, 0.75);
                const hl_d = Qt.alpha(hl, 0.3);
                const hl_f = Qt.alpha(hl, 0.13);
                return Object.assign({}, terminal, {
                    wait_anim: "hev_alert",
                    done_anim: "hev_pickup",
                    weather_header: "hev",
                    osd_layout: "hud",
                    text_muted: hl_t,
                    text_dim: Qt.alpha(hl, 0.85),
                    text_fg: hl,
                    text_primary: hl,
                    font_family: "Exo 2",
                    font_size: Theme.popup_font_size + 2,
                    number_font: "Chakra Petch",
                    mono_font: "Chakra Petch",
                    frame_color: Theme.bg_core,
                    frame_border_color: hl_l,
                    accent_color: hl,
                    accent_height: 1,
                    hairline: hl_hair,
                    hairline_dim: hl_d,
                    selection_bg: hl_f,
                    selection_outline: "transparent",
                    selection_border: hl_l,
                    caret_color: hl,
                    caret_blink: false,
                    row_cursor: "",
                    tab_active_bg: hl_f,
                    tab_active_fg: Theme.fg_strong,
                    tab_fg: hl_t,
                    tab_underline: hl,
                    tab_outline: hl_d,
                    key_fg: Theme.theme_secondary,
                    key_border: Qt.alpha(Theme.theme_secondary, 0.45),
                    section_fg: hl,
                    section_rule: false,
                    section_fade: hl_d,
                    label_spacing: 1,
                    caps_tracking: 3,
                    footer_fg: hl_t,
                    footer_rule_solid: true,
                    footer_rule_color: hl_d,
                    meter_on: hl,
                    meter_off: hl_f,
                    title_bg: "transparent",
                    title_fg: hl,
                    title_spacing: 3.8,
                    title_strip: hl_f,
                    chip_brackets: false,
                    chip_active_bg: hl,
                    chip_active_fg: Theme.bg_crust,
                    chip_pick: hl,
                    chip_border: hl_l,
                    toggle_brackets: false,
                    toggle_on: hl,
                    toggle_off: hl_t,
                    marker_fill: false,
                    bar_font_family: "Chakra Petch",
                    bar_font_size: Theme.font_size + 1,
                    bar_letter_spacing: 0.8,
                    bar_side_bg: Qt.alpha(Theme.bg_core, 0.94),
                    bar_center_bg: Qt.alpha(Theme.bg_core, 0.94),
                    bar_fg: hl,
                    bar_clock_fg: hl,
                    bar_border_color: hl_l,
                    bar_workspace_focused: Theme.theme_secondary,
                    bar_workspace_active: hl,
                    bar_workspace_idle: hl_f,
                    bar_workspace_ring: hl_d,
                    bar_pill_square: true,
                    bar_hover_bg: hl_d
                });
            })(),
            // A backlit Game Boy screen in four shades of the primary; `small` popups sit in the handheld's shell.
            "gameboy": (() => {
                const g0 = Qt.tint(Theme.bg_crust, Qt.alpha(Theme.theme_primary, 0.08));
                const g1 = Qt.tint(Theme.bg_core, Qt.alpha(Theme.theme_primary_strong, 0.34));
                const g2 = Theme.theme_primary;
                const g3 = Theme.theme_primary_light;
                return Object.assign({}, terminal, {
                    wait_anim: "exclaim",
                    done_anim: "levelup",
                    weather_header: "pokedex",
                    card_layout: "pixel",
                    shade_0: g0,
                    shade_1: g1,
                    shade_2: g2,
                    shade_3: g3,
                    controller: "gameboy",
                    pixel_border: g2,
                    text_muted: g2,
                    text_dim: g2,
                    text_fg: g3,
                    text_strong: g3,
                    text_primary: g3,
                    text_accent: g3,
                    // Silkscreen and Press Start 2P sit on an 8px grid; 16 is Silkscreen's 2x size.
                    font_family: "Silkscreen",
                    font_size: 16,
                    title_font_family: "Press Start 2P",
                    number_font: "Press Start 2P",
                    mono_font: "Press Start 2P",
                    frame_color: g1,
                    frame_border_width: 0,
                    frame_border_color: g2,
                    frame_pad: 6,
                    accent_color: g2,
                    accent_height: 0,
                    selection_bg: g3,
                    selection_inverse: true,
                    selection_fg: g0,
                    selection_outline: "transparent",
                    caret_color: g0,
                    row_cursor: "\u25b6",
                    tab_active_bg: g3,
                    tab_active_fg: g0,
                    tab_fg: g2,
                    key_fg: g3,
                    key_border: g2,
                    section_fg: g2,
                    section_rule: false,
                    section_fade: g2,
                    footer_fg: g2,
                    footer_key_fg: g3,
                    footer_rule_color: g2,
                    meter_on: g3,
                    meter_off: g0,
                    meter_hot: Theme.theme_label,
                    meter_height: 8,
                    chart_fill: g3,
                    title_bg: "transparent",
                    title_fg: g3,
                    title_spacing: 0,
                    chip_brackets: false,
                    chip_active_bg: g3,
                    chip_active_fg: g0,
                    chip_pick: g3,
                    chip_border: g2,
                    toggle_on: g3,
                    toggle_off: g2,
                    marker_fill: false,
                    bar_font_family: "Silkscreen",
                    bar_font_size: 16,
                    bar_side_bg: g1,
                    bar_center_bg: g1,
                    bar_fg: g3,
                    bar_clock_fg: g3,
                    bar_border_width: 2,
                    bar_border_color: g0,
                    bar_inset_gap: 0,
                    bar_inset_width: 2,
                    bar_inset_color: g2,
                    bar_workspace_focused: g3,
                    bar_workspace_active: g2,
                    bar_workspace_idle: g0,
                    bar_workspace_ring: g2,
                    bar_pill_square: true,
                    bar_hover_bg: Qt.alpha(g3, 0.25),
                    small: {
                        device_shell: true
                    }
                });
            })(),
            // Final Fantasy VII materia menus: blue diagonal windows in a light rim, orbs for keys and a pointing hand.
            "ff7": (() => {
                const rim = Qt.tint(Theme.fg_strong, Qt.alpha(Theme.theme_primary_light, 0.55));
                const win_top = Qt.tint(Theme.ui_visual_bg, Qt.alpha(Theme.theme_primary_strong, 0.14));
                const win_mid = Qt.tint(Theme.bg_crust, Qt.alpha(Theme.ui_visual_bg, 0.55));
                const win_end = Qt.tint(Theme.bg_crust, Qt.alpha(Theme.ui_visual_bg, 0.14));
                const label = Qt.tint(Theme.fg_strong, Qt.alpha(Theme.theme_primary_light, 0.15));
                return Object.assign({}, terminal, {
                    wait_anim: "atb",
                    done_anim: "fanfare",
                    weather_header: "status",
                    text_muted: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.5)),
                    text_dim: Theme.theme_primary_light,
                    text_fg: label,
                    text_primary: Theme.theme_primary_light,
                    font_family: "Nunito",
                    font_size: Theme.popup_font_size + 4,
                    frame_color: win_end,
                    frame_shade: win_top,
                    window_gradient: [[0, win_top], [0.4, win_mid], [1, win_end]],
                    frame_radius: 6,
                    frame_border_width: 2,
                    frame_border_color: rim,
                    frame_inset_width: 1,
                    frame_inset_color: Theme.fg_muted,
                    frame_drop: 4,
                    accent_color: rim,
                    accent_height: 2,
                    selection_bg: "transparent",
                    selection_outline: "transparent",
                    caret_color: Theme.fg_strong,
                    caret_blink: false,
                    row_cursor: "",
                    hand_cursor: true,
                    controller: "ps1",
                    // Lighter than PS1's so the dark end of the window gradient keeps its blue.
                    dither: Qt.alpha(Theme.bg_shadow, 0.14),
                    tab_active_bg: "transparent",
                    tab_active_fg: Theme.fg_strong,
                    tab_fg: Theme.theme_primary_light,
                    key_bg: "transparent",
                    key_fg: Theme.bg_crust,
                    key_border: "transparent",
                    key_round: true,
                    materia: {
                        key: Theme.theme_secondary,
                        section: Theme.ok,
                        workspace: Theme.ok,
                        alert: Theme.theme_label,
                        clear: Theme.theme_secondary,
                        cloud: Theme.theme_primary_light,
                        rain: Theme.info,
                        storm: Theme.theme_label,
                        snow: Theme.fg_strong,
                        fog: Theme.fg_dim,
                        days: {
                            red: Theme.theme_label,
                            green: Theme.ok,
                            purple: Theme.magenta,
                            blue: Theme.info,
                            yellow: Theme.theme_secondary
                        }
                    },
                    section_fg: Theme.theme_primary_light,
                    section_rule: false,
                    section_fade: Qt.alpha(rim, 0.3),
                    label_caps: true,
                    label_spacing: 1.2,
                    footer_fg: Theme.theme_primary_light,
                    footer_key_fg: Theme.theme_secondary,
                    footer_rule_color: Qt.alpha(rim, 0.2),
                    meter_on: Theme.theme_primary_strong,
                    meter_shade: Theme.theme_primary_light,
                    meter_off: Theme.bg_crust,
                    meter_hot: Theme.theme_label,
                    meter_outline: Theme.fg_muted,
                    meter_radius: 1,
                    meter_height: 7,
                    meter_solid: true,
                    title_bg: "transparent",
                    title_fg: Theme.theme_primary_light,
                    title_spacing: 0.5,
                    chip_brackets: false,
                    chip_active_bg: "transparent",
                    chip_active_fg: Theme.fg_strong,
                    chip_pick: Qt.alpha(Theme.fg_strong, 0.2),
                    chip_border: Qt.alpha(rim, 0.45),
                    toggle_brackets: false,
                    toggle_on: Theme.ok,
                    toggle_off: Theme.theme_primary_light,
                    text_shadow: Qt.alpha(Theme.bg_crust, 0.85),
                    bar_font_family: "Nunito",
                    bar_font_size: Theme.font_size + 1,
                    bar_side_bg: win_end,
                    bar_center_bg: win_end,
                    bar_fg: Theme.fg_strong,
                    bar_clock_fg: Theme.fg_strong,
                    bar_border_width: 2,
                    bar_border_color: rim,
                    bar_inset_gap: 2,
                    bar_inset_width: 1,
                    bar_inset_color: Theme.fg_muted,
                    bar_workspace_focused: Theme.ok,
                    bar_workspace_active: Theme.theme_secondary,
                    bar_workspace_idle: Theme.bg_crust,
                    bar_workspace_ring: Theme.fg_muted,
                    bar_hover_bg: Qt.alpha(Theme.fg_strong, 0.12),
                    bar_glow_color: Theme.bg_crust,
                    bar_text_raised: true
                });
            })()
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
        o.label_font_family = o.label_font_family || o.font_family;
        o.mono_font = o.mono_font || o.font_family;
        o.custom_frame = o.frame_octagon > 0 || o.frame_cut > 0;
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
    // Sections, tabs and chips; empty uses font_family.
    readonly property string label_font_family: root.active.label_font_family || root.font_family
    // Readouts, keys and ids; empty uses font_family.
    readonly property string mono_font: root.active.mono_font || root.font_family
    // Frames cut to an octagon this many px at each corner (OctagonFrame).
    readonly property real frame_octagon: root.active.frame_octagon
    // Diagonal struts from the octagon's cut corners and ticks at its edge midpoints.
    readonly property color frame_struts: root.active.frame_struts
    // Top-left and bottom-right corners cut by this many px (ChamferFrame), with frame_notch px stepped notches.
    readonly property real frame_cut: root.active.frame_cut
    readonly property real frame_notch: root.active.frame_notch
    // A frame component draws the fill and border, so the base rectangle and FrameShade stay empty.
    readonly property bool custom_frame: root.frame_octagon > 0 || root.frame_cut > 0
    // The middle of a frame_cut border's vertical fade; its ends are frame_border_color.
    readonly property color frame_line: root.active.frame_line
    readonly property color frame_marks: root.active.frame_marks
    // "top": a tick scale on the top edge, bottom rule and corner crosses; "left": a scale down the left side and a corner ring.
    readonly property string frame_ticks: root.active.frame_ticks
    // Major and minor tick color for frame scales, rules and ruler meters.
    readonly property color hairline: root.active.hairline
    readonly property color hairline_dim: root.active.hairline_dim
    readonly property real lcd_radius: root.active.lcd_radius
    readonly property color lcd_border: root.active.lcd_border
    // Corner brackets at all four corners inside the LCD panel.
    readonly property color lcd_brackets: root.active.lcd_brackets
    // Target-lock corner brackets on selected rows, cards and days.
    readonly property color selection_brackets: root.active.selection_brackets
    // A 1px rule under the selected row; row_rule draws it under the others.
    readonly property color selection_rule: root.active.selection_rule
    readonly property color row_rule: root.active.row_rule
    // "box" marks every row with a square, filled on the selected one; rows with a slot number show it instead.
    readonly property string row_marker: root.active.row_marker
    // A diagonal tick in the top-right corner of cards and the selected row.
    readonly property color corner_tick: root.active.corner_tick
    // Brackets around the active tab's label.
    readonly property color tab_brackets: root.active.tab_brackets
    // A 1px baseline under every tab.
    readonly property color tab_rule: root.active.tab_rule
    readonly property color tab_bg: root.active.tab_bg
    readonly property real tab_cut: root.active.tab_cut
    readonly property color chip_bg: root.active.chip_bg
    // Chips, action chips, header buttons and the alert banner as outlined pills.
    readonly property bool pill_chips: root.active.pill_chips
    readonly property bool key_round: root.active.key_round
    readonly property real key_cut: root.active.key_cut
    readonly property color section_marker: root.active.section_marker
    // A reticle glyph before popup titles.
    readonly property color title_reticle: root.active.title_reticle
    // Popup names numbered 01, 02, ... in front of their titles.
    readonly property var title_index: root.active.title_index
    // 0 keeps titles bold when they share the body font.
    readonly property int title_weight: root.active.title_weight
    // A rule from the title to the readout, fading out to the right.
    readonly property color title_trail: root.active.title_trail
    // A title strip with a tab-cut band in this color (TabHeader); title_ids maps popup names to [id, readout].
    readonly property color title_band: root.active.title_band
    readonly property var title_ids: root.active.title_ids
    readonly property color chart_outline: root.active.chart_outline
    // Daily temperature ranges as 1px lines with ring end caps.
    readonly property bool range_line: root.active.range_line
    readonly property bool tick_ruler: root.active.tick_ruler
    // Every fifth unlit meter segment; meter_height 0 keeps the default height.
    readonly property color meter_major: root.active.meter_major
    readonly property real meter_height: root.active.meter_height
    // Footer keys drawn as filled caps in footer_key_fg on this color.
    readonly property color footer_key_bg: root.active.footer_key_bg
    readonly property string footer_separator: root.active.footer_separator
    readonly property bool footer_rule_solid: root.active.footer_rule_solid
    readonly property bool slider_readout: root.active.slider_readout
    // Hazard stripes on alert banners and critical cards.
    readonly property color hazard: root.active.hazard
    // Start's schematic and status strip.
    readonly property color schematic: root.active.schematic
    readonly property bool status_strip: root.active.status_strip
    // Alternate layouts: "" keeps the default; osd "ring", "readout", "hud", "rpg", "alert" or "glow", weather "ring", "spec", "scope", "watch", "memcard", "battle", "mode7", "wttr", "weatherstar", "towers", "scan", "hev", "pokedex" or "status", cards "rule", "channel", "pixel", "dq", "dialogue" or "dialog".
    readonly property string osd_layout: root.active.osd_layout
    readonly property string weather_header: root.active.weather_header
    readonly property string card_layout: root.active.card_layout
    // The keeptabs done celebration: hearts, pixel (stepped), lcd (stepped, then blinks), hev_pickup, levelup (inverted flash, pixel sparkles) or fanfare.
    readonly property string done_anim: root.active.done_anim || "hearts"
    // The keeptabs waiting cue: bubble, cursor, pressanykey, advance, hand, alert, rumble, transmission, scan, comms, ping, orders, hev_alert, exclaim or atb.
    readonly property string wait_anim: root.active.wait_anim || "bubble"
    // A full-width title strip in this color with a hairline under it and a close box at the right.
    readonly property color title_strip: root.active.title_strip
    // Sections, tabs, chips and header buttons in caps tracked this far; footers keep label_caps.
    readonly property real caps_tracking: root.active.caps_tracking
    // A 1px outline around every tab and header button; the active tab takes selection_border.
    readonly property color tab_outline: root.active.tab_outline
    // A four-shade screen palette, darkest first, for pixel-art parts (sprites, photos, dot bars).
    readonly property color shade_0: root.active.shade_0
    readonly property color shade_1: root.active.shade_1
    readonly property color shade_2: root.active.shade_2
    readonly property color shade_3: root.active.shade_3
    // Frames get a 2px pixel double border with this middle ring (PixelFrame); keys and meters get 2px pixel rings.
    readonly property color pixel_border: root.active.pixel_border
    // Small popups sit inside a handheld's shell (DeviceShell); hover shelves never do.
    readonly property bool device_shell: root.active.device_shell
    // Diagonal [position, color] stops filling window frames inside their border (WindowGradient); empty keeps frame_color.
    readonly property var window_gradient: root.active.window_gradient
    // Orb colors (MateriaOrb) by role (key, section, workspace, alert), weather kind and daily slot color; a role left out draws no orb.
    readonly property var materia: root.active.materia
    // A pointing hand (HandCursor) on the selected row, active tab, picked chip and selected day.
    readonly property bool hand_cursor: root.active.hand_cursor
    // Meters as one continuous gauge (AtbBar) instead of segments.
    readonly property bool meter_solid: root.active.meter_solid
    // Key badges, footers and help draw this console's buttons (KeyHints.controller_maps, components/<console>/<Console>Button.qml).
    readonly property string controller: root.active.controller
    // Meter art by popup name (or "osd"): a component path relative to components/ that replaces the segments.
    readonly property var meter_art: root.active.meter_art
    // Toast arrival: "" fades in; "type" slides and types, "mode7" zooms from a tilted plane, "wobble" settles, "bloom" glows, each once.
    readonly property string toast_enter: root.active.toast_enter
    // Popups, toasts and bar modules swap in this console's views ("nes", "snes", "ps1", "ps2"); "" keeps the shared ones.
    readonly property string console_views: root.active.console_views

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
    // Square-cornered workspace pills; bar_workspace_diamond also turns the empty ones into diamonds.
    readonly property bool bar_pill_square: root.bar.bar_pill_square
    readonly property bool bar_workspace_diamond: root.bar.bar_workspace_diamond
    // Brackets around the bar clock's time.
    readonly property color bar_clock_brackets: root.bar.bar_clock_brackets
    // A tick scale rising from each island's bottom edge.
    readonly property color bar_ticks: root.bar.bar_ticks
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
