// home/quickshell/.config/quickshell/services/SessionJson.js
.pragma library

// Pure helpers for the saved sessions document: { version, sessions: { <name>: { windows: [AppEntry] } }, ...unknown }.
// Every function returns a new document and leaves its argument alone.

// Fields in the order they are written, so an entry reads the same every save.
var field_order = ["monitor", "ws", "special", "cmd", "class", "title", "size", "pos", "delay", "float", "guessed"];

function empty_document() {
    return { version: 1, sessions: {} };
}

function is_object(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
}

// A parsed file as a usable document; anything that is not an object with a sessions object is rejected by the caller.
function valid_document(data) {
    return is_object(data) && (data.sessions === undefined || is_object(data.sessions));
}

function with_sessions(doc, sessions) {
    const next = Object.assign({}, doc, { sessions: sessions });
    if (next.version === undefined) next.version = 1;
    return next;
}

function window_list(session) {
    return is_object(session) && Array.isArray(session.windows) ? session.windows.filter(is_object) : [];
}

// Saved sessions first in file order, then Lua sessions not shadowed by a saved one, by name.
function merge(doc, lua_sessions) {
    const out = [];
    const saved = is_object(doc.sessions) ? doc.sessions : {};
    for (const name of Object.keys(saved)) {
        out.push({ name: name, source: "saved", read_only: false, sequential: true, windows: window_list(saved[name]) });
    }
    for (const name of Object.keys(lua_sessions).sort()) {
        if (name in saved) continue;
        const info = lua_sessions[name];
        // lib/json encodes an empty array as an object, so a non-array reads as no windows.
        out.push({ name: name, source: "lua", read_only: true, sequential: !!info.sequential, windows: Array.isArray(info.windows) ? info.windows.filter(is_object) : [] });
    }
    return out;
}

// "Session N" with the lowest N not in names.
function default_name(names) {
    let n = 1;
    while (names.indexOf("Session " + n) >= 0) n++;
    return "Session " + n;
}

// Known fields in field_order, then unknown ones as they came, minus undefined and null values.
function normalize_entry(entry) {
    const out = {};
    for (const key of field_order) {
        if (entry[key] !== undefined && entry[key] !== null) out[key] = entry[key];
    }
    for (const key of Object.keys(entry)) {
        if (!(key in out) && entry[key] !== undefined && entry[key] !== null && field_order.indexOf(key) < 0) out[key] = entry[key];
    }
    return out;
}

function set_session(doc, name, windows) {
    const sessions = Object.assign({}, doc.sessions);
    const previous = is_object(sessions[name]) ? sessions[name] : {};
    sessions[name] = Object.assign({}, previous, { windows: windows.map(normalize_entry) });
    return with_sessions(doc, sessions);
}

function remove_session(doc, name) {
    const sessions = Object.assign({}, doc.sessions);
    delete sessions[name];
    return with_sessions(doc, sessions);
}

// Keeps the session in its place in the file.
function rename_session(doc, old_name, new_name) {
    const sessions = {};
    for (const name of Object.keys(doc.sessions)) {
        sessions[name === old_name ? new_name : name] = doc.sessions[name];
    }
    return with_sessions(doc, sessions);
}

// Merges `fields` into window `index`; a null value removes the field.
function patch_window(doc, name, index, fields) {
    const windows = window_list(doc.sessions[name]).map((w, i) => i === index ? Object.assign({}, w, fields) : w);
    return set_session(doc, name, windows);
}

function drop_window(doc, name, index) {
    return set_session(doc, name, window_list(doc.sessions[name]).filter((w, i) => i !== index));
}

function is_scalar(value) {
    return value === null || typeof value !== "object";
}

function is_flat(value) {
    if (Array.isArray(value)) return value.every(is_scalar);
    return is_object(value) && Object.keys(value).every(k => is_scalar(value[k]) || (Array.isArray(value[k]) && value[k].every(is_scalar)));
}

function inline(value) {
    if (Array.isArray(value)) return "[" + value.map(inline).join(", ") + "]";
    if (is_object(value)) {
        const keys = Object.keys(value);
        return keys.length === 0 ? "{}" : "{ " + keys.map(k => JSON.stringify(k) + ": " + inline(value[k])).join(", ") + " }";
    }
    return JSON.stringify(value);
}

// Two-space indent, with a window entry (or any object of plain values) on one line so the file diffs and hand-edits well.
function encode_value(value, depth) {
    if (is_scalar(value) || is_flat(value)) return inline(value);
    const pad = "  ".repeat(depth + 1);
    const close = "  ".repeat(depth);
    if (Array.isArray(value)) return "[\n" + value.map(v => pad + encode_value(v, depth + 1)).join(",\n") + "\n" + close + "]";
    return "{\n" + Object.keys(value).map(k => pad + JSON.stringify(k) + ": " + encode_value(value[k], depth + 1)).join(",\n") + "\n" + close + "}";
}

function encode(doc) {
    const sessions = {};
    for (const name of Object.keys(doc.sessions)) {
        const session = doc.sessions[name];
        sessions[name] = is_object(session) && Array.isArray(session.windows) ? Object.assign({}, session, { windows: session.windows.map(w => is_object(w) ? normalize_entry(w) : w) }) : session;
    }
    return encode_value(Object.assign({}, doc, { sessions: sessions }), 0) + "\n";
}
