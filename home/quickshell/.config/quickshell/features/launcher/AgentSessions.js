.pragma library

// Pure helpers for AgentsProvider, kept here so node can test them.

var state_labels = { running: "working", waiting: "waiting", idle: "idle", done: "done" };

// How a state's badge is drawn: the theme colour it takes and whether it is filled. Waiting needs the owner and done has
// news, so those two are filled; working and idle stay outlined. An unknown state draws like idle.
var badge_styles = {
    working: { tone: "primary", filled: false },
    done: { tone: "ok", filled: true },
    waiting: { tone: "warning", filled: true },
    idle: { tone: "dim", filled: false }
};

function badge_style(state) {
    return badge_styles[state] || badge_styles.idle;
}

function shorten_home(path, home) {
    if (path === home) return "~";
    return path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
}

// { pct, used, window } from a session's context fields, or null when it has none (keeptabs leaves them out until it
// has read the session's transcript). The percent is keeptabs' own, worked out here only when it is missing.
function parse_context(s) {
    if (s.context_used == null || s.context_window == null) return null;
    var used = Number(s.context_used);
    var window = Number(s.context_window);
    if (!isFinite(used) || !isFinite(window) || used < 0 || window <= 0) return null;
    var pct = s.context_pct == null ? NaN : Number(s.context_pct);
    if (!isFinite(pct)) pct = Math.round(used / window * 100);
    return { pct: pct, used: used, window: window };
}

// The theme colour a context bar takes at `pct` percent full.
function context_tone(pct) {
    return pct >= 80 ? "error" : pct >= 50 ? "warning" : "ok";
}

// A token count the way the bar's label writes it: 950, 1.5k, 118k, 1M.
function short_tokens(n) {
    if (n < 1000) return String(Math.round(n));
    if (n < 10000) return String(Math.round(n / 100) / 10) + "k";
    if (n < 1000000) return Math.round(n / 1000) + "k";
    return String(Math.round(n / 100000) / 10) + "M";
}

function context_label(context) {
    return short_tokens(context.used) + " / " + short_tokens(context.window);
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
            agent: s.agent || "",
            state: state,
            cwd_short: shorten_home(cwd, home),
            description: [s.agent || "", state, shorten_home(cwd, home)].filter(function (x) { return x !== ""; }).join(" · "),
            icon: "utilities-terminal",
            keywords: [s.agent || "", state, cwd],
            tmux_socket: s.tmux_socket || "",
            tmux_pane: s.tmux_pane || "",
            pid: /^[1-9]\d*$/.test(String(s.pid)) ? String(s.pid) : "",
            context: parse_context(s)
        };
    });
}

function socket_args(entry) {
    return entry.tmux_socket ? ["-S", entry.tmux_socket] : [];
}

// A session outside tmux is read from its kitty window: kitty puts the window's remote-control socket and id in the
// environment of everything it starts, so the agent's own environment names them. Sets `to` and `win`; fails when the
// process is gone or its terminal is not a kitty with `listen_on` set.
var kitty_window_fn = "kitty_window() { "
    + "e=$(tr '\\0' '\\n' 2>/dev/null < \"/proc/$1/environ\") || return 1; "
    + "to=$(printf '%s\\n' \"$e\" | sed -n 's/^KITTY_LISTEN_ON=//p'); "
    + "win=$(printf '%s\\n' \"$e\" | sed -n 's/^KITTY_WINDOW_ID=//p'); "
    + "[ -n \"$to\" ] && [ -n \"$win\" ]; }; ";

