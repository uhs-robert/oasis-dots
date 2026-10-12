// home/quickshell/.config/quickshell/popups/keeptabs/KeeptabsFormat.js
.pragma library

// A library cannot see Style, so callers pass the colors in: error, ok, warning, text_primary and text_dim.
function state_color(state, colors) {
    if (state === "waiting") return colors.error;
    if (state === "done") return colors.ok;
    if (state === "running") return colors.text_primary;
    return colors.text_dim;
}

// Below 60% the primary color, 60-85% a warning, above that an error.
function context_bar_color(pct, colors) {
    if (pct >= 85) return colors.error;
    if (pct >= 60) return colors.warning;
    return colors.text_primary;
}

function fmt_tokens(n) {
    if (n === null || n === undefined) return "0";
    if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, "") + "M";
    if (n >= 1000) return Math.round(n / 1000) + "k";
    return String(n);
}

function age(since) {
    const s = Math.floor(Date.now() / 1000) - since;
    if (s < 60) return s + "s";
    if (s < 3600) return Math.floor(s / 60) + "m";
    return Math.floor(s / 3600) + "h";
}
