.pragma library

// The tmux picker's reading of tmux (TmuxProvider.qml), kept here so node can test it: the list and capture commands,
// one item per window with its panes, the session headers, both sorts, the session filter, pane cycling, which client
// to follow and which terminal shows a session.

var sep = "\u001f";

var fmt_session = "S" + sep + ["#{session_id}", "#{session_name}", "#{session_attached}"].join(sep);
var fmt_window = "W" + sep + ["#{session_id}", "#{window_id}", "#{window_index}", "#{window_name}", "#{window_active}", "#{window_activity}"].join(sep);
var fmt_pane = "P" + sep + ["#{window_id}", "#{pane_id}", "#{pane_left}", "#{pane_top}", "#{pane_active}", "#{pane_current_command}", "#{pane_current_path}"].join(sep);
var fmt_client = "C" + sep + ["#{client_name}", "#{session_id}", "#{client_activity}"].join(sep);

// Printed instead of the list when there is no tmux binary; no server prints nothing at all.
var missing_marker = "NO-TMUX";

// Through sh so a missing tmux is a line the picker reads rather than a process that never starts.
function list_argv() {
    var args = ["list-sessions", "-F", fmt_session, ";", "list-windows", "-a", "-F", fmt_window, ";", "list-panes", "-a", "-F", fmt_pane, ";", "list-clients", "-F", fmt_client];
    return ["sh", "-c", "command -v tmux >/dev/null 2>&1 || { echo " + missing_marker + "; exit 0; }; exec tmux \"$@\" 2>/dev/null", "sh"].concat(args);
}

// The pane's width first, as AgentSessions.capture_argv prints it, so AgentSessions.split_capture reads both.
function capture_argv(pane_id) {
    return ["tmux", "display-message", "-p", "-t", pane_id, "#{pane_width}", ";", "capture-pane", "-p", "-e", "-t", pane_id];
}

// One plain capture of every pane in pane_ids, each headed by a marker line naming it; a gone pane prints nothing.
function tails_argv(pane_ids) {
    return ["sh", "-c", "for p; do printf '\\037PANE\\037%s\\n' \"$p\"; tmux capture-pane -p -t \"$p\" 2>/dev/null; done", "sh"].concat(pane_ids);
}

// pane_id -> its last `count` lines with any text, from tails_argv's output.
function parse_tails(text, count) {
    var out = {};
    var marker = sep + "PANE" + sep;
    var id = "";
    var lines = [];
    var flush = function () {
        if (id === "") return;
        var kept = lines.filter(function (l) { return l.trim() !== ""; });
        out[id] = kept.slice(Math.max(0, kept.length - count)).join("\n");
    };
    var all = String(text || "").split("\n");
    for (var i = 0; i < all.length; i++) {
        if (all[i].indexOf(marker) === 0) {
            flush();
            id = all[i].slice(marker.length);
            lines = [];
        } else {
            lines.push(all[i]);
        }
    }
    flush();
    return out;
}

function short_path(path, home) {
    return home !== "" && (path === home || path.indexOf(home + "/") === 0) ? "~" + path.slice(home.length) : path;
}

function int_of(text) {
    return parseInt(text, 10) || 0;
}

// Top to bottom, then left to right, the order `[` and `]` step through.
function reading_order(panes) {
    return panes.slice().sort(function (a, b) {
        return a.top - b.top || a.left - b.left;
    });
}

// { state, sessions, items, clients } from list_argv's output. state is "ok", "missing" (no tmux) or "none" (no
// server, or one with no sessions). Items are one per window, sessions in tmux's order and windows by index.
function parse_list(text, home) {
    var lines = String(text || "").split("\n");
    if (lines[0] === missing_marker) return { state: "missing", sessions: [], items: [], clients: [] };
    var sessions = [];
    var windows = [];
    var panes = [];
    var clients = [];
    for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split(sep);
        if (f[0] === "S" && f.length >= 4) sessions.push({ id: f[1], name: f[2], attached: int_of(f[3]) > 0 });
        else if (f[0] === "W" && f.length >= 7) windows.push({ session_id: f[1], id: f[2], index: int_of(f[3]), name: f[4], active: f[5] === "1", activity: int_of(f[6]) });
        else if (f[0] === "P" && f.length >= 8) panes.push({ window_id: f[1], pane_id: f[2], left: int_of(f[3]), top: int_of(f[4]), active: f[5] === "1", cmd: f[6], path: f[7], short_path: short_path(f[7], home || "") });
        else if (f[0] === "C" && f.length >= 4) clients.push({ name: f[1], session_id: f[2], activity: int_of(f[3]) });
    }
    var items = [];
    var shown_sessions = [];
    for (var s = 0; s < sessions.length; s++) {
        var session = sessions[s];
        var own = windows.filter(function (w) { return w.session_id === session.id; }).sort(function (a, b) { return a.index - b.index; });
        if (own.length === 0) continue;
        session.number = shown_sessions.length + 1;
        session.window_count = own.length;
        shown_sessions.push(session);
        for (var w = 0; w < own.length; w++) items.push(window_item(own[w], session, reading_order(panes.filter(function (p) { return p.window_id === own[w].id; }))));
    }
    return { state: shown_sessions.length > 0 ? "ok" : "none", sessions: shown_sessions, items: items, clients: clients };
}

