// home/quickshell/.config/quickshell/theme/Style.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Watch.js" as Watch
import "styles/index.js" as Styles

Singleton {
    id: root

    property string name: "oasis"
    // The saved choice; `name` differs from it only while the style picker previews.
    property string saved_name: "oasis"
    // Everyday styles, then consoles by release year, then sci-fi.
    readonly property var order: ["oasis", "modern", "neovim", "terminal", "crt", "nes", "gameboy", "snes", "ps1", "ff7", "goldeneye", "ps2", "tie", "halflife", "metroid", "reticle"]
    readonly property var names: root.order.filter(n => n in root.styles).concat(Object.keys(root.styles).filter(n => root.order.indexOf(n) < 0))
    readonly property var labels: ({ crt: "CRT", nes: "NES", snes: "SNES", gameboy: "Gameboy", goldeneye: "Goldeneye", ps1: "PSX", ff7: "FFVII", ps2: "PS2", halflife: "Half Life", tie: "Tie Fighter", modern: "Modern" })

    FileView {
        id: skin_index
        path: Qt.resolvedUrl("../lock/skins/index.json")
        blockLoading: true
        printErrors: false
    }

    // Per-skin metadata from lock/skins/index.json.
    readonly property var lock_skins: {
        try {
            return JSON.parse(skin_index.text());
        } catch (e) {
            return {};
        }
    }

    // Lock screens with no bar style of their own yet, name to label; never in `names`.
    readonly property var lock_only: {
        const out = {};
        for (const key of Object.keys(root.lock_skins)) if (root.lock_skins[key].lock_only) out[key] = root.lock_skins[key].label;
        return out;
    }
    readonly property var lock_only_names: Object.keys(root.lock_only)

    function label(style_name) {
        return root.labels[style_name] || root.lock_only[style_name] || style_name.charAt(0).toUpperCase() + style_name.slice(1);
    }

    readonly property var styles: Styles.build(Theme, root.version)

    // Quickshell only watches JS that QML imports directly, so edits to the style files reload the shell here.
    Instantiator {
        model: Styles.sources
        delegate: FileView {
            required property string modelData
            path: Qt.resolvedUrl("styles/" + modelData)
            watchChanges: true
            printErrors: false
            onFileChanged: Quickshell.reload(false)
        }
    }

    readonly property var base_active: root.styles[root.name] || root.styles["oasis"]
    readonly property var active: {
        const opts = root.theme_values[root.styles[root.name] ? root.name : "oasis"];
        return opts ? root.with_options(root.base_active, opts) : root.base_active;
    }
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
        o.custom_frame = o.frame_octagon > 0 || o.slant_frame;
        o.inset_pad = o.frame_inset_width > 0 ? o.frame_border_width + o.frame_inset_gap + o.frame_inset_width : o.frame_pad;
        o.fs = k => o.font_size + (o.type_scale && o.type_scale[k] !== undefined ? o.type_scale[k] : k);
        return o;
    }

    // A text size as font_size plus an offset, through the style's type_scale.
    function fs(k) {
        const v = root.type_scale[k];
        return root.font_size + (v !== undefined ? v : k);
    }

    // Toggled by the open popup's blink timer; the caret is solid whenever it rests true.
    property bool caret_phase: true

    property bool cava_line: true
    readonly property var bar: root.active

    // BEGIN generated: scripts/gen-style-exports writes these lines from StyleSchema.js
    readonly property var pal: root.active.pal
    readonly property var wk: root.active.wk
    readonly property string watch_mode: (root.theme_values.goldeneye || {}).watch_colors || "Theme"
    readonly property color text_muted: root.active.text_muted
    readonly property color text_dim: root.active.text_dim
    readonly property color text_fg: root.active.text_fg
    readonly property color text_strong: root.active.text_strong
    readonly property color text_primary: root.active.text_primary
    readonly property color text_accent: root.active.text_accent
    readonly property string font_family: root.active.font_family
    readonly property int font_size: root.active.font_size
    readonly property string number_font: root.active.number_font !== "" ? root.active.number_font : root.font_family
    readonly property string title_font_family: root.active.title_font_family || root.font_family
    readonly property bool rounded: root.active.rounded
    readonly property bool frame_follows_island: root.active.frame_follows_island
    readonly property color frame_color: root.active.frame_color
    readonly property real frame_radius: root.active.frame_radius
    readonly property int frame_border_width: root.active.frame_border_width
    readonly property color frame_border_color: root.active.frame_border_color
    readonly property real frame_chamfer: root.active.frame_chamfer
    readonly property bool frame_visor: root.active.frame_visor
    readonly property int frame_inset_gap: root.active.frame_inset_gap
    readonly property int frame_inset_width: root.active.frame_inset_width
    readonly property color frame_inset_color: root.active.frame_inset_color
    readonly property int inset_pad: root.frame_inset_width > 0 ? root.frame_border_width + root.frame_inset_gap + root.frame_inset_width : root.active.frame_pad
    readonly property int frame_drop: root.active.frame_drop
    readonly property color lcd_top: root.active.lcd_top
    readonly property color lcd_bottom: root.active.lcd_bottom
    readonly property color lcd_scan: root.active.lcd_scan
    readonly property int lcd_margin: root.active.lcd_margin
    readonly property string frame_engraving: root.active.frame_engraving
    readonly property bool frame_watch: root.active.frame_watch
    readonly property string link_style: root.active.link_style
    readonly property bool ammo_counter: root.active.ammo_counter
    readonly property bool night_vision: root.active.night_vision
    readonly property bool toast_mission: root.active.toast_mission
    readonly property bool track_bars: root.active.track_bars
    readonly property string open_fx: root.active.open_fx
    readonly property string confirm_layout: root.active.confirm_layout
    readonly property color accent_color: root.active.accent_color
    readonly property int accent_height: root.active.accent_height
    readonly property bool accent_full_width: root.active.accent_full_width
    readonly property bool frame_top_rule: root.active.frame_top_rule
    readonly property color selection_bg: root.active.selection_bg
    readonly property bool selection_inverse: root.active.selection_inverse
    readonly property color selection_fg: root.active.selection_fg
    readonly property color caret_color: root.active.caret_color
    readonly property bool caret_blink: root.active.caret_blink
    readonly property color selection_outline: root.active.selection_outline
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
    readonly property bool label_caps: root.active.label_caps
    readonly property real label_spacing: root.active.label_spacing
    readonly property color section_fade: root.active.section_fade
    readonly property color footer_fg: root.active.footer_fg
    readonly property color footer_key_fg: root.active.footer_key_fg
    readonly property bool footer_rule: root.active.footer_rule
    readonly property color footer_rule_color: root.active.footer_rule_color
    readonly property color meter_on: root.active.meter_on
    readonly property color meter_off: root.active.meter_off
    readonly property color meter_hot: root.active.meter_hot
    readonly property real meter_radius: root.active.meter_radius
    readonly property color meter_outline: root.active.meter_outline
    readonly property real scale: root.active.scale
    readonly property real popup_min_width: root.active.popup_min_width
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
    readonly property string title_readout: root.active.title_readout
    readonly property color title_readout_fg: root.active.title_readout_fg
    readonly property color title_rule: root.active.title_rule
    readonly property color frame_glow: root.active.frame_glow
    readonly property bool scanlines: root.active.scanlines
    readonly property color scanline_color: root.active.scanline_color
    readonly property int scanline_period: root.active.scanline_period
    readonly property bool glow: root.active.glow
    readonly property color glow_color: root.active.glow_color
    readonly property real glow_tint: root.active.glow_tint
    readonly property color frame_shade: root.active.frame_shade
    readonly property bool shade_vertical: root.active.shade_vertical
    readonly property color dither: root.active.dither
    readonly property color text_shadow: root.active.text_shadow
    readonly property bool fade_fills: root.active.fade_fills
    readonly property color selection_border: root.active.selection_border
    readonly property color selection_glow: root.active.selection_glow
    readonly property color meter_shade: root.active.meter_shade
    readonly property real meter_slant: root.active.meter_slant
    readonly property bool meter_bloom: root.active.meter_bloom
    readonly property real chart_slant: root.active.chart_slant
    readonly property color chart_fill: root.active.chart_fill
    readonly property real corner_scale: root.active.corner_scale
    readonly property string mono_font: root.active.mono_font || root.font_family
    readonly property color selection_rule: root.active.selection_rule
    readonly property color tab_bg: root.active.tab_bg
    readonly property color chip_bg: root.active.chip_bg
    readonly property real meter_height: root.active.meter_height
    readonly property color footer_key_bg: root.active.footer_key_bg
    readonly property string footer_separator: root.active.footer_separator
    readonly property bool footer_rule_solid: root.active.footer_rule_solid
    readonly property string osd_layout: root.active.osd_layout
    readonly property string level_layout: root.active.level_layout
    readonly property string card_layout: root.active.card_layout
    readonly property string weather_header: root.active.weather_header
    readonly property string picker_skin: root.active.picker_skin
    readonly property color picker_hud: root.active.picker_hud
    readonly property string picker_hint_keys: root.active.picker_hint_keys || ""
    readonly property bool bar_pill_square: root.bar.bar_pill_square
    readonly property string bar_font_family: root.bar.bar_font_family
    readonly property int bar_font_size: root.bar.bar_font_size
    readonly property int bar_capitalization: root.bar.bar_caps ? Font.AllUppercase : Font.MixedCase
    readonly property real bar_letter_spacing: root.bar.bar_letter_spacing
    readonly property color bar_side_bg: root.bar.bar_side_bg
    readonly property color bar_center_bg: root.bar.bar_center_bg
    readonly property color bar_fg: root.bar.bar_fg
    readonly property color bar_clock_bg: root.bar.bar_clock_bg
    readonly property color bar_clock_fg: root.bar.bar_clock_fg
    readonly property string bar_clock_font: root.bar.bar_clock_font || root.bar_font_family
    readonly property int bar_clock_size: root.bar.bar_clock_size
    readonly property int bar_glyph_size: root.bar.bar_glyph_size > 0 ? root.bar.bar_glyph_size : Theme.glyph_size
    readonly property int bar_badge_size: root.bar.bar_glyph_size > 0 ? Math.round(root.bar.bar_glyph_size * 0.62) : Math.max(6, root.bar_font_size - 3)
    readonly property int bar_border_width: root.bar.bar_border_width
    readonly property color bar_border_color: root.bar.bar_border_color
    readonly property bool bar_rounded: root.bar.bar_rounded
    readonly property color bar_workspace_focused: root.bar.bar_workspace_focused
    readonly property color bar_workspace_active: root.bar.bar_workspace_active
    readonly property color bar_workspace_idle: root.bar.bar_workspace_idle
    readonly property color bar_workspace_ring: root.bar.bar_workspace_ring
    readonly property int bar_inset_gap: root.bar.bar_inset_gap
    readonly property int bar_inset_width: root.bar.bar_inset_width
    readonly property color bar_inset_color: root.bar.bar_inset_color
    readonly property color bar_hover_bg: root.bar.bar_hover_bg
    readonly property color bar_glow_color: root.bar.bar_glow_color
    readonly property string done_anim: root.active.done_anim || "hearts"
    readonly property string wait_anim: root.active.wait_anim || "bubble"
    readonly property color bar_scanline_color: root.bar.bar_scanline_color
    readonly property string label_font_family: root.active.label_font_family || root.font_family
    readonly property real frame_octagon: root.active.frame_octagon
    readonly property color frame_struts: root.active.frame_struts
    readonly property bool custom_frame: root.frame_octagon > 0 || root.slant_frame
    readonly property real lcd_radius: root.active.lcd_radius
    readonly property color lcd_border: root.active.lcd_border
    readonly property color lcd_brackets: root.active.lcd_brackets
    readonly property color selection_brackets: root.active.selection_brackets
    readonly property color tab_brackets: root.active.tab_brackets
    readonly property color tab_rule: root.active.tab_rule
    readonly property color title_reticle: root.active.title_reticle
    readonly property color chart_outline: root.active.chart_outline
    readonly property bool bar_workspace_diamond: root.bar.bar_workspace_diamond
    readonly property color bar_clock_brackets: root.bar.bar_clock_brackets
    readonly property string bar_separator: root.bar.bar_separator
    readonly property color bar_tick_color: root.bar.bar_center_bg.hslLightness > 0.6 ? Theme.fg_core : Watch.white
    readonly property string bar_island_shape: root.bar.bar_island_shape
    readonly property color hairline: root.active.hairline
    readonly property color hairline_dim: root.active.hairline_dim
    readonly property string frame_ticks: root.active.frame_ticks
    readonly property bool tick_ruler: root.active.tick_ruler
    readonly property bool range_line: root.active.range_line
    readonly property bool key_round: root.active.key_round
    readonly property bool pill_chips: root.active.pill_chips
    readonly property var title_index: root.active.title_index
    readonly property int title_weight: root.active.title_weight
    readonly property color title_trail: root.active.title_trail
    readonly property color bar_ticks: root.bar.bar_ticks
    readonly property color title_strip: root.active.title_strip
    readonly property real caps_tracking: root.active.caps_tracking
    readonly property color tab_outline: root.active.tab_outline
    readonly property color shade_0: root.active.shade_0
    readonly property color shade_1: root.active.shade_1
    readonly property color shade_2: root.active.shade_2
    readonly property color shade_3: root.active.shade_3
    readonly property color pixel_border: root.active.pixel_border
    readonly property bool device_shell: root.active.device_shell
    readonly property string device_model: root.active.device_model
    readonly property var window_gradient: root.active.window_gradient
    readonly property var materia: root.active.materia
    readonly property bool hand_cursor: root.active.hand_cursor
    readonly property bool meter_solid: root.active.meter_solid
    readonly property string controller: root.active.controller
    readonly property var meter_art: root.active.meter_art
    readonly property string toast_enter: root.active.toast_enter
    readonly property string console_views: root.active.console_views
    readonly property string workspace_art: root.active.workspace_art
    readonly property bool slant_frame: root.active.slant_frame
    readonly property int slant_room: root.slant_frame ? 8 : 0
    readonly property bool footer_moon: root.active.footer_moon
    readonly property color selection_edge: root.active.selection_edge
    readonly property bool chip_tabs: root.active.chip_tabs
    readonly property bool title_case: root.active.title_case
    readonly property int title_size: root.active.title_size
    readonly property int frame_float: root.active.frame_float
    readonly property color frame_shadow: root.active.frame_shadow
    readonly property color sheen: root.active.sheen
    readonly property color selection_shade: root.active.selection_shade
    readonly property color tab_well: root.active.tab_well
    readonly property color tab_active_shade: root.active.tab_active_shade
    readonly property bool tab_key_plain: root.active.tab_key_plain
    readonly property bool title_status: root.active.title_status
    readonly property color chip_fg: root.active.chip_fg
    readonly property int bar_capsule: root.bar.bar_capsule
    readonly property int bar_capsule_pad: root.bar.bar_capsule_pad
    readonly property int bar_height: root.bar.bar_height
    readonly property int bar_module_gap: root.bar.bar_module_gap
    readonly property int bar_pill_height: root.bar.bar_pill_height
    readonly property int bar_pill_pad: root.bar.bar_pill_pad
    readonly property int bar_workspace_gap: root.bar.bar_workspace_gap
    readonly property color bar_workspace_shade: root.bar.bar_workspace_shade
    readonly property color bar_workspace_dot: root.bar.bar_workspace_dot
    readonly property string bar_clock_layout: root.bar.bar_clock_layout
    readonly property color bar_start_well: root.bar.bar_start_well
    readonly property bool border_title: root.active.border_title
    readonly property bool row_gutter: root.active.row_gutter
    readonly property color tab_marker: root.active.tab_marker
    readonly property bool section_fold: root.active.section_fold
    readonly property string footer_arrow: root.active.footer_arrow
    readonly property bool footer_italic: root.active.footer_italic
    readonly property int footer_size: root.active.footer_size
    readonly property string whichkey_arrow: root.active.whichkey_arrow
    readonly property int whichkey_size: root.active.whichkey_size
    readonly property var type_scale: root.active.type_scale || ({})
    readonly property real meter_gap: root.active.meter_gap
    readonly property string meter_palette: root.active.meter_palette
    readonly property bool bar_lualine: root.bar.bar_lualine
    readonly property int bar_text_style: root.bar.bar_text_raised ? Text.Raised : root.bar_glow_color.a > 0 ? Text.Outline : Text.Normal
    // END generated

    // A title as the token set `st` (this singleton when omitted) shows it: all-caps words of three letters or more recased under title_case.
    function title_text(text, st) {
        const t = text || "";
        return (st || root).title_case ? t.replace(/\b[A-Z]{3,}\b/g, w => w.charAt(0) + w.slice(1).toLowerCase()) : t;
    }

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
        const saved = root.save_choice(style_name);
        if (saved !== "") root.name = saved;
        return saved !== "";
    }

    // Saves the choice without changing the displayed style; returns the saved name, or "" if unknown.
    function save_choice(style_name) {
        if (style_name === "default") style_name = "oasis";
        if (!(style_name in root.styles)) {
            console.warn("Style: unknown style " + style_name);
            return "";
        }
        root.saved_name = style_name;
        root.save();
        return style_name;
    }

    // The lock screen's own style: "follow" for the active one, "simple" for the plain generic screen.
    property string lock_style: "follow"
    readonly property string lock_name: root.lock_style === "follow" ? root.name : root.lock_style
    // The lock skins' colour family.
    property string lock_tint: "primary"
    readonly property var lock_tints: ["primary", "secondary", "green", "amber", "white"]
    // What the simple lock draws behind its card: the desktop pixelated, blurred, or nothing.
    property string lock_backdrop: "pixelate"
    readonly property var lock_backdrops: ["pixelate", "blur", "off"]
    // Lock skins with music play it only while this is on.
    property bool lock_music: true

    function valid_lock_style(style_name) {
        return style_name === "follow" || style_name === "simple" || root.lock_only_names.indexOf(style_name) >= 0 || (style_name in root.styles);
    }

    function set_lock_style(style_name) {
        if (!root.valid_lock_style(style_name)) return false;
        root.lock_style = style_name;
        root.save_lock();
        return true;
    }

    function set_lock_tint(tint) {
        if (root.lock_tints.indexOf(tint) < 0) return false;
        root.lock_tint = tint;
        root.save_lock();
        return true;
    }

    function set_lock_backdrop(mode) {
        if (root.lock_backdrops.indexOf(mode) < 0) return false;
        root.lock_backdrop = mode;
        root.save_lock();
        return true;
    }

    function set_lock_music(on) {
        root.lock_music = on;
        root.save_lock();
    }

    // Per-style option values by style then key, from theme_options.json; only values that differ from the style's own are kept.
    property var theme_values: ({})
    // The current style's option schema: [{ key, label, type, default, choices | min, max, step }].
    readonly property var settings: root.settings_for(root.saved_name)
    readonly property var font_choices: {
        const seen = {};
        for (const n in root.styles) {
            if (root.styles[n].font_family) seen[root.styles[n].font_family] = true;
            if (root.styles[n].bar_font_family) seen[root.styles[n].bar_font_family] = true;
        }
        return Object.keys(seen).sort();
    }

    function settings_for(style_name) {
        const b = root.styles[style_name];
        if (!b) return [];
        const out = [];
        const flag = (key, label) => out.push({ key: key, label: label, type: "bool", default: true });
        if (b.models) out.push({ key: "device_model", label: "Model", type: "choice", default: b.device_model, choices: Object.keys(b.model_labels), labels: b.model_labels });
        if (b.scanlines === true) flag("scanlines", "Scanlines");
        if (b.glow === true) {
            flag("glow", "Glow");
            out.push({ key: "glow_tint", label: "Glow strength", type: "number", default: b.glow_tint, min: 0, max: 1, step: 0.05 });
        }
        if (b.dither !== undefined && Qt.color(b.dither).a > 0) flag("dither", "Dither");
        if (b.meter_bloom === true) flag("meter_bloom", "Meter bloom");
        if (b.caret_blink === true) flag("caret_blink", "Caret blink");
        if (b.fade_fills === true) flag("fade_fills", "Fade fills");
        if (b.watch_classic) out.push({ key: "watch_colors", label: "Watch colours", type: "choice", default: "Theme", choices: ["Theme", "Classic"] });
        out.push({ key: "font_family", label: "Font", type: "choice", default: b.font_family, choices: root.font_choices });
        out.push({ key: "bar_font_family", label: "Bar font", type: "choice", default: b.bar_font_family, choices: root.font_choices });
        out.push({ key: "font_size", label: "Text size", type: "number", default: b.font_size, min: 8, max: 32, step: 1 });
        return out;
    }

    // The value of option `key` for the current style: the saved one, else the style's own.
    function option(key) {
        const def = root.settings.find(d => d.key === key);
        if (!def) return undefined;
        const saved = (root.theme_values[root.saved_name] || {})[key];
        return saved !== undefined ? saved : def.type === "bool" ? true : def.default;
    }

    function set_option(key, value) {
        const def = root.settings.find(d => d.key === key);
        if (!def || !root.valid_option(def, value)) return false;
        const all = Object.assign({}, root.theme_values);
        const mine = Object.assign({}, all[root.saved_name] || {});
        if (value === (def.type === "bool" ? true : def.default)) delete mine[key];
        else mine[key] = value;
        if (Object.keys(mine).length > 0) all[root.saved_name] = mine;
        else delete all[root.saved_name];
        root.theme_values = all;
        root.save_options();
        return true;
    }

    function reset_options() {
        const all = Object.assign({}, root.theme_values);
        delete all[root.saved_name];
        root.theme_values = all;
        root.save_options();
    }

    function valid_option(def, value) {
        if (def.type === "bool") return typeof value === "boolean";
        if (def.type === "choice") return def.choices.indexOf(value) >= 0;
        return typeof value === "number" && isFinite(value) && value >= def.min && value <= def.max;
    }

    // A style's tokens with its picked model's and the saved option values laid over them; dither is a colour, so off blanks it.
    function with_options(base, opts) {
        const o = Object.assign({}, base, base.models ? base.models[opts.device_model] : null);
        for (const k in opts) {
            if (k === "dither") o.dither = "transparent";
            else o[k] = opts[k];
        }
        if (o.watch_colors === "Classic" && o.watch_classic) Object.assign(o, o.watch_classic);
        return o;
    }

    function save_options() {
        options_file.setText(JSON.stringify(root.theme_values));
    }

    function load_options(data) {
        const all = {};
        for (const style_name in data) {
            const mine = {};
            for (const def of root.settings_for(style_name)) {
                const v = data[style_name] ? data[style_name][def.key] : undefined;
                if (v !== undefined && root.valid_option(def, v) && v !== (def.type === "bool" ? true : def.default)) mine[def.key] = v;
            }
            if (Object.keys(mine).length > 0) all[style_name] = mine;
        }
        root.theme_values = all;
    }

    function set_cava_line(on) {
        root.cava_line = on;
        root.save();
    }

    function save() {
        state_file.setText(JSON.stringify({ style: root.saved_name, cava_line: root.cava_line }));
    }

    function save_lock() {
        lock_file.setText(JSON.stringify({ lock_style: root.lock_style, lock_tint: root.lock_tint, lock_backdrop: root.lock_backdrop, lock_music: root.lock_music }));
    }

    function load_lock(data) {
        if (typeof data.lock_style === "string" && root.valid_lock_style(data.lock_style)) root.lock_style = data.lock_style;
        if (root.lock_tints.indexOf(data.lock_tint) >= 0) root.lock_tint = data.lock_tint;
        if (root.lock_backdrops.indexOf(data.lock_backdrop) >= 0) root.lock_backdrop = data.lock_backdrop;
        root.lock_music = data.lock_music !== false;
    }

    function preview(style_name) {
        if (style_name in root.styles) root.name = style_name;
    }

    readonly property string state_dir: Paths.state_dir

    Process {
        id: ensure_state_dir
        command: ["mkdir", "-p", root.state_dir]
    }

    FileView {
        id: version_file
        path: Qt.resolvedUrl("../VERSION")
        blockLoading: true
        printErrors: false
    }

    // The optional VERSION file at the config root, as on the lock skin's header.
    readonly property string version: version_file.text().trim() || "0.0"

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
                root.legacy_lock = data;
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

    property var legacy_lock: null

    FileView {
        id: options_file
        path: root.state_dir + "/theme_options.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                root.load_options(JSON.parse(text()));
            } catch (e) {
                console.warn("Style: invalid theme_options.json (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }

    FileView {
        id: lock_file
        path: root.state_dir + "/lock.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                root.load_lock(JSON.parse(text()));
            } catch (e) {
                console.warn("Style: invalid lock.json (" + e + ")");
            }
        }
        onLoadFailed: error => {
            if (!root.legacy_lock) return;
            root.load_lock(root.legacy_lock);
            root.save_lock();
        }
    }

    Component.onCompleted: {
        ensure_state_dir.running = true;
        state_file.reload();
        lock_file.reload();
        options_file.reload();
    }
}