// A session recorded without a socket lives on tmux's default server, so `-S` is left out rather than passed empty.
// The pane's width comes first, from the same tmux call, so the preview can fit its font to the whole width; a kitty
// window's comes from its tty, which is the agent's stdin.
function capture_argv(entry) {
    if (entry.tmux_pane) return ["tmux"].concat(socket_args(entry), ["display-message", "-p", "-t", entry.tmux_pane, "#{pane_width}", ";", "capture-pane", "-p", "-e", "-t", entry.tmux_pane]);
    var script = kitty_window_fn + "kitty_window \"$1\" || exit 1; "
        + "cols=$(stty size < \"/proc/$1/fd/0\" 2>/dev/null | cut -d' ' -f2); "
        + "printf '%s\\n' \"${cols:-0}\"; "
        + "exec kitten @ --to \"$to\" get-text --match \"id:$win\" --extent screen --add-wrap-markers --ansi";
    return ["sh", "-c", script, "sh", entry.pid || ""];
}

// kitty joins a soft-wrapped row to the next unless asked for wrap markers, which it writes as "\r"; each marks a row
// break, so it becomes one here (tmux output has none).
function rows_of(out) {
    return out.replace(/\r\n?/g, "\n");
}

// { width, text } from capture_argv's output; width is 0 when the first line is not a number.
function split_capture(out) {
    out = rows_of(out);
    var nl = out.indexOf("\n");
    var head = nl >= 0 ? out.slice(0, nl) : out;
    if (!/^\d+$/.test(head)) return { width: 0, text: out };
    return { width: parseInt(head, 10), text: nl >= 0 ? out.slice(nl + 1) : "" };
}

// Spaces, box drawing, blocks and prompt marks: the frame of a TUI's input box, which says nothing on its own.
var frame_edge = /^[\s─-▟|>›❯]+|[\s─-▟|]+$/g;

// Bullets agents put before an output line: Claude Code's ⏺, codex's •.
var output_bullet = /^[⏺•●]\s+/;

// Where an agent's input area starts: the top edge of Claude Code's input box (or a permission dialog's), else codex's
// › prompt (▌ in older versions). The prompt and the status footer under it are not output.
var input_start = /^\s*(?:[╭┌]|[›❯▌](?:\s|$))/;

function output_end(lines) {
    for (var i = lines.length - 1; i >= 0; i--) {
        if (input_start.test(lines[i])) return i;
    }
    return lines.length;
}

// The last output line of a plain capture above the agent's input area that has a letter or digit in it, its frame and
// bullet trimmed off and its column padding squeezed to two spaces so a card shows the words; "" when there is none.
function last_line(text) {
    var lines = text.split("\n");
    for (var i = output_end(lines) - 1; i >= 0; i--) {
        var line = lines[i].replace(frame_edge, "").replace(output_bullet, "").replace(/\s{3,}/g, "  ");
        if (/[0-9A-Za-zÀ-ɏ]/.test(line)) return line;
    }
    return "";
}

// One process for every session's plain capture, each headed by a \x1e line naming its id; a pane or window that is gone prints nothing.
function tails_argv(entries) {
    var script = kitty_window_fn + "while [ $# -ge 4 ]; do printf '\\036%s\\n' \"$1\"; "
        + "if [ -n \"$3\" ]; then if [ -n \"$2\" ]; then tmux -S \"$2\" capture-pane -p -t \"$3\"; else tmux capture-pane -p -t \"$3\"; fi 2>/dev/null; "
        + "elif [ -n \"$4\" ] && kitty_window \"$4\"; then kitten @ --to \"$to\" get-text --match \"id:$win\" --extent screen --add-wrap-markers 2>/dev/null; fi; "
        + "shift 4; done";
    var args = ["sh", "-c", script, "sh"];
    for (var i = 0; i < entries.length; i++) args.push(entries[i].id, entries[i].tmux_socket || "", entries[i].tmux_pane || "", entries[i].pid || "");
    return args;
}

// id -> last_line of its capture, from tails_argv's output.
function parse_tails(out) {
    out = rows_of(out);
    var tails = {};
    var chunks = out.split("\x1e");
    for (var i = 1; i < chunks.length; i++) {
        var nl = chunks[i].indexOf("\n");
        var id = nl >= 0 ? chunks[i].slice(0, nl) : chunks[i];
        if (id !== "") tails[id] = last_line(nl >= 0 ? chunks[i].slice(nl + 1) : "");
    }
    return tails;
}
