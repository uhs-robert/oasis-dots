.pragma library

// The DesertFox state file (host-written, version 1): its validation and the which-key mapping, kept pure so a node
// test can run them. The shape is the hand-off contract with the DesertFox display host.

var supported_version = 1;

// A file this reader does not know is the same as no file: nothing shows.
var empty = {
    valid: false,
    host_pid: 0,
    host_start: "",
    mode_id: "",
    mode_label: "",
    whichkey_seq: 0,
    whichkey_title: "",
    whichkey_items: []
};

function validate(raw) {
    if (!raw || raw.version !== supported_version) return Object.assign({}, empty);
    const host = raw.host || {};
    const mode = raw.mode || {};
    const panel = raw.whichkey;
    const has_panel = !!panel && typeof panel === "object" && Array.isArray(panel.rows);
    return {
        valid: true,
        host_pid: Number(host.pid) || 0,
        host_start: String(host.start || ""),
        mode_id: String(mode.id || ""),
        mode_label: String(mode.label || ""),
        whichkey_seq: has_panel ? Number(panel.seq) || 0 : 0,
        whichkey_title: has_panel && Array.isArray(panel.title) ? panel.title.join(" ") : "",
        whichkey_items: has_panel ? panel.rows.map(item_of) : []
    };
}

// A row's `more` marks a group, drawn as a filled key cap.
function item_of(row) {
    return { key: String(row.keys || ""), desc: String(row.command || row.description || ""), group: row.more === true };
}

// What WhichKey.qml takes. Position, columns and footer are its own defaults, not in the file.
function payload_of(values) {
    return { title: values.whichkey_title, items: values.whichkey_items };
}

// Identity of the panel on screen: a new host restarting its counter at the same number is still a new panel.
function panel_key(values) {
    return values.host_start + ":" + values.whichkey_seq;
}

function is_firefox_class(cls) {
    const lower = String(cls || "").toLowerCase();
    return lower.indexOf("firefox") === 0 || lower === "org.mozilla.firefox";
}
