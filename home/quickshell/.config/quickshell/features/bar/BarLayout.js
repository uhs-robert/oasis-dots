.pragma library

.import "BarModules.js" as BarModules

var sides = ["left", "center", "right"];
var known = BarModules.names;
// In the order Settings steps through them.
var positions = ["top", "bottom", "left", "right"];

// The screen edge a rule puts its bar on; anything unknown falls back to top.
function position_of(rule) {
    const p = rule && rule.position;
    return positions.indexOf(p) >= 0 ? p : "top";
}

function is_vertical(position) {
    return position === "left" || position === "right";
}

// Whether a screen draws the screen frame: the frame is laid out for a top or bottom bar only, so a side bar goes without.
function draws_frame(frame_on, position) {
    return frame_on && !is_vertical(position);
}

// Whether any screen draws the frame, which is when Hyprland should shape windows to it.
function any_draws_frame(frame_on, screen_positions) {
    return screen_positions.some(p => draws_frame(frame_on, p));
}

// What Settings steps through. Left and right stay valid when saved but are not offered until the side bar looks
// right (popups, the remaining shapes, module fitting); re-enable them by making this `positions`.
var settings_positions = ["top", "bottom"];

// The position `delta` steps on from `position` in `settings_positions`, wrapping; a saved side position steps as from the first.
function step_position(position, delta) {
    const at = Math.max(0, settings_positions.indexOf(position));
    return settings_positions[(at + delta + settings_positions.length) % settings_positions.length];
}

// Why a rule's position falls back to top, or "" when it is fine.
function position_problem(rule) {
    const p = rule ? rule.position : undefined;
    if (p === undefined || positions.indexOf(p) >= 0) return "";
    return "unknown bar position " + JSON.stringify(p) + " in bars.json; using top";
}

// Right-island section a lualine bar draws a module in.
function lualine_section(entry) {
    const m = BarModules.find(entry.split(":")[0]);
    return m ? m.section : "x";
}

// Modules a lualine bar leaves out of its islands because it draws them itself (the directory in section c).
function lualine_draws_itself(entry) {
    return entry.split(":")[0] === "directory";
}

function section_sorted(list) {
    return ["x", "y", "z"].reduce((out, k) => out.concat(list.filter(e => lualine_section(e) === k)), []);
}

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
            const v = raw[k];
            if (sides.indexOf(v) >= 0) out[k] = { side: v, index: -1 };
            else if (is_object(v) && sides.indexOf(v.side) >= 0) out[k] = { side: v.side, index: Number.isInteger(v.index) && v.index >= 0 ? v.index : -1 };
        }
    }
    return out;
}

// Clean copy of a state file's contents; throws on the wrong shape.
function normalize(raw) {
    if (raw === null || raw === undefined) return { shared: { place: {}, order: [], last_side: {} }, monitors: {}, positions: {} };
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
    // Kept apart from `monitors` so a monitor keeps its edge whether or not it has its own layout.
    const saved_positions = {};
    if (is_object(raw.positions)) {
        for (const k of Object.keys(raw.positions)) {
            if (positions.indexOf(raw.positions[k]) >= 0) saved_positions[k] = raw.positions[k];
        }
    }
    // Before `positions`, a pre-release build saved the position inside the monitor's own layout.
    for (const k of Object.keys(monitors)) {
        const nested_position = raw.monitors[k].position;
        if (!(k in saved_positions) && positions.indexOf(nested_position) >= 0) saved_positions[k] = nested_position;
    }
    const out_shared = { place: place, order: unique(shared.order), last_side: clean_last(shared.last_side) };
    if (positions.indexOf(shared.position) >= 0) out_shared.position = shared.position;
    const out = { shared: out_shared, monitors: monitors, positions: saved_positions };
    // Written only once a switch is flipped, so a state file without one reads as all on.
    if (is_object(raw.directory)) {
        const switches = {};
        for (const k of directory_switch_names) {
            if (typeof raw.directory[k] === "boolean") switches[k] = raw.directory[k];
        }
        if (Object.keys(switches).length > 0) out.directory = switches;
    }
    if (raw.cava_migrated === true) out.cava_migrated = true;
    return out;
}

// The directory module's global on/off switches: the app name, the path, and the file name Neovim has open.
var directory_switch_names = ["app_name", "path", "file_name"];

function directory_switches(state) {
    const out = {};
    for (const k of directory_switch_names) out[k] = !(state && state.directory && state.directory[k] === false);
    return out;
}

function set_directory_switch(state, name, on) {
    const next = normalize(state);
    if (directory_switch_names.indexOf(name) < 0) return next;
    next.directory = Object.assign({}, next.directory, { [name]: !!on });
    return next;
}

