// home/quickshell/.config/quickshell/components/KeyHints.js
.pragma library

const key_glyphs = { Enter: String.fromCodePoint(0xF0311), Esc: String.fromCodePoint(0xF12B7), Tab: String.fromCodePoint(0xF0312), space: String.fromCodePoint(0xF1050), Backspace: String.fromCodePoint(0xF030D) };

function with_glyphs(text) {
    return text.replace(/\b(Enter|Esc|Tab|space|Backspace)\b/g, k => key_glyphs[k]);
}

// Splits "key desc · key desc" into groups; "[ ]" is the one key that contains a space.
function parse(text) {
    return text === "" ? [] : text.split(" · ").map(g => {
        const key = g.startsWith("[ ]") ? "[ ]" : g.split(" ")[0];
        return { key: key, desc: g.slice(key.length).trim() };
    });
}
