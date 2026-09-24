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
            font_family: "JetBrainsMono Nerd Font",
            font_size: Theme.popup_font_size + 2,
            rounded: false,
            frame_follows_island: false,
            frame_color: Theme.bg_crust,
            frame_radius: 0,
            frame_border_width: 1,
            frame_border_color: Theme.fg_muted,
            accent_color: Theme.theme_secondary,
            accent_height: 3,
            accent_full_width: true,
            selection_bg: "transparent",
            selection_inverse: false,
            selection_fg: Theme.bg_crust,
            caret_color: Theme.theme_secondary,
            caret_blink: true,
            selection_outline: Qt.alpha(Theme.theme_secondary, 0.6),
            tab_active_bg: Theme.theme_secondary,
            tab_active_fg: Theme.bg_crust,
            tab_fg: Theme.fg_muted,
            key_bg: "transparent",
            key_fg: Theme.fg_muted,
            key_border: Theme.bg_surface,
            section_fg: Theme.fg_muted,
            section_rule: true,
            footer_fg: Theme.fg_muted,
            footer_rule: true,
            footer_rule_color: Theme.bg_surface,
            meter_on: Theme.theme_primary,
            meter_off: Theme.bg_surface,
            meter_hot: Theme.theme_label,
            meter_radius: 0,
            scale: 1.15,
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
            toggle_brackets: true,
            toggle_on: Theme.ok,
            toggle_off: Theme.fg_muted,
            marker_fill: true,
            selection_bar: false,
            title_prefix: "",
            title_suffix: "",
            frame_glow: "transparent",
            scanlines: false,
            scanline_color: "transparent",
            glow: false,
            glow_color: "transparent",
            glow_tint: 0,
            frame_shade: "transparent",
            dither: "transparent",
            text_shadow: "transparent",
            fade_fills: false,
            selection_border: "transparent",
            selection_glow: "transparent",
            meter_shade: "transparent",
            corner_scale: 1,
            bar_font_family: "JetBrainsMono Nerd Font",
            bar_font_size: Theme.font_size,
            bar_side_bg: Theme.bg_crust,
            bar_center_bg: Theme.bg_crust,
            bar_fg: Theme.fg_core,
            bar_border_width: 1,
            bar_border_color: Theme.fg_muted,
            bar_rounded: false,
            bar_workspace_focused: Theme.theme_secondary,
            bar_workspace_active: Theme.theme_primary,
            bar_workspace_idle: Theme.bg_surface,
            bar_hover_bg: Theme.bg_surface,
            bar_glow_color: "transparent",
            bar_text_raised: false,
            bar_scanline_color: "transparent",
            bar_tip_bg: Theme.bg_crust,
            bar_tip_fg: Theme.fg_core,
            bar_tip_border_width: 1,
            bar_tip_border_color: Theme.fg_muted
        };
        return {
            "default": {
                text_muted: Theme.fg_muted,
                text_dim: Theme.fg_dim,
                font_family: Theme.font_family,
                font_size: Theme.popup_font_size,
                rounded: true,
                frame_follows_island: true,
                frame_color: Theme.bg_mantle,
                frame_radius: 10,
                frame_border_width: 0,
                frame_border_color: "transparent",
                accent_color: Theme.theme_primary,
                accent_height: 3,
                accent_full_width: false,
                selection_bg: Theme.bg_surface,
                selection_inverse: false,
                selection_fg: Theme.bg_crust,
                caret_color: Theme.theme_primary,
                caret_blink: false,
                selection_outline: "transparent",
                tab_active_bg: Theme.bg_surface,
                tab_active_fg: Theme.theme_secondary,
                tab_fg: Theme.fg_muted,
                key_bg: Theme.bg_mantle,
                key_fg: Theme.fg_dim,
                key_border: Theme.ui_border,
                section_fg: Theme.fg_muted,
                section_rule: false,
                footer_fg: Theme.fg_dim,
                footer_rule: false,
                footer_rule_color: Theme.bg_surface,
                meter_on: Theme.theme_primary,
                meter_off: Theme.bg_surface,
                meter_hot: Theme.theme_label,
                meter_radius: 1,
                scale: 1,
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
                toggle_brackets: false,
                toggle_on: Theme.theme_primary,
                toggle_off: Theme.fg_dim,
                marker_fill: false,
                selection_bar: false,
                title_prefix: "",
                title_suffix: "",
                frame_glow: "transparent",
                scanlines: false,
                scanline_color: "transparent",
                glow: false,
                glow_color: "transparent",
                glow_tint: 0,
                frame_shade: "transparent",
                dither: "transparent",
                text_shadow: "transparent",
                fade_fills: false,
                selection_border: "transparent",
                selection_glow: "transparent",
                meter_shade: "transparent",
                corner_scale: 1,
                bar_font_family: Theme.font_family,
                bar_font_size: Theme.font_size,
                bar_side_bg: Theme.bg_core,
                bar_center_bg: Theme.bg_mantle,
                bar_fg: Theme.fg_core,
                bar_border_width: 1,
                bar_border_color: Qt.alpha(Theme.ui_border, 0.5),
                bar_rounded: true,
                bar_workspace_focused: Theme.theme_secondary,
                bar_workspace_active: Theme.theme_primary,
                bar_workspace_idle: Theme.bg_surface,
                bar_hover_bg: Theme.bg_surface,
                bar_glow_color: "transparent",
                bar_text_raised: false,
                bar_scanline_color: "transparent",
                bar_tip_bg: Theme.ui_float_bg,
                bar_tip_fg: Theme.ui_float_fg,
                bar_tip_border_width: 0,
                bar_tip_border_color: "transparent"
            },
            "terminal": terminal,
            "crt": Object.assign({}, terminal, {
                text_muted: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.35)),
                text_dim: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.6)),
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
                bar_fg: Theme.theme_primary_light,
                bar_border_color: Qt.alpha(Theme.theme_primary, 0.5),
                bar_hover_bg: Qt.alpha(Theme.theme_primary, 0.4),
                bar_glow_color: Qt.alpha(Theme.theme_primary, 0.3),
                bar_scanline_color: Qt.alpha(Theme.theme_primary, 0.07),
                bar_tip_fg: Theme.theme_primary_light,
                bar_tip_border_color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.theme_primary, 0.35))
            }),
            "ps1": Object.assign({}, terminal, {
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
                bar_text_raised: true,
                bar_tip_border_width: 2,
                bar_tip_border_color: Theme.fg_dim
            }),
            "ps2": Object.assign({}, terminal, {
                font_family: "Montserrat",
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
                bar_font_family: "Montserrat",
                bar_font_size: Theme.font_size,
                bar_side_bg: Theme.bg_mantle,
                bar_center_bg: Theme.bg_mantle,
                bar_fg: Theme.theme_primary_light,
                bar_border_width: 0,
                bar_border_color: "transparent",
                bar_rounded: true,
                bar_workspace_idle: Qt.alpha(Theme.theme_primary, 0.12),
                bar_hover_bg: Qt.alpha(Theme.theme_primary, 0.2),
                bar_tip_bg: Theme.bg_mantle,
                bar_tip_fg: Theme.theme_primary_light,
                bar_tip_border_color: Qt.alpha(Theme.theme_primary, 0.4)
            })
        };
    }

    readonly property var active: root.styles[root.name] || root.styles["default"]

    readonly property string font_family: root.active.font_family
    readonly property int font_size: root.active.font_size
    readonly property color text_muted: root.active.text_muted
    readonly property color text_dim: root.active.text_dim
    readonly property bool rounded: root.active.rounded
    readonly property bool frame_follows_island: root.active.frame_follows_island
    readonly property color frame_color: root.active.frame_color
    readonly property real frame_radius: root.active.frame_radius
    readonly property int frame_border_width: root.active.frame_border_width
    readonly property color frame_border_color: root.active.frame_border_color
    readonly property color accent_color: root.active.accent_color
    readonly property int accent_height: root.active.accent_height
    readonly property bool accent_full_width: root.active.accent_full_width
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
    readonly property color key_bg: root.active.key_bg
    readonly property color key_fg: root.active.key_fg
    readonly property color key_border: root.active.key_border
    readonly property color section_fg: root.active.section_fg
    readonly property bool section_rule: root.active.section_rule
    readonly property color footer_fg: root.active.footer_fg
    readonly property bool footer_rule: root.active.footer_rule
    readonly property color footer_rule_color: root.active.footer_rule_color
    readonly property color meter_on: root.active.meter_on
    readonly property color meter_off: root.active.meter_off
    readonly property color meter_hot: root.active.meter_hot
    readonly property real meter_radius: root.active.meter_radius
    readonly property real scale: root.active.scale
    readonly property bool show_title: root.active.show_title
    readonly property color title_bg: root.active.title_bg
    readonly property color title_fg: root.active.title_fg
    readonly property bool show_footer: root.active.show_footer
    readonly property bool footer_wrap: root.active.footer_wrap
    readonly property string row_cursor: root.active.row_cursor
    readonly property bool segmented_levels: root.active.segmented_levels
    readonly property bool tab_keys: root.active.tab_keys
    readonly property bool row_keys: root.active.row_keys
    readonly property bool boxed_cards: root.active.boxed_cards
    readonly property bool chip_brackets: root.active.chip_brackets
    readonly property color chip_active_bg: root.active.chip_active_bg
    readonly property color chip_active_fg: root.active.chip_active_fg
    readonly property bool toggle_brackets: root.active.toggle_brackets
    readonly property color toggle_on: root.active.toggle_on
    readonly property color toggle_off: root.active.toggle_off
    readonly property bool marker_fill: root.active.marker_fill
    readonly property bool selection_bar: root.active.selection_bar
    readonly property string title_prefix: root.active.title_prefix
    readonly property string title_suffix: root.active.title_suffix
    readonly property color frame_glow: root.active.frame_glow
    readonly property bool scanlines: root.active.scanlines
    readonly property color scanline_color: root.active.scanline_color
    readonly property bool glow: root.active.glow
    readonly property color glow_color: root.active.glow_color
    readonly property real glow_tint: root.active.glow_tint
    // A diagonal shade from this color at the top left into frame_color.
    readonly property color frame_shade: root.active.frame_shade
    readonly property color dither: root.active.dither
    readonly property color text_shadow: root.active.text_shadow
    // Selection and title fills fade out to the right.
    readonly property bool fade_fills: root.active.fade_fills
    readonly property color selection_border: root.active.selection_border
    readonly property color selection_glow: root.active.selection_glow
    readonly property color meter_shade: root.active.meter_shade
    // Multiplies every radius a rounded style draws.
    readonly property real corner_scale: root.active.corner_scale

    // Saved with the style; off keeps the bar on the default look.
    property bool style_bar: false
    property bool cava_line: true
    readonly property var plain_bar: Object.assign({}, root.styles["default"], {
        bar_border_width: 0,
        bar_border_color: "transparent"
    })
    readonly property var bar: root.style_bar ? root.active : root.plain_bar
    readonly property string bar_font_family: root.bar.bar_font_family
    readonly property int bar_font_size: root.bar.bar_font_size
    readonly property color bar_side_bg: root.bar.bar_side_bg
    readonly property color bar_center_bg: root.bar.bar_center_bg
    readonly property color bar_fg: root.bar.bar_fg
    readonly property int bar_border_width: root.bar.bar_border_width
    readonly property color bar_border_color: root.bar.bar_border_color
    readonly property bool bar_rounded: root.bar.bar_rounded
    // Focused is the workspace you are on; active is the one shown on each other monitor.
    readonly property color bar_workspace_focused: root.bar.bar_workspace_focused
    readonly property color bar_workspace_active: root.bar.bar_workspace_active
    readonly property color bar_workspace_idle: root.bar.bar_workspace_idle
    readonly property color bar_hover_bg: root.bar.bar_hover_bg
    readonly property color bar_glow_color: root.bar.bar_glow_color
    readonly property color bar_scanline_color: root.bar.bar_scanline_color
    readonly property int bar_text_style: root.bar.bar_text_raised ? Text.Raised : root.bar_glow_color.a > 0 ? Text.Outline : Text.Normal
    readonly property color bar_tip_bg: root.bar.bar_tip_bg
    readonly property color bar_tip_fg: root.bar.bar_tip_fg
    readonly property int bar_tip_border_width: root.bar.bar_tip_border_width
    readonly property color bar_tip_border_color: root.bar.bar_tip_border_color

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

    function set_bar(on) {
        root.style_bar = on;
        root.save();
    }

    function set_cava_line(on) {
        root.cava_line = on;
        root.save();
    }

    function save() {
        state_file.setText(JSON.stringify({ style: root.saved_name, style_bar: root.style_bar, cava_line: root.cava_line }));
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
                root.style_bar = data.style_bar === true;
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
