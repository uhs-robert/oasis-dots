.pragma library

// What the overview shows, as the snapshot voxcmd reads (voxcmd/overview.json in the runtime dir). The shape is documented in
// the Quickshell README; Overview.qml writes it and the voxcmd Overview integration reads it.

const columns_words = { 2: ["left", "right"], 3: ["left", "middle", "right"] };
const rows_words = { 2: ["top", "bottom"], 3: ["top", "middle", "bottom"] };

// Groups that overlap along one axis share a cluster; clusters are in order along it.
function clusters(groups, start, size) {
    const order = groups.map((g, i) => i).sort((a, b) => groups[a][start] - groups[b][start]);
    const out = [];
    let end = -Infinity;
    for (const i of order) {
        const g = groups[i];
        if (out.length === 0 || g[start] >= end) {
            out.push([i]);
            end = g[start] + g[size];
        } else {
            out[out.length - 1].push(i);
            end = Math.max(end, g[start] + g[size]);
        }
    }
    return out;
}

// A word per cluster: all of them for two or three, only the ends for more.
function cluster_words(list, words) {
    const out = {};
    let named = words[list.length];
    if (!named && list.length > 3) named = [words[3][0], ...Array(list.length - 2).fill(""), words[3][2]];
    if (!named) return out;
    list.forEach((members, k) => members.forEach(i => out[i] = named[k]));
    return out;
}

// Groups in rows, top to bottom. A group joins the row while its top is above the bottom of every group in it (the row's
// lowest bottom edge), so a tall neighbour sharing the top edge stays in the row. A group starting at or below the shortest
// member's bottom starts a new row, as a laptop set below a row of monitors does.
function rows(groups) {
    const order = groups.map((g, i) => i).sort((a, b) => groups[a].y - groups[b].y || groups[a].h - groups[b].h || a - b);
    const out = [];
    let bottom = Infinity;
    for (const i of order) {
        const g = groups[i];
        if (out.length > 0 && g.y < bottom) {
            out[out.length - 1].push(i);
            bottom = Math.min(bottom, g.y + g.h);
        } else {
            out.push([i]);
            bottom = g.y + g.h;
        }
    }
    return out;
}

// { horizontal, vertical } per group: "top", "middle", "bottom" by row, then "left", "middle", "right" within the row, each
// empty while there is only one row or one column to tell apart. Monitors side by side have no vertical word, and a laptop
// below a row of monitors is just "bottom".
function positions(groups) {
    const row_list = rows(groups);
    const vertical = cluster_words(row_list, rows_words);
    const horizontal = {};
    for (const row of row_list) {
        const columns = clusters(row.map(i => groups[i]), "x", "w").map(members => members.map(k => row[k]));
        Object.assign(horizontal, cluster_words(columns, columns_words));
    }
    return groups.map((g, i) => ({ horizontal: horizontal[i] || "", vertical: vertical[i] || "" }));
}

// Group indexes in monitor slot order (the monitor SUPER+CTRL+n focuses), unslotted ones after in Hyprland's order.
function slot_order(groups, slots) {
    const slot_of = i => {
        const at = slots.indexOf(groups[i].name);
        return at < 0 ? Infinity : at;
    };
    return groups.map((g, i) => i).sort((a, b) => slot_of(a) - slot_of(b) || a - b);
}

function reading_order(windows) {
    return windows.slice().sort((a, b) => a.ry - b.ry || a.rx - b.rx);
}

// input: { groups, tiles, marks, special, slots, nav_order }. Windows are numbered 1.. by monitor slot, then workspace
// order, then reading order inside the workspace. A workspace's n is its id (its place in nav_order for special ones),
// the number said in "workspace three" and typed as digits.
function snapshot(input) {
    const marks = input.marks || [];
    const slots = input.slots || [];
    const places = positions(input.groups);
    const order = slot_order(input.groups, slots);
    const items = [];
    let window_n = 0;
    for (const gi of order) {
        const g = input.groups[gi];
        for (const ti of g.tiles) {
            const tile = input.tiles[ti];
            if (tile.is_new) continue;
            const ref = tile.key.startsWith("sp:") ? tile.key : String(tile.id);
            const n = input.special ? input.nav_order.indexOf(ti) + 1 : tile.id;
            items.push({ n: n, kind: "workspace", id: ref, label: tile.name, workspace: ref, monitor: g.name, marked: false, windows: tile.windows.length, shown: !!tile.shown_on_monitor });
            for (const w of reading_order(tile.windows)) {
                window_n++;
                items.push({ n: window_n, kind: "window", id: w.address, label: w.label + (w.title ? ": " + w.title : ""), workspace: ref, monitor: g.name, marked: marks.indexOf(w.address) >= 0 });
            }
        }
    }
    const monitors = order.map(gi => ({ id: input.groups[gi].name, slot: slots.indexOf(input.groups[gi].name) + 1, horizontal: places[gi].horizontal, vertical: places[gi].vertical, focused: !!input.groups[gi].focused }));
    return { version: 1, open: true, special: !!input.special, marks: marks, monitors: monitors, items: items };
}

// The number a window shows while voice drives the overview: address -> n, in the snapshot's order.
function window_numbers(snap) {
    const out = {};
    for (const item of snap.items || []) if (item.kind === "window") out[item.id] = item.n;
    return out;
}