function window_item(win, session, panes) {
    var lead = panes.filter(function (p) { return p.active; })[0] || panes[0] || null;
    var name = win.name.trim();
    return {
        id: win.id,
        label: name,
        // Searched along with the label; the row draws its own text.
        description: session.name,
        keywords: panes.map(function (p) { return p.cmd; }).concat(panes.map(function (p) { return p.short_path; })),
        session_id: session.id,
        session_name: session.name,
        session_number: session.number,
        index: win.index,
        active: win.active,
        activity: win.activity,
        panes: panes,
        active_pane: lead ? lead.pane_id : "",
        cmd: lead ? lead.cmd : "",
        short_path: lead ? lead.short_path : ""
    };
}

// `s` flips the order: "sessions" heads each session's windows by index, "recent" is one list by last activity.
var sorts = ["sessions", "recent"];
var sort_labels = { sessions: "SESSIONS", recent: "RECENT" };

function sort_of(name) {
    return sorts.indexOf(name) >= 0 ? name : sorts[0];
}

function cycled_sort(sort) {
    return sorts[(sorts.indexOf(sort_of(sort)) + 1) % sorts.length];
}

function recent_first(items) {
    return items.slice().sort(function (a, b) {
        return b.activity - a.activity || a.session_number - b.session_number || a.index - b.index;
    });
}

// The picker's items: the windows the session filter keeps, in the sort's order.
function arranged(items, sort, filter) {
    var kept = items.filter(function (item) { return kept_by_filter(item, filter); });
    return sort_of(sort) === "recent" ? recent_first(kept) : kept;
}

// A session's header over the windows of it that show: "SESSION 1 · work · 3 WINDOWS · ATTACHED".
function group_title(session_id, shown_count, sessions) {
    var session = sessions.filter(function (s) { return s.id === session_id; })[0];
    if (!session) return "";
    var parts = ["SESSION " + session.number, session.name, shown_count + (shown_count === 1 ? " WINDOW" : " WINDOWS")];
    if (session.attached) parts.push("ATTACHED");
    return parts.join(" · ");
}

// `f`: all, then each session in turn, then all again. A session that has gone also goes back to all.
function cycled_filter(filter, sessions) {
    var ids = sessions.map(function (s) { return s.id; });
    if (filter === "all") return ids.length > 0 ? ids[0] : "all";
    var i = ids.indexOf(filter);
    return i >= 0 && i + 1 < ids.length ? ids[i + 1] : "all";
}

function kept_by_filter(item, filter) {
    return filter === "all" || item.session_id === filter;
}

function shown_filter(filter, sessions) {
    return sessions.some(function (s) { return s.id === filter; }) ? filter : "all";
}

// The search bar corner: "ALL", or the session's place among them ("SESSION 2/3").
function filter_label(filter, sessions) {
    for (var i = 0; i < sessions.length; i++) if (sessions[i].id === filter) return "SESSION " + (i + 1) + "/" + sessions.length;
    return "ALL";
}

// The pane `[` or `]` lands on, from the one shown now (the window's active pane when none was chosen).
function cycled_pane(item, current, delta) {
    var panes = item.panes;
    if (panes.length === 0) return "";
    var at = 0;
    for (var i = 0; i < panes.length; i++) if (panes[i].pane_id === current) at = i;
    return panes[(at + delta + panes.length) % panes.length].pane_id;
}

// The pane a window shows: the chosen one while it still exists, else the window's active pane.
function pane_of(item, chosen) {
    if (!item) return null;
    var want = chosen || item.active_pane;
    return item.panes.filter(function (p) { return p.pane_id === want; })[0] || item.panes.filter(function (p) { return p.pane_id === item.active_pane; })[0] || null;
}

// "PANE 2/3 · nvim" for the preview corner.
function pane_label(item, pane) {
    if (!item || !pane) return "";
    return "PANE " + (item.panes.indexOf(pane) + 1) + "/" + item.panes.length + " · " + pane.cmd;
}

// The most recently active client attached to a session.
function client_of(clients, session_id) {
    return latest_client(clients.filter(function (c) { return c.session_id === session_id; }));
}

function latest_client(clients) {
    return clients.slice().sort(function (a, b) { return b.activity - a.activity; })[0] || null;
}

// Where the picker opens: the window the most recent client shows, which is its session's active window.
function initial_index(items, clients) {
    var latest = latest_client(clients);
    if (!latest) return 0;
    for (var i = 0; i < items.length; i++) if (items[i].session_id === latest.session_id && items[i].active) return i;
    return 0;
}

// Hyprland titles are the session name, with a "Tmux " prefix when a tmuxifier layout set the title string, and then
// the active program ("UpHill nvim").
// A longer name in session_names that also fits the title owns the window ("Dev tools nvim" is not session "Dev").
function title_matches(title, session_name, session_names) {
    var fits = function (name) {
        return [name, "Tmux " + name].some(function (t) { return title === t || title.indexOf(t + " ") === 0; });
    };
    return fits(session_name) && !(session_names || []).some(function (o) { return o.length > session_name.length && fits(o); });
}
