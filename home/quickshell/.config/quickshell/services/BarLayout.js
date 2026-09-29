.pragma library

var sides = ["left", "center", "right"];
// Keep in step with Bar.module_map.
var known = ["start", "workspaces", "clock", "tray", "volume", "battery", "bluetooth", "system", "network", "weather", "keeptabs", "updates", "voxtype", "recording", "notifications", "media"];

function is_object(v) {
    return typeof v === "object" && v !== null && !Array.isArray(v);
}

function unique(list) {
    const out = [];
    for (const e of Array.isArray(list) ? list : []) {
        if (typeof e === "string" && out.indexOf(e) < 0) out.push(e);
    }
    return out;
}

function clean_last(raw) {
    const out = {};
    if (is_object(raw)) {
        for (const k of Object.keys(raw)) {
            if (sides.indexOf(raw[k]) >= 0) out[k] = raw[k];
        }
    }
    return out;
}

// Clean copy of a state file's contents; throws on the wrong shape.
function normalize(raw) {
    if (raw === null || raw === undefined) return { shared: { place: {}, order: [], last_side: {} }, monitors: {} };
    if (!is_object(raw)) throw new Error("bars.json state must be a JSON object");
    const shared = is_object(raw.shared) ? raw.shared : {};
    const place = {};
    if (is_object(shared.place)) {
        for (const k of Object.keys(shared.place)) {
            const side = shared.place[k];
            if (side === "hidden" || sides.indexOf(side) >= 0) place[k] = side;
        }
    }
    const monitors = {};
    if (is_object(raw.monitors)) {
        for (const k of Object.keys(raw.monitors)) {
            const m = raw.monitors[k];
            if (!is_object(m)) continue;
            monitors[k] = { left: unique(m.left), center: unique(m.center), right: unique(m.right), last_side: clean_last(m.last_side) };
            if (typeof m.compact === "boolean") monitors[k].compact = m.compact;
        }
    }
    return { shared: { place: place, order: unique(shared.order), last_side: clean_last(shared.last_side) }, monitors: monitors };
}

function layout_of(rule) {
    return { left: unique(rule && rule.left), center: unique(rule && rule.center), right: unique(rule && rule.right) };
}

// Entries in `order` refill their own slots sorted by index there; the rest keep their slots.
function sort_side(list, order) {
    const slots = [];
    const ranked = [];
    list.forEach((e, i) => {
        const at = order.indexOf(e);
        if (at >= 0) {
            slots.push(i);
            ranked.push(e);
        }
    });
    ranked.sort((a, b) => order.indexOf(a) - order.indexOf(b));
    const out = list.slice();
    slots.forEach((slot, i) => out[slot] = ranked[i]);
    return out;
}

// The tracked rule with the shared layout, or the monitor's own override, applied. `state` must be normalized.
function effective(rule, state, key) {
    if (!rule) return null;
    const out = Object.assign({}, rule, layout_of(rule));
    const own = key && state.monitors[key];
    if (own) {
        for (const s of sides) out[s] = own[s].slice();
        if (own.compact !== undefined) out.compact = own.compact;
        return out;
    }
    const place = state.shared.place;
    for (const entry of Object.keys(place)) {
        const to = place[entry];
        if (to !== "hidden" && out[to].indexOf(entry) >= 0) continue;
        for (const s of sides) out[s] = out[s].filter(e => e !== entry);
        if (to !== "hidden") out[to].push(entry);
    }
    for (const s of sides) out[s] = sort_side(out[s], state.shared.order);
    return out;
}

function side_of(layout, entry) {
    for (const s of sides) {
        if (layout[s].indexOf(entry) >= 0) return s;
    }
    return "";
}

// Known modules plus anything a tracked rule or the state names, minus what `layout` shows.
function hidden_entries(rules, state, layout) {
    const all = known.slice();
    const add = e => {
        if (all.indexOf(e) < 0) all.push(e);
    };
    for (const rule of rules) {
        for (const s of sides) unique(rule[s]).forEach(add);
    }
    Object.keys(state.shared.place).forEach(add);
    return all.filter(e => side_of(layout, e) === "");
}

// Side a tracked rule gives an entry, else "".
function tracked_side(rules, entry) {
    for (const rule of rules) {
        const s = side_of(layout_of(rule), entry);
        if (s) return s;
    }
    return "";
}

function apply_op(layout, op) {
    const out = { left: layout.left.slice(), center: layout.center.slice(), right: layout.right.slice() };
    const from = side_of(out, op.entry);
    if (op.type === "move") {
        const list = out[from];
        if (!list) return out;
        const i = list.indexOf(op.entry);
        const j = i + op.delta;
        if (j < 0 || j >= list.length) return out;
        list[i] = list[j];
        list[j] = op.entry;
        return out;
    }
    for (const s of sides) out[s] = out[s].filter(e => e !== op.entry);
    if (op.type !== "hide") out[op.side].push(op.entry);
    return out;
}

function order_from(layout, old) {
    const out = layout.left.concat(layout.center, layout.right);
    for (const e of old) {
        if (out.indexOf(e) < 0) out.push(e);
    }
    return out;
}

// Side to restore a hidden entry to: its remembered side, else the tracked one, else right.
function restore_side(rules, state, key, entry) {
    const own = key && state.monitors[key];
    const last = own ? own.last_side : state.shared.last_side;
    return last[entry] || tracked_side(rules, entry) || "right";
}

// op: { type: "hide" | "show" | "side", entry, side? } or { type: "move", entry, delta }. Returns a new state.
function edit(rule, state, key, op) {
    const next = normalize(state);
    const view = layout_of(effective(rule, next, key));
    const own = key && next.monitors[key];
    const after = apply_op(view, op);
    const was = side_of(view, op.entry);
    if (own) {
        next.monitors[key] = Object.assign({}, own, after);
        if (op.type === "hide" && was) next.monitors[key].last_side[op.entry] = was;
        return next;
    }
    if (op.type === "hide") {
        next.shared.place[op.entry] = "hidden";
        if (was) next.shared.last_side[op.entry] = was;
    } else {
        if (op.type !== "move") next.shared.place[op.entry] = op.side;
        next.shared.order = order_from(after, next.shared.order);
    }
    return next;
}

function set_own(state, key, layout, compact) {
    const next = normalize(state);
    next.monitors[key] = Object.assign({}, layout_of(layout), { compact: compact });
    return next;
}

function drop_own(state, key) {
    const next = normalize(state);
    delete next.monitors[key];
    return next;
}
