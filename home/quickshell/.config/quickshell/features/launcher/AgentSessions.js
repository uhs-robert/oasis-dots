.pragma library

// Pure helpers for AgentsProvider, kept here so node can test them.

var state_labels = { running: "working", waiting: "waiting", idle: "idle", done: "idle" };

function shorten_home(path, home) {
    if (path === home) return "~";
    return path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
}

// Rows from `keeptabs-pick --json`; bad JSON or a non-list gives no rows.
function parse_sessions(text, home) {
    var sessions;
    try {
        sessions = JSON.parse(text);
    } catch (e) {
        return [];
    }
    if (!Array.isArray(sessions)) return [];
    return sessions.filter(function (s) { return s && s.id; }).map(function (s) {
        var cwd = s.cwd || "";
        var state = state_labels[s.state] || s.state || "";
        return {
            id: String(s.id),
            label: s.title || s.agent || "session",
            description: [s.agent || "", state, shorten_home(cwd, home)].filter(function (x) { return x !== ""; }).join(" · "),
            icon: "utilities-terminal",
            keywords: [s.agent || "", state, cwd],
            tmux_socket: s.tmux_socket || "",
            tmux_pane: s.tmux_pane || ""
        };
    });
}

// A session recorded without a socket lives on tmux's default server, so `-S` is left out rather than passed empty.
function capture_argv(entry) {
    var socket = entry.tmux_socket ? ["-S", entry.tmux_socket] : [];
    return ["tmux"].concat(socket, ["capture-pane", "-p", "-e", "-t", entry.tmux_pane]);
}