// One-time: a monitor with its own saved layout predates the `cava` module, so it gets the entry after workspaces
// (else at the end of left). The flag keeps a later removal from being undone; BarSettings stamps every write with it.
function migrate_cava(state) {
    const next = normalize(state);
    if (next.cava_migrated) return next;
    for (const m of Object.values(next.monitors)) {
        if (sides.some(s => m[s].some(e => e.split(":")[0] === "cava"))) continue;
        m.left.splice(m.left.indexOf("workspaces") + 1 || m.left.length, 0, "cava");
    }
    next.cava_migrated = true;
    return next;
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

// Where a monitor's position comes from: "monitor" (its own saved value), "global" (the shared one), "bars.json" (the rule names one) or "default" (top).
function position_source(rule, state, key) {
    if (key && state.positions[key]) return "monitor";
    if (state.shared.position) return "global";
    return rule && rule.position !== undefined ? "bars.json" : "default";
}

// The tracked rule with the shared layout, or the monitor's own override, and its saved position applied. `state` must be normalized.
function effective(rule, state, key) {
    if (!rule) return null;
    const out = Object.assign({}, rule, layout_of(rule));
    if (key && state.positions[key]) out.position = state.positions[key];
    // A Settings override like the shared layout, so it wins over the tracked rule; unlike that layout it also reaches monitors with their own.
    else if (state.shared.position) out.position = state.shared.position;
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

// Stable override key (own layout or position): an exact match, else the only saved key for the same description whose connector is not a live screen with that description.
function resolve_key(state, description, name, connected) {
    const fresh = description ? description + " @ " + name : name;
    const saved_keys = Object.keys(state.monitors).concat(Object.keys(state.positions).filter(k => !(k in state.monitors)));
    if (saved_keys.indexOf(fresh) >= 0) return fresh;
    if (!description) return fresh;
    const found = saved_keys.filter(k => {
        if (k === description) return true;
        if (k.indexOf(description + " @ ") !== 0) return false;
        const connector = k.slice(description.length + 3);
        return !connected.some(c => c.name === connector && c.description === description);
    });
    return found.length === 1 ? found[0] : fresh;
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
    Object.keys(state.shared.last_side).forEach(add);
    for (const m of Object.values(state.monitors)) {
        for (const s of sides) m[s].forEach(add);
        Object.keys(m.last_side).forEach(add);
    }
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
        const j = op.with ? list.indexOf(op.with) : i + op.delta;
        if (j < 0 || j >= list.length) return out;
        list[i] = list[j];
        list[j] = op.entry;
        return out;
    }
    for (const s of sides) out[s] = out[s].filter(e => e !== op.entry);
    if (op.type === "hide") return out;
    const to = out[op.side];
    if (op.index >= 0) to.splice(Math.min(op.index, to.length), 0, op.entry);
    else to.push(op.entry);
    return out;
}

// The edited view's order written into `old`; entries the view lacks keep their slots.
function order_from(layout, old) {
    const view = layout.left.concat(layout.center, layout.right);
    const out = old.slice();
    view.forEach((e, i) => {
        if (out.indexOf(e) >= 0) return;
        const after = i > 0 ? out.indexOf(view[i - 1]) : -1;
        out.splice(after + 1, 0, e);
    });
    const slots = [];
    out.forEach((e, i) => {
        if (view.indexOf(e) >= 0) slots.push(i);
    });
    slots.forEach((slot, i) => out[slot] = view[i]);
    return out;
}

// { side, index } to restore a hidden entry to: remembered, else the tracked side, else right; index -1 appends.
function restore_side(rules, state, key, entry) {
    const own = key && state.monitors[key];
    const last = own ? own.last_side : state.shared.last_side;
    return last[entry] || { side: tracked_side(rules, entry) || "right", index: -1 };
}

// Forgets an entry everywhere in the state.
function purge(state, entry) {
    const next = normalize(state);
    delete next.shared.place[entry];
    delete next.shared.last_side[entry];
    next.shared.order = next.shared.order.filter(e => e !== entry);
    for (const m of Object.values(next.monitors)) {
        for (const s of sides) m[s] = m[s].filter(e => e !== entry);
        delete m.last_side[entry];
    }
    return next;
}

// Arguments the modules that take one accept.
var module_args = BarModules.modules.reduce((out, m) => {
    if (m.args.length > 0) out[m.name] = m.args;
    return out;
}, {});

// The first `base:arg` not in `taken`, else "".
function next_entry(base, taken) {
    for (const arg of module_args[base] || []) {
        if (taken.indexOf(base + ":" + arg) < 0) return base + ":" + arg;
    }
    return "";
}

// op: { type: "hide" | "show" | "side" | "remove", entry, side?, index? } or { type: "move", entry, delta } or { type: "move", entry, with } to swap with another entry. Returns a new state.
function edit(rule, state, key, op) {
    const next = normalize(state);
    const view = layout_of(effective(rule, next, key));
    const own = key && next.monitors[key];
    if (op.type === "remove") return purge(next, op.entry);
    const after = apply_op(view, op);
    const was = side_of(view, op.entry);
    if (own) {
        next.monitors[key] = Object.assign({}, own, after);
        if (op.type === "hide" && was) next.monitors[key].last_side[op.entry] = { side: was, index: view[was].indexOf(op.entry) };
        return next;
    }
    if (op.type === "hide") {
        next.shared.place[op.entry] = "hidden";
        if (was) next.shared.last_side[op.entry] = { side: was, index: view[was].indexOf(op.entry) };
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

function set_position(state, key, position) {
    const next = normalize(state);
    if (key && positions.indexOf(position) >= 0) next.positions[key] = position;
    return next;
}

function clear_position(state, key) {
    const next = normalize(state);
    delete next.positions[key];
    return next;
}

function set_shared_position(state, position) {
    const next = normalize(state);
    if (positions.indexOf(position) >= 0) next.shared.position = position;
    return next;
}

function clear_shared_position(state) {
    const next = normalize(state);
    delete next.shared.position;
    return next;
}

function set_compact(state, key, compact) {
    const next = normalize(state);
    if (next.monitors[key]) next.monitors[key].compact = compact;
    return next;
}

function drop_own(state, key) {
    const next = normalize(state);
    delete next.monitors[key];
    return next;
}
