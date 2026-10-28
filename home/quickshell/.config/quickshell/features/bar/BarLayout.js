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

// The Ctrl+letters that walk the popups along a bar: H and L along a row, K and J down a column. The other pair is
// left to the popups, so a list's own Ctrl+J/K (the picker) is not taken on a bar it cannot mean.
function walk_keys(position) {
    return is_vertical(position) ? { back: "K", forward: "J" } : { back: "H", forward: "L" };
}

// Whether a screen draws the screen frame: the frame is laid out for a top or bottom bar only, so a side bar goes without.
function draws_frame(frame_on, position) {
    return frame_on && !is_vertical(position);
}

// A bar's thickness: bars.json height, else the style's (its vertical one on a side bar when it sets one), else the default.
function thickness_for(rule_height, style_height, style_vertical_height, position, default_height) {
    if (rule_height > 0) return rule_height;
    if (is_vertical(position) && style_vertical_height > 0) return style_vertical_height;
    return style_height > 0 ? style_height : default_height;
}

// The screen height a top or bottom bar takes (its thickness plus the float gap above a floating popup); a side bar takes width instead, so none.
function vertical_reserve(position, bar_thickness, float_gap) {
    return is_vertical(position) ? 0 : bar_thickness + float_gap;
}

// Whether any screen draws the frame, which is when Hyprland should shape windows to it.
function any_draws_frame(frame_on, screen_positions) {
    return screen_positions.some(p => draws_frame(frame_on, p));
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

// Modules a lualine bar leaves out of its islands because it draws them itself in section c (the directory, cava).
function lualine_draws_itself(entry) {
    return ["directory", "cava"].indexOf(entry.split(":")[0]) >= 0;
}

// Whether a rule lists the module on any side, with or without an argument.
function rule_lists(rule, base) {
    if (!rule) return false;
    return [rule.left, rule.center, rule.right].some(list => (list || []).some(e => e.split(":")[0] === base));
}

// The stretches of a framed lualine bar's edge outside the strip, as [from, to] pairs: where the frame's own band shows. The strip fills `start` to `end` itself, so a translucent band under it would stack alpha on the strip's non-overlapping fills.
function lualine_side_spans(start, end, width) {
    return [[0, start], [end, width]].filter(span => span[1] > span[0]);
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
    // The compact setting of the shared layout; a monitor with its own layout has its own.
    if (typeof shared.compact === "boolean") out_shared.compact = shared.compact;
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

// One-time: a monitor with its own saved layout predates the media module, so it gets the entry after workspaces
// (else at the end of left). The flag keeps a later removal from being undone; BarSettings stamps every write with it.
// `cava` is the module's old name and counts as already listed.
function migrate_cava(state) {
    const next = normalize(state);
    if (next.cava_migrated) return next;
    for (const m of Object.values(next.monitors)) {
        if (sides.some(s => m[s].some(e => ["media", "cava"].indexOf(e.split(":")[0]) >= 0))) continue;
        m.left.splice(m.left.indexOf("workspaces") + 1 || m.left.length, 0, "media");
    }
    next.cava_migrated = true;
    return next;
}

// Whether a state file still names the old `cava` module anywhere.
function has_cava(state) {
    const s = normalize(state);
    const in_list = list => list.some(e => e.split(":")[0] === "cava");
    return "cava" in s.shared.place || "cava" in s.shared.last_side || in_list(s.shared.order)
        || Object.values(s.monitors).some(m => sides.some(side => in_list(m[side])) || "cava" in m.last_side);
}

// `cava` was renamed `media`. A list that names both keeps the `media` one; otherwise `cava` takes `media`'s name in
// place. Returns `state` itself, untouched, when it names no `cava`, so a caller writes the file only on a change.
function migrate_cava_to_media(state) {
    if (!has_cava(state)) return state;
    const next = normalize(state);
    const rename_list = list => {
        const keep_media = list.indexOf("media") >= 0;
        return unique(list.filter(e => !(keep_media && e === "cava")).map(e => e === "cava" ? "media" : e));
    };
    const rename_keys = map => {
        if (!("cava" in map)) return map;
        if (!("media" in map)) map.media = map.cava;
        delete map.cava;
        return map;
    };
    rename_keys(next.shared.place);
    rename_keys(next.shared.last_side);
    next.shared.order = rename_list(next.shared.order);
    for (const m of Object.values(next.monitors)) {
        for (const side of sides) m[side] = rename_list(m[side]);
        rename_keys(m.last_side);
    }
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
    if (state.shared.compact !== undefined) out.compact = state.shared.compact;
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
    const aliases = BarModules.modules.filter(m => m.alias_of).map(m => m.name);
    const all = known.filter(e => aliases.indexOf(e) < 0);
    const add = e => {
        if (all.indexOf(e) < 0 && aliases.indexOf(e) < 0) all.push(e);
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

// Entries that render identically to a plainer one: system draws CPU only, so system:cpu is the same module as system.
var same_as = { "system:cpu": "system" };

function plain_entry(entry) {
    return same_as[entry] || entry;
}

// What the editor's hidden list offers for the layout being edited: the hidden modules, then every `base:arg` variant not on
// it. An entry and its `same_as` twin count as one, so system:cpu is never offered (system is) and CPU cannot land twice.
function addable_entries(rules, state, layout) {
    const on = sides.reduce((all, s) => all.concat(layout[s]), []).map(plain_entry);
    const out = [];
    const add = entry => {
        const plain = plain_entry(entry);
        if (on.indexOf(plain) < 0 && out.indexOf(plain) < 0) out.push(plain);
    };
    const hidden = hidden_entries(rules, state, layout);
    hidden.filter(e => e.indexOf(":") < 0).forEach(add);
    hidden.filter(e => e.indexOf(":") >= 0).forEach(add);
    for (const base of Object.keys(module_args)) module_args[base].forEach(arg => add(base + ":" + arg));
    return out;
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

// The bar editor's edits. Each takes the tracked `rule` of the monitor being edited and returns a new state; a monitor
// without its own layout edits the shared one, so every monitor sharing it follows.

function is_sharing(state, key) {
    return !(key && state.monitors[key]);
}

function is_known_entry(entry) {
    return known.indexOf(entry.split(":")[0]) >= 0;
}

// The modules in the order a bar shows them, which `h`/`l` step through. `sectioned` is a lualine bar on a row: it draws the
// center and right modules by section and leaves out the ones it draws itself.
function nav_order(layout, sectioned) {
    const all = sectioned ? layout.left.concat(section_sorted(layout.center.concat(layout.right)).filter(e => !lualine_draws_itself(e))) : layout.left.concat(layout.center, layout.right);
    return all.filter(is_known_entry);
}

// The entry `delta` places from `entry` in `order`, stopping at the ends; the first when `entry` is not in it.
function nav_step(order, entry, delta) {
    const at = order.indexOf(entry);
    if (at < 0) return order[0] || "";
    return order[Math.max(0, Math.min(order.length - 1, at + delta))];
}

// The modules a sectioned (lualine) bar shows from center and right, in the order it draws them: one list sorted by section.
function lualine_shown(layout) {
    return section_sorted(layout.center.concat(layout.right)).filter(e => !lualine_draws_itself(e) && is_known_entry(e));
}

// Moves `entry` one place along the bar: swaps with the neighbor on its side, or crosses to the next side at the end of
// it (left to center to right). A sectioned (lualine) bar draws center and right as one sorted list, so there the neighbor
// is the next module shown, even on the other side, and it never swaps a module out of its section; the left side is not sectioned.
function move_step(rule, state, key, entry, delta, sectioned) {
    const next = normalize(state);
    const view = layout_of(effective(rule, next, key));
    const side = side_of(view, entry);
    if (side === "") return next;
    const is_sectioned = sectioned && side !== "left";
    // Each shown module keeps the side it came from: a module listed on both center and right shows twice, and
    // side_of would name center for both.
    const pairs = is_sectioned ? view.center.map(e => [e, "center"]).concat(view.right.map(e => [e, "right"])) : view[side].map(e => [e, side]);
    const tagged = is_sectioned ? ["x", "y", "z"].reduce((out, k) => out.concat(pairs.filter(p => lualine_section(p[0]) === k)), []).filter(p => !lualine_draws_itself(p[0]) && is_known_entry(p[0])) : pairs;
    const at = tagged.findIndex(p => p[0] === entry);
    const neighbor_pair = tagged[at + delta];
    if (neighbor_pair !== undefined) {
        const neighbor = neighbor_pair[0];
        if (is_sectioned && lualine_section(neighbor) !== lualine_section(entry)) return next;
        const neighbor_side = neighbor_pair[1];
        if (neighbor_side === side) return edit(rule, next, key, { type: "move", entry: entry, with: neighbor });
        // Onto the other side of the neighbor, so the two trade places in the drawn order.
        return edit(rule, next, key, { type: "side", entry: entry, side: neighbor_side, index: view[neighbor_side].indexOf(neighbor) + (delta > 0 ? 1 : 0) });
    }
    const to = is_sectioned ? (delta < 0 ? "left" : undefined) : sides[sides.indexOf(side) + delta];
    if (to === undefined) return next;
    return edit(rule, next, key, { type: "side", entry: entry, side: to, index: delta > 0 ? 0 : -1 });
}

// Takes the module off the bar into the hidden list. Nothing is purged, so it can come back.
function hide_entry(rule, state, key, entry) {
    return edit(rule, state, key, { type: "hide", entry: entry });
}

// Puts a hidden module back on the side it left (else the tracked side, else right).
function unhide_place(rules, rule, state, key, entry) {
    const next = normalize(state);
    const back = restore_side(rules, next, key, entry);
    return edit(rule, next, key, { type: "show", entry: entry, side: back.side, index: back.index });
}

// `o`: a sharing monitor gets a copy of what it shows now; a monitor with its own layout goes back to the shared one.
function toggle_own(rule, state, key) {
    const next = normalize(state);
    if (!is_sharing(next, key)) return drop_own(next, key);
    const view = effective(rule, next, key);
    return set_own(next, key, view, !!(view && view.compact));
}

// `c`: flips the compact the edited layout shows: every sharing monitor on a shared layout, one monitor on its own. On a
// shared layout the flipped value is written, or the setting removed when every sharing monitor's rule (`sharing_rules`, the
// edited one by default) already gives it, so the rules apply again without changing any monitor's look.
function toggle_compact(rule, state, key, sharing_rules) {
    const next = normalize(state);
    const flipped = !(effective(rule, next, key) || {}).compact;
    if (!is_sharing(next, key)) return set_compact(next, key, flipped);
    const rules = sharing_rules && sharing_rules.length > 0 ? sharing_rules : [rule];
    if (rules.every(r => flipped === !!(r && r.compact))) delete next.shared.compact;
    else next.shared.compact = flipped;
    return next;
}

// The bar edge follows the layout mode: a sharing monitor moves the shared edge (dropping its own saved one, which would
// outrank it and leave the bar where it was), a monitor with its own layout moves only its own edge.
function set_position_for_mode(state, key, position) {
    if (!is_sharing(normalize(state), key)) return set_position(state, key, position);
    return set_shared_position(clear_position(state, key), position);
}

// What `x` in VISUAL forgets: the saved position set_position_for_mode would write. A sharing monitor also loses its own saved
// one, which survives `o` back to shared and would outrank the cleared shared position; an own-layout monitor never touches the shared one.
function forget_position_for_mode(state, key) {
    if (!is_sharing(normalize(state), key)) return clear_position(state, key);
    return clear_shared_position(clear_position(state, key));
}
