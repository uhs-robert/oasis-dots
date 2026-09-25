// home/quickshell/.config/quickshell/components/neovim/Modes.js
.pragma library

// The Neovim mode family of a Hyprland submap name; "" is the global (reset) submap.
function kind(name) {
    const n = (name || "").toUpperCase();
    if (n === "" || n === "NORMAL" || n === "GOTO") return "normal";
    if (n === "INSERT") return "insert";
    if (n === "VISUAL" || n === "G-VISUAL" || n === "G-VLINE" || n.startsWith("V-")) return "visual";
    if (n === "R-CHAR") return "replace";
    return "submap";
}

function label(name) {
    return name === "" ? "HYPRVIM" : name.toUpperCase();
}

// The idle (global) submap takes tmux-oasis's normal-mode colour.
function color(name, theme, submap_color) {
    if (!name) return theme.theme_primary_strong;
    const k = kind(name);
    return k === "normal" ? theme.theme_primary : k === "insert" ? theme.syntax_string : k === "visual" ? theme.syntax_special : k === "replace" ? theme.syntax_exception : submap_color;
}
