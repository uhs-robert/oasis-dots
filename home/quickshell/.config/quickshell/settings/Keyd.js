.pragma library

// Reads keyd's config so Settings can show the remaps that really apply; nothing here writes it.

const KEY_NAMES = {
    capslock: "Caps Lock", leftcontrol: "Left Ctrl", rightcontrol: "Right Ctrl", leftalt: "Left Alt", rightalt: "Right Alt",
    leftshift: "Left Shift", rightshift: "Right Shift", leftmeta: "Left Super", rightmeta: "Right Super",
    esc: "Escape", tab: "Tab", enter: "Enter", space: "Space", backspace: "Backspace", delete: "Delete",
    left: "Left", right: "Right", up: "Up", down: "Down", home: "Home", end: "End",
    pageup: "Page up", pagedown: "Page down", insert: "Insert", compose: "Compose", menu: "Menu"
};

// Hold-layer suffixes keyd accepts after a layer name, e.g. [ctrl_vim:C].
const MODIFIER_NAMES = { C: "Ctrl", S: "Shift", A: "Alt", M: "Super", G: "AltGr" };
const MODIFIER_PREFIXES = { C: "Ctrl+", S: "Shift+", A: "Alt+", M: "Super+", G: "AltGr+" };

// Vim layer actions worth wording by hand; anything else falls back to the raw value.
const ACTION_NAMES = {
    left: "Left", right: "Right", up: "Up", down: "Down", home: "Line start", end: "Line end",
    "C-left": "Word back", "C-right": "Word forward", "C-up": "Paragraph up", "C-down": "Paragraph down",
    "C-home": "Document start", "C-end": "Document end", "C-z": "Undo", "C-y": "Redo", "C-v": "Paste", "C-c": "Copy", "C-f": "Find",
    f3: "Find next", "S-f3": "Find previous", delete: "Delete", backspace: "Backspace",
    pagedown: "Page down", pageup: "Page up", scrolldown: "Scroll down", scrollup: "Scroll up",
    "swap(insert_mode)": "Back to insert", "swap(normal_mode)": "Back to normal", "swap(visual_mode)": "Visual mode",
    "oneshot(c_normal_mode)": "Change operator", "oneshot(d_normal_mode)": "Delete operator", "oneshot(y_normal_mode)": "Yank operator",
    "oneshot(g_mode)": "g prefix", "swap(vim_shift)": "Shift layer", "repeat()": "Repeat last action",
    "swapm(insert_mode, right)": "Insert after cursor", "swapm(insert_mode, end)": "Insert at line end",
    "swapm(insert_mode, macro(end enter))": "Open line below", "swapm(insert_mode, macro(end up enter))": "Open line above",
    "macro(C-right C-right C-left)": "Next word start", "macro(right C-right left)": "Word end",
    "macro(C-S-end S-delete)": "Delete to end of text", "macro(C-S-end C-insert)": "Copy to end of text",
    "macro(home enter up S-insert)": "Paste above",
    "macro(C-right C-S-left 20ms C-insert 10ms C-f 20ms S-insert)": "Search word under cursor"
};

// Sections in file order as { name, entries: [{ key, value }] }; comments and the [ids] lines carry no remap.
function parse(text) {
    const sections = [];
    let current = null;
    for (const raw of text.split("\n")) {
        const line = raw.trim();
        if (line === "" || line[0] === "#") continue;
        const header = line.match(/^\[(.+)\]$/);
        if (header) {
            current = { name: header[1], entries: [] };
            sections.push(current);
            continue;
        }
        const entry = line.match(/^(\S+?)\s*=\s*(.*)$/);
        if (current && entry) current.entries.push({ key: entry[1], value: entry[2].trim() });
    }
    return sections;
}

function section(sections, name) {
    return sections.find(s => s.name === name);
}

function key_name(key) {
    if (KEY_NAMES[key]) return KEY_NAMES[key];
    return key.length === 1 ? key.toUpperCase() : key;
}

// The layer a hold action names, as words: modifier layers read as that modifier, the vim layer as such.
function layer_name(sections, layer) {
    const modifier = sections.map(s => s.name.split(":")).find(p => p[0] === layer && p.length === 2);
    if (modifier && MODIFIER_NAMES[modifier[1]]) return MODIFIER_NAMES[modifier[1]];
    if (layer === "normal_mode") return "vim layer";
    return layer.replace(/_/g, " ") + " layer";
}

// The plain-words form of a [main] right-hand side: overload(layer, key), a bare key, or the raw text.
function describe_remap(sections, value) {
    const overload = value.match(/^overload\w*\(\s*([\w:]+)\s*,\s*([^,()]+?)\s*(?:,[^()]*)?\)$/);
    if (overload) return "Tap " + key_name(overload[2]) + " · hold " + layer_name(sections, overload[1]);
    if (/^[\w-]+$/.test(value)) return "Acts as " + key_name(value);
    return value;
}

// One entry per [main] remap: { key, label, value, layer } where layer is the held layer's section name, if any.
function remaps(sections) {
    const main = section(sections, "main");
    if (!main) return [];
    return main.entries.map(e => {
        const overload = e.value.match(/^overload\w*\(\s*([\w:]+)\s*,/);
        return { key: e.key, label: key_name(e.key), value: describe_remap(sections, e.value), layer: overload ? overload[1] : "" };
    });
}

function describe_action(value) {
    return ACTION_NAMES[value] !== undefined ? ACTION_NAMES[value] : value;
}

// "key -> action" lines for a layer and its modifier variants (name+shift, name+control), noop keys skipped.
// Vim notation inside the layer: h and H are different keys, so letters keep their case and Shift+ is only spelled out for the rest.
function layer_key(key, prefix) {
    if (/^[a-z]$/.test(key)) return prefix === "Shift+" ? key.toUpperCase() : prefix + key;
    return prefix + key_name(key);
}

function layer_lines(sections, layer) {
    const variants = [[layer, ""], [layer + "+shift", "Shift+"], [layer + "+control", "Ctrl+"]];
    const lines = [];
    for (const [name, prefix] of variants) {
        const s = section(sections, name);
        if (!s) continue;
        for (const e of s.entries) {
            if (e.value === "noop") continue;
            lines.push(layer_key(e.key, prefix) + " → " + describe_action(e.value));
        }
    }
    return lines;
}
