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
function module_position_only(island_style, mode) {
    return island_style && mode === "split";
}

// What the strip under the clock island draws: "cava", "position" (a progress line) or "none". On battery cava is too
// costly, so island styles follow `battery_fallback`; any other layout draws nothing there, as before.
function edge_strip(island_style, mode, on_ac, fallback) {
    if (!edge_cava_allowed(island_style, mode)) return "none";
    if (on_ac) return "cava";
    return island_style && fallback === "position" ? "position" : "none";
}
