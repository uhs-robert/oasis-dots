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

const glyph_names = Object.keys(key_glyphs).reduce((m, k) => {
    m[key_glyphs[k]] = k;
    return m;
}, {});

// Key cap text and ring, shared by the caps (KeyBadge, HeaderButton) and the layouts that reserve room for them.
// A pixel ring (Game Boy) gets a 2px ring and the body font; Press Start 2P read too large there at a legible size.
function cap_ring_width(st) {
    return st.pixel_border.a > 0 ? 2 : 1;
}

function cap_font_family(st) {
    return st.pixel_border.a > 0 ? st.font_family : st.mono_font;
}

function cap_font_px(st) {
    return st.key_size > 0 ? st.key_size : st.fs(-5);
}

// Per console (Style.controller): button component (takes button, size, shades) and key -> button map, whole or by "/" halves.
// "?" never maps, so footers always show the help key that explains the buttons.
const controllers = {
    nes: { button: "nes/NesButton.qml", keys: { Enter: "a", Backspace: "b", q: "start", Esc: "start", Tab: "select", "j/k": "dpad_v", "h/l": "dpad_h", "Up/Down": "dpad_v", j: "dpad_v", k: "dpad_v", h: "dpad_h", l: "dpad_h" } },
    snes: { button: "snes/SnesButton.qml", keys: { Enter: "a", Backspace: "b", q: "start", Esc: "start", Tab: "select", "/": "y", "[ ]": "lr", "[": "l", "]": "r", t: "x", "j/k": "dpad_v", "h/l": "dpad_h", "Up/Down": "dpad_v", j: "dpad_v", k: "dpad_v", h: "dpad_h", l: "dpad_h" } },
    ps1: { button: "ps1/Ps1Button.qml", keys: { Enter: "circle", Backspace: "cross", q: "start", Esc: "start", Tab: "select", "/": "triangle", "[": "l1", "]": "r1", t: "square", gg: "l2", G: "r2", "j/k": "dpad_v", "h/l": "dpad_h", "Up/Down": "dpad_v", j: "dpad_down", k: "dpad_up", h: "dpad_left", l: "dpad_right" } },
    ps2: { button: "ps2/Ps2Button.qml", keys: { Enter: "cross", Backspace: "circle", q: "start", Esc: "start", Tab: "select", "/": "triangle", "[": "l1", "]": "r1", t: "square", gg: "l2", G: "r2", "j/k": "dpad_v", "h/l": "dpad_h", "Up/Down": "dpad_v", j: "dpad_v", k: "dpad_v", h: "dpad_h", l: "dpad_h" } }
};
// Game Boy pads use the NES buttons, drawn in its four shades (components/gameboy/GameboyButton.qml).
controllers.gameboy = { button: "gameboy/GameboyButton.qml", keys: controllers.nes.keys };

// Esc takes START only where it closes the popup; as cancel/back (n/Esc, Tab/Esc list) it shows the back button.
function button_for(map, key, desc) {
    return map[key === "Esc" && desc && !/\bclose\b/.test(desc) ? "Backspace" : key];
}

// Directions and shoulders read as what they do on a keyboard; face and menu buttons only mean something once you know their key.
const self_evident = ["dpad_v", "dpad_h", "dpad_up", "dpad_down", "dpad_left", "dpad_right", "l", "r", "lr", "l1", "r1"];

// A key (glyphs allowed) as [{ button, label? } | { text }] parts, "/" text between halves; [] when nothing maps.
// glyphs is Style.controller_glyphs: "dpad" keeps other buttons as key text, "labeled" gives them their key as label.
function controller_parts(controller, key, desc, glyphs) {
    const map = controllers[controller] ? controllers[controller].keys : null;
    if (!map || !key || key.indexOf("+") >= 0) return [];
    let k = key;
    for (const g in glyph_names) k = k.split(g).join(glyph_names[g]);
    const part_for = p => {
        const b = button_for(map, p, desc);
        const evident = self_evident.indexOf(b) >= 0;
        if (b === undefined || (glyphs === "dpad" && !evident)) return { text: p };
        return glyphs === "labeled" && !evident ? { button: b, label: p } : { button: b };
    };
    const whole = part_for(k);
    if (whole.button) return [whole];
    const pieces = k === "/" ? ["/"] : k === "[ ]" ? ["[", "]"] : k.split("/");
    const parts = [];
    let hit = false;
    for (const p of pieces) {
        const next = part_for(p);
        if (next.button) hit = true;
        const last = parts[parts.length - 1];
        if (next.button && last && last.button === next.button) {
            if (last.label) last.label += "/" + p;
            continue;
        }
        if (parts.length > 0 && k !== "[ ]") parts.push({ text: "/" });
        parts.push(next);
    }
    return hit ? parts : [];
}

// The button component's path under components/, or "" for a console without drawn buttons.
function button_path(controller) {
    return controllers[controller] ? controllers[controller].button : "";
}
