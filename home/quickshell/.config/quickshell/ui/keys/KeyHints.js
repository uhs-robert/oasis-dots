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

// Room a drawn cap (key_cap) takes beyond a flat one, read by KeyBadge and by TabRows to reserve it.
function cap_pad_w(st) {
    return st.key_cap === "none" ? 6 : st.key_cap === "ps2_gloss" ? 10 : 8;
}

function cap_gloss_h(st) {
    return st.key_cap === "none" ? 0 : st.key_cap === "ps2_gloss" ? 3 : 2;
}

function cap_font_family(st) {
    return st.pixel_border.a > 0 ? st.font_family : st.mono_font;
}

function cap_font_px(st) {
    return st.key_size > 0 ? st.key_size : st.fs(-5);
}

// Per console (Style.controller): button component (takes button, size, shades) and key -> button map, whole or by "/" halves.
// A button maps only when its face shows the key: Enter is START, Tab is SELECT, the d-pad is hjkl and the arrows, shoulders carry [ or ]
// and face buttons carry their own letter (o and x on a PlayStation pad). Esc, q and Backspace stay plain key caps.
// "?" never maps, so footers always show the help key that explains the buttons.
const dpad_keys = { "j/k": "dpad_v", "h/l": "dpad_h", "Up/Down": "dpad_v", Up: "dpad_up", Down: "dpad_down", Left: "dpad_left", Right: "dpad_right", j: "dpad_down", k: "dpad_up", h: "dpad_left", l: "dpad_right" };
const controllers = {
    nes: { button: "nes/NesButton.qml", keys: Object.assign({ Enter: "start", Tab: "select", a: "a", b: "b" }, dpad_keys) },
    snes: { button: "snes/SnesButton.qml", keys: Object.assign({ Enter: "start", Tab: "select", a: "a", b: "b", x: "x", y: "y", "[ ]": "lr", "[": "l", "]": "r" }, dpad_keys) },
    ps1: { button: "ps1/Ps1Button.qml", keys: Object.assign({ Enter: "start", Tab: "select", o: "circle", x: "cross", "[": "l1", "]": "r1" }, dpad_keys) },
    ps2: { button: "ps2/Ps2Button.qml", keys: Object.assign({ Enter: "start", Tab: "select", o: "circle", x: "cross", "[": "l1", "]": "r1" }, dpad_keys) }
};
// Game Boy pads use the NES buttons, drawn in its four shades (styles/gameboy/widgets/GameboyButton.qml).
controllers.gameboy = { button: "gameboy/GameboyButton.qml", keys: controllers.nes.keys };

// A key as [{ button } | { text }] parts, "/" text between halves; [] when nothing maps.
function controller_parts(controller, key) {
    const map = controllers[controller] ? controllers[controller].keys : null;
    if (!map || !key || key.indexOf("+") >= 0) return [];
    let k = key;
    for (const g in glyph_names) k = k.split(g).join(glyph_names[g]);
    const part_for = p => map[p] === undefined ? { text: p } : { button: map[p] };
    const whole = part_for(k);
    if (whole.button) return [whole];
    const pieces = k === "/" ? ["/"] : k === "[ ]" ? ["[", "]"] : k.split("/");
    const parts = [];
    let hit = false;
    for (const p of pieces) {
        const next = part_for(p);
        if (next.button) hit = true;
        const last = parts[parts.length - 1];
        if (next.button && last && last.button === next.button) continue;
        if (parts.length > 0 && k !== "[ ]") parts.push({ text: "/" });
        parts.push(next);
    }
    return hit ? parts : [];
}

// The button component as "<console>/File.qml", resolved under styles/<console>/widgets/, or "" for a console without drawn buttons.
function button_path(controller) {
    return controllers[controller] ? controllers[controller].button : "";
}
