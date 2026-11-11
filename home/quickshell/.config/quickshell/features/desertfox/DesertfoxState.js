.pragma library

// The DesertFox state file (host-written, version 2): its validation, kept pure so a node test can run it. The shape is
// the hand-off contract with the DesertFox bridge host (host/README.md in DesertFox).

var supported_version = 2;

// A file this reader does not know is the same as no file: nothing shows.
var empty = {
    valid: false,
    host_pid: 0,
    host_start: "",
    mode_id: "",
    mode_label: ""
};

function validate(raw) {
    if (!raw || raw.version !== supported_version) return Object.assign({}, empty);
    const host = raw.host || {};
    const mode = raw.mode || {};
    return {
        valid: true,
        host_pid: Number(host.pid) || 0,
        host_start: String(host.start || ""),
        mode_id: String(mode.id || ""),
        mode_label: String(mode.label || "")
    };
}

// Modes that draw their own surface (the hint labels, the command line), where a chip would sit on top of it.
var own_surface_modes = ["hint", "cmdline"];

function hides_chip(mode_id) {
    return own_surface_modes.indexOf(mode_id) >= 0;
}

// Firefox builds name their window class `firefox`, `firefox-esr`, `firefox-developer-edition` or, packaged by
// Flatpak and others, `org.mozilla.firefox`.
function is_firefox_class(cls) {
    const lower = String(cls || "").toLowerCase();
    return lower.indexOf("firefox") === 0 || lower.indexOf("org.mozilla.firefox") === 0;
}
