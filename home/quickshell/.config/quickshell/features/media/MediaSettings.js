.pragma library

// What to copy from the old style.json cava_line into media.json, or null when media.json already holds one.
// `raw` is media.json's parsed top level ({} or null when missing or corrupt); a missing old key meant on.
function migrated_cava_line(raw, legacy) {
    if (raw && typeof raw.cava_line === "boolean") return null;
    return legacy !== false;
}

// island_mode governs island styles only (`island_style`); strip, frame, lualine and side-bar layouts ignore it.
// An unknown mode acts as cava_under_island.

// Whether the media/cava bar module is built for this bar.
function module_listed(island_style, mode) {
    return !island_style || mode === "module_only" || mode === "split";
}

// Whether the island-edge cava under the clock may draw.
function edge_cava_allowed(island_style, mode) {
    return !island_style || mode !== "module_only";
}

// Split keeps the strip under the clock, so the module shows the position instead of a second visualizer.
// Lualine draws its own cava at the end of section c, so a listed media module never adds a second one there.
function module_position_only(island_style, mode, lualine) {
    return !!lualine || (island_style && mode === "split");
}

// What the strip under the clock island draws: "cava", "position" (a progress line) or "none". On battery cava is too
// costly, so island styles follow `battery_fallback`; any other layout draws nothing there, as before.
function edge_strip(island_style, mode, on_ac, fallback) {
    if (!edge_cava_allowed(island_style, mode)) return "none";
    if (on_ac) return "cava";
    return island_style && fallback === "position" ? "position" : "none";
}

// What a wheel notch over the media module does. The right side (cava or position) always seeks, so seeking needs no
// modifier key: a layer-shell bar never holds keyboard focus and so never sees Shift. Anywhere else the wheel follows
// `scroll_action`: "volume", "skip" or "none".
function scroll_effect(over_right_side, scroll_action) {
    if (over_right_side) return "seek";
    return scroll_action === "skip" ? "skip" : scroll_action === "none" ? "none" : "volume";
}

// Which right side the module draws. A forced one (split mode, lualine) wins; otherwise the setting decides for the
// `media` and `cava` entries alike. On battery cava gives way to `battery_fallback`.
function right_side(forced, setting, on_ac, battery_fallback) {
    const wanted = forced !== "" ? forced : setting;
    return wanted === "cava" && !on_ac ? battery_fallback : wanted;
}

// Whether the module has anything to show: any active player, with or without metadata (a radio stream has none), but
// not as the `cava` entry on a side bar, which keeps its cava tail instead.
function well_shown(has_player, vertical, is_cava_entry) {
    return !!has_player && !(vertical && is_cava_entry);
}

// Whether the clock-island strip is asked for: a `cava` entry always did, and a `media` entry does too, since in the
// default island mode that entry is dropped and would otherwise leave nothing at all.
function strip_listed(lists_cava, lists_media) {
    return !!lists_cava || !!lists_media;
}

// How the media container is drawn: `fill` (shadow, wash or none), `border` (strong, soft or none) and whether the
// pressed-in top shadow shows. "none" draws nothing, so the contents sit on the bar; the padding is the caller's and
// does not change with the style. An unknown style acts as inset.
function container_look(container_style) {
    switch (container_style) {
    case "border": return { fill: "none", border: "strong", top_shadow: false };
    case "raised": return { fill: "wash", border: "none", top_shadow: false };
    case "none": return { fill: "none", border: "none", top_shadow: false };
    default: return { fill: "shadow", border: "soft", top_shadow: true };
    }
}
