.pragma library

const sep = "\u001f";
// Terminal cells are about twice as tall as wide.
const cell_aspect = 0.5;
const per_row = 4;

const fmt_session = "S" + sep + ["#{session_id}", "#{session_name}", "#{session_attached}"].join(sep);
const fmt_window = "W" + sep + ["#{session_id}", "#{window_id}", "#{window_index}", "#{window_name}", "#{window_active}", "#{window_width}", "#{window_height}", "#{window_activity}"].join(sep);
const fmt_pane = "P" + sep + ["#{window_id}", "#{pane_id}", "#{pane_left}", "#{pane_top}", "#{pane_width}", "#{pane_height}", "#{pane_active}", "#{pane_current_command}", "#{pane_current_path}"].join(sep);
const fmt_client = "C" + sep + ["#{client_name}", "#{session_id}", "#{client_activity}"].join(sep);

function list_command() {
    return ["tmux", "list-sessions", "-F", fmt_session, ";", "list-windows", "-a", "-F", fmt_window, ";", "list-panes", "-a", "-F", fmt_pane, ";", "list-clients", "-F", fmt_client];
}

function capture_command(pane_ids) {
    return ["sh", "-c", "for p; do printf '\\037PANE\\037%s\\n' \"$p\"; tmux capture-pane -ep -t \"$p\"; done", "sh"].concat(pane_ids);
}

// Splits capture_command output into pane_id -> raw text.
function parse_captures(text) {
    const out = {};
    const marker = sep + "PANE" + sep;
    let id = "";
    let buf = [];
    const flush = () => {
        if (id !== "") out[id] = buf.join("\n");
    };
    for (const line of text.split("\n")) {
        if (line.startsWith(marker)) {
            flush();
            id = line.slice(marker.length);
            buf = [];
        } else {
            buf.push(line);
        }
    }
    flush();
    return out;
}

function group_geometry(index, aspect, row_end) {
    const row = Math.floor(index / per_row);
    const w = aspect * 1000;
    const x = index % per_row === 0 ? 0 : row_end[row] + 200;
    row_end[row] = x + w;
    return { x: x, y: row * 1200, w: w, h: 1000 };
}

// groups are sessions in list order, tiles their windows by index; client_of lists attached clients.
function parse_model(text) {
    const sessions = [];
    const windows = [];
    const panes = [];
    const clients = [];
    for (const line of text.split("\n")) {
        const f = line.split(sep);
        if (f[0] === "S" && f.length >= 4) sessions.push({ id: f[1], name: f[2], attached: parseInt(f[3], 10) || 0 });
        else if (f[0] === "W" && f.length >= 9) windows.push({ session_id: f[1], id: f[2], index: parseInt(f[3], 10), name: f[4], active: f[5] === "1", cols: Math.max(1, parseInt(f[6], 10) || 1), rows: Math.max(1, parseInt(f[7], 10) || 1), activity: parseInt(f[8], 10) || 0 });
        else if (f[0] === "P" && f.length >= 10) panes.push({ window_id: f[1], pane_id: f[2], left: parseInt(f[3], 10), top: parseInt(f[4], 10), cols: parseInt(f[5], 10), rows: parseInt(f[6], 10), active: f[7] === "1", cmd: f[8], path: f[9] });
        else if (f[0] === "C" && f.length >= 4) clients.push({ name: f[1], session_id: f[2], activity: parseInt(f[3], 10) || 0 });
    }
    const groups = [];
    const tiles = [];
    const row_end = {};
    for (const s of sessions) {
        const wins = windows.filter(w => w.session_id === s.id).sort((a, b) => a.index - b.index);
        if (wins.length === 0) continue;
        const lead = wins.find(w => w.active) || wins[0];
        const geo = group_geometry(groups.length, (lead.cols / lead.rows) * cell_aspect, row_end);
        const g = { key: s.id, id: s.id, name: s.name, attached: s.attached, x: geo.x, y: geo.y, w: geo.w, h: geo.h, tiles: [], active_tile: -1 };
        for (const w of wins) {
            const own = panes.filter(p => p.window_id === w.id).map(p => ({
                pane_id: p.pane_id,
                rx: p.left / w.cols,
                ry: p.top / w.rows,
                rw: p.cols / w.cols,
                rh: p.rows / w.rows,
                left: p.left,
                top: p.top,
                cols: p.cols,
                rows: p.rows,
                active: p.active,
                cmd: p.cmd,
                path: p.path
            }));
            const lead_pane = own.find(p => p.active) || own[0];
            if (w.active) g.active_tile = tiles.length;
            g.tiles.push(tiles.length);
            tiles.push({ key: s.id + ":" + w.id, id: w.id, index: w.index, name: w.name, group: groups.length, session_id: s.id, session_name: s.name, active: w.active, cols: w.cols, rows: w.rows, activity: w.activity, panes: own, cmd: lead_pane ? lead_pane.cmd : "" });
        }
        if (g.active_tile < 0) g.active_tile = g.tiles[0];
        groups.push(g);
    }
    return { groups: groups, tiles: tiles, clients: clients };
}

function short_path(path, home) {
    return home !== "" && (path === home || path.startsWith(home + "/")) ? "~" + path.slice(home.length) : path;
}

// One search entry per tile minus the skipped keys, most recently active window first.
function search_entries(tiles, home, skip) {
    const out = [];
    for (const t of tiles) {
        if (skip[t.key]) continue;
        const lead = t.panes.find(p => p.active) || t.panes[0];
        const name = t.name.trim();
        const cmds = t.panes.map(p => p.cmd);
        const paths = t.panes.map(p => short_path(p.path, home));
        out.push({
            key: t.key,
            activity: t.activity,
            label: name,
            title: lead ? (lead.cmd + " " + short_path(lead.path, home)).trim() : name,
            place: t.session_name + ":" + t.index,
            description: name + " · " + paths.join(" "),
            keywords: cmds.concat([t.session_name])
        });
    }
    out.sort((a, b) => b.activity - a.activity);
    out.forEach((e, i) => { e.recency = i; });
    return out;
}

// The most recently active client attached to a session.
function client_of(clients, session_id) {
    return clients.filter(c => c.session_id === session_id).sort((a, b) => b.activity - a.activity)[0] || null;
}

function latest_client(clients) {
    return clients.slice().sort((a, b) => b.activity - a.activity)[0] || null;
}

// Hyprland titles are the session name, with a "Tmux " prefix when a tmuxifier layout set the title string.
function title_matches(title, session_name) {
    for (const base of [session_name, "Tmux " + session_name]) {
        if (title === base || title.startsWith(base + " ")) return true;
    }
    return false;
}
