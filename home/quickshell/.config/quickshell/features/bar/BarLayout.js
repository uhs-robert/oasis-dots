.pragma library

.import "BarModules.js" as BarModules

var sides = ["left", "center", "right"];
var known = BarModules.names;
// In the order Settings steps through them.
var positions = ["top", "bottom", "left", "right"];

// The screen edge a rule puts its bar on; anything unknown falls back to top.
function position_of(rule) {
    const folded = fold_bars(rule);
    const p = folded && folded.position;
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
    const folded = fold_bars(rule);
    const p = folded ? folded.position : undefined;
    if (p === undefined || positions.indexOf(p) >= 0) return "";
    return "unknown bar position " + JSON.stringify(p) + " in bars.json; using top";
}

// Right-island section a lualine bar draws a module in.
function lualine_section(entry) {
    const m = BarModules.find(entry.split(":")[0]);
    return m ? m.section : "x";
}

// How deep a lualine arrow is, along the bar, on a bar `thickness` across: 0.4 of it, as the mode chip, the sections
// and the island caps draw theirs.
function lualine_arrow(thickness) {
    return Math.round(thickness * 0.4);
}

// The mode chip's length down a lualine column: a square tile as wide as the column, then its arrow into section b.
function mode_chip_column_length(thickness) {
    return thickness + lualine_arrow(thickness);
}

// Section c of a lualine strip, along the bar from `start`: from the end of the a/b island to the x/y/z island's cap
// (or the strip's end without one). Islands are { x, y, width, height, visible }; a column reads y and height.
function lualine_c_extent(vertical, left, right, start, end) {
    const along = island => vertical ? { from: island.y, size: island.height } : { from: island.x, size: island.width };
    const c_start = left && left.visible ? along(left).from + along(left).size - start : 0;
    const c_end = (right && right.visible ? along(right).from : end) - start;
    return { start: c_start, end: c_end };
}

// Modules a lualine bar leaves out of its islands because it draws them itself in section c (the directory, cava).
function lualine_draws_itself(entry) {
    return ["directory", "cava"].indexOf(entry.split(":")[0]) >= 0;
}

// Whether a rule lists the module on any side, with or without an argument.
function rule_lists(rule, base) {
    if (!rule) return false;
    const r = layout_of(rule);
    return [r.left, r.center, r.right].some(list => (list || []).some(e => e.split(":")[0] === base));
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

// Per-module compact overrides, keyed by entry (`clock`, `system:memory`): booleans for known modules only. A twin's key
// is read as its plain entry's (system:cpu as system), which is the only key module_compact looks up.
function clean_compact_modules(raw) {
    const out = {};
    if (is_object(raw)) {
        for (const k of Object.keys(raw)) {
            if (typeof raw[k] === "boolean" && is_known_entry(k)) out[plain_entry(k)] = raw[k];
        }
    }
    return out;
}

// Sets `holder.compact_modules` to the cleaned map, leaving the key out when it is empty so untouched state files keep their shape.
function put_compact_modules(holder, raw) {
    const map = clean_compact_modules(raw);
    if (Object.keys(map).length > 0) holder.compact_modules = map;
    else delete holder.compact_modules;
    return holder;
}

// `hidden` is a first-bar placement only: a module hidden from either bar is off the screen.
function clean_place(raw, allow_hidden) {
    const out = {};
    if (is_object(raw)) {
        for (const k of Object.keys(raw)) {
            const side = raw[k];
            if ((allow_hidden && side === "hidden") || sides.indexOf(side) >= 0) out[k] = side;
        }
    }
    return out;
}

function lists_of(bar) {
    return { left: unique(bar && bar.left), center: unique(bar && bar.center), right: unique(bar && bar.right) };
}

// The shared layout's `bars` list read like a rule's (fold_bars): the first bar's `place` and `order` at the root, the
// second bar's in `second_bar`.
function fold_shared(shared) {
    if (!Array.isArray(shared.bars)) return shared;
    const first = is_object(shared.bars[0]) ? shared.bars[0] : {};
    const out = Object.assign({}, shared, { place: first.place, order: first.order });
    delete out.bars;
    if (is_object(shared.bars[1])) out.second_bar = shared.bars[1];
    return out;
}

// Clean copy of a state file's contents; throws on the wrong shape. A layout with second-bar edits comes back folded,
// its second bar in `second_bar`, as a rule does from fold_bars; `to_file` writes it out as a `bars` list again.
function normalize(raw) {
    if (raw === null || raw === undefined) return { shared: { place: {}, order: [], last_side: {} }, monitors: {}, positions: {} };
    if (!is_object(raw)) throw new Error("bars.json state must be a JSON object");
    const shared = is_object(raw.shared) ? fold_shared(raw.shared) : {};
    const place = clean_place(shared.place, true);
    const monitors = {};
    if (is_object(raw.monitors)) {
        for (const k of Object.keys(raw.monitors)) {
            if (!is_object(raw.monitors[k])) continue;
            const m = fold_bars(raw.monitors[k]);
            monitors[k] = Object.assign(lists_of(m), { last_side: clean_last(m.last_side) });
            if (is_object(m.second_bar)) monitors[k].second_bar = lists_of(m.second_bar);
            if (typeof m.compact === "boolean") monitors[k].compact = m.compact;
            put_compact_modules(monitors[k], m.compact_modules);
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
    if (is_object(shared.second_bar)) {
        const second = { place: clean_place(shared.second_bar.place, false), order: unique(shared.second_bar.order) };
        if (Object.keys(second.place).length > 0 || second.order.length > 0) out_shared.second_bar = second;
    }
    if (positions.indexOf(shared.position) >= 0) out_shared.position = shared.position;
    // The compact setting of the shared layout; a monitor with its own layout has its own.
    if (typeof shared.compact === "boolean") out_shared.compact = shared.compact;
    put_compact_modules(out_shared, shared.compact_modules);
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
    if (raw.auto_compact === false) out.auto_compact = false;
    return out;
}

// A normalized state as the file holds it: a layout with a second bar keeps both bars in a `bars` list, the shape
// bars.json rules use; a single-bar layout keeps the old shape, so files without second-bar edits do not change.
function to_file(state) {
    const unfold = (holder, keys) => {
        if (!holder.second_bar) return holder;
        const first = {};
        const out = Object.assign({}, holder);
        for (const k of keys) {
            first[k] = holder[k];
            delete out[k];
        }
        delete out.second_bar;
        out.bars = [first, holder.second_bar];
        return out;
    };
    const monitors = {};
    for (const k of Object.keys(state.monitors)) monitors[k] = unfold(state.monitors[k], sides);
    return Object.assign({}, state, { shared: unfold(state.shared, ["place", "order"]), monitors: monitors });
}

// The global auto compact switch: on by default, saved only while off.
function auto_compact(state) {
    return !(state && state.auto_compact === false);
}

function set_auto_compact(state, on) {
    const next = normalize(state);
    if (on) delete next.auto_compact;
    else next.auto_compact = false;
    return next;
}

// How far each pair of neighbouring islands overlaps along the bar (across a top or bottom bar, down a column), the
// module gap included; at or below 0 they fit. `bar` holds the room (`start`, `end`, `gap`), the first and last islands'
// lengths (`left`, `right`, 0 when hidden) and the centre island's span (`center`: `{ x, width }`, null without one).
function island_overlaps(bar) {
    if (bar.center) return [bar.start + bar.left + bar.gap - bar.center.x, bar.center.x + bar.center.width + bar.gap - (bar.end - bar.right)];
    return bar.left > 0 && bar.right > 0 ? [bar.left + bar.right + bar.gap - (bar.end - bar.start)] : [];
}

// What compact hides per island pair, in `island_overlaps`' order, from each island's `hidden` length. The centre island
// grows both ways, so each side gets half of its own.
function pair_hidden(bar) {
    if (bar.center) return [bar.hidden.left + bar.hidden.center / 2, bar.hidden.center / 2 + bar.hidden.right];
    return bar.left > 0 && bar.right > 0 ? [bar.hidden.left + bar.hidden.right] : [];
}

var auto_compact_off = { on: false, full: [], saving: null, hidden: null };

// One step of auto compact, from the last `memo`, the overlaps the bar draws now and what compact hides per pair
// (`hidden`, from `pair_hidden`). Compacting shrinks the islands, so the full layout can no longer be measured: `full`
// keeps the overlaps that turned it on, and `saving` what compacting gained per pair, taken on the first step after
// with the `hidden` of that moment. A later change to `hidden` (a new media title) moves the saving by as much. It turns
// off only once the full layout would fit with `margin` spare, so it does not flip back and forth at the edge. A change
// in the islands' pairing starts over.
function auto_compact_step(memo, overlaps, margin, hidden) {
    const now_hidden = hidden || overlaps.map(() => 0);
    if (!memo.on) return overlaps.some(o => o > 0) ? { on: true, full: overlaps, saving: null, hidden: null } : auto_compact_off;
    if (overlaps.length !== memo.full.length || now_hidden.length !== overlaps.length) return auto_compact_off;
    const saving = memo.saving || memo.full.map((f, i) => Math.max(0, f - overlaps[i]));
    const at_saving = memo.hidden || now_hidden;
    const fits = overlaps.every((o, i) => o + Math.max(0, saving[i] + now_hidden[i] - at_saving[i]) <= -margin);
    if (fits) return auto_compact_off;
    return { on: true, full: memo.full, saving: saving, hidden: at_saving };
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
    const in_map = map => !!map && "cava" in map;
    const second = s.shared.second_bar;
    return "cava" in s.shared.place || "cava" in s.shared.last_side || in_list(s.shared.order) || in_map(s.shared.compact_modules)
        || (!!second && ("cava" in second.place || in_list(second.order)))
        || Object.values(s.monitors).some(m => shown_entries(m).some(e => e.split(":")[0] === "cava") || "cava" in m.last_side || in_map(m.compact_modules));
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
    if (next.shared.compact_modules) rename_keys(next.shared.compact_modules);
    next.shared.order = rename_list(next.shared.order);
    if (next.shared.second_bar) {
        rename_keys(next.shared.second_bar.place);
        next.shared.second_bar.order = rename_list(next.shared.second_bar.order);
    }
    for (const m of Object.values(next.monitors)) {
        for (const side of sides) m[side] = rename_list(m[side]);
        if (m.second_bar) for (const side of sides) m.second_bar[side] = rename_list(m.second_bar[side]);
        rename_keys(m.last_side);
        if (m.compact_modules) rename_keys(m.compact_modules);
    }
    return next;
}

// A rule's lists. A rule with a second bar keeps its lists in `second_bar`, so the editor's view knows what that bar shows.
function layout_of(rule) {
    const r = fold_bars(rule);
    const out = { left: unique(r && r.left), center: unique(r && r.center), right: unique(r && r.right) };
    if (r && is_object(r.second_bar)) out.second_bar = Object.assign({}, r.second_bar, layout_of(r.second_bar));
    return out;
}

// Every entry a layout shows, the second bar's included.
function shown_entries(layout) {
    const bar_entries = bar => sides.reduce((all, s) => all.concat(bar[s]), []);
    return bar_entries(layout).concat(layout.second_bar ? bar_entries(layout.second_bar) : []);
}

// A rule's `bars` list read into the single-bar shape every other function here takes: the first bar's lists and
// position at the rule's root, the second bar's in `second_bar`. A rule without `bars` comes back as it is, so the
// old shape and the new read the same, and folding twice changes nothing.
function fold_bars(rule) {
    if (!rule || !Array.isArray(rule.bars)) return rule;
    const first = is_object(rule.bars[0]) ? rule.bars[0] : {};
    const out = Object.assign({}, rule, layout_of(first));
    delete out.bars;
    if (first.position !== undefined) out.position = first.position;
    if (is_object(rule.bars[1])) {
        out.second_bar = layout_of(rule.bars[1]);
        if (rule.bars[1].position !== undefined) out.second_bar.position = rule.bars[1].position;
    }
    if (rule.bars.length > 2) out.extra_bars = rule.bars.length - 2;
    return out;
}

var opposite_edge = { top: "bottom", bottom: "top" };

// The bars a screen draws from its effective rule, each { position, left, center, right }, and `problems`, what was left
// out and why. The first bar sits on the rule's edge and the second on the opposite one. A side bar has no opposite
// bar, and a module the first bar shows is dropped from the second, as a screen shows each module once.
function bars_of(rule) {
    if (!rule) return { bars: [], problems: [] };
    const lists = layout_of(rule);
    const first = { position: position_of(rule), left: lists.left, center: lists.center, right: lists.right };
    const problems = [];
    if (rule.extra_bars) problems.push("a bars.json rule lists " + (rule.extra_bars + 2) + " bars; drawing the first two");
    const second = rule.second_bar;
    if (!second) return { bars: [first], problems: problems };
    if (is_vertical(first.position)) {
        problems.push("a " + first.position + " bar has no second bar; ignoring the rule's second bar");
        return { bars: [first], problems: problems };
    }
    const edge = opposite_edge[first.position];
    if (second.position !== undefined && second.position !== edge) problems.push("the second bar goes on the edge opposite the first; drawing it on " + edge);
    const on_first = sides.reduce((all, s) => all.concat(first[s]), []).map(plain_entry);
    const out = { position: edge };
    for (const s of sides) {
        out[s] = second[s].filter(e => on_first.indexOf(plain_entry(e)) < 0);
        second[s].filter(e => out[s].indexOf(e) < 0).forEach(e => problems.push("module \"" + e + "\" is on both bars; keeping it on the first"));
    }
    return { bars: [first, out], problems: problems };
}

// A bar's modules on one line for Settings, labelled by its edge: "Top bar: start workspaces · clock · tray", an empty
// side as a dash.
function bar_summary(bar) {
    const edge = bar.position.charAt(0).toUpperCase() + bar.position.slice(1);
    return edge + " bar: " + sides.map(s => bar[s].length > 0 ? bar[s].join(" ") : "-").join(" · ");
}

// One rule per bar a screen draws (bars_of), for Bar.qml: the screen's rule with that bar's edge and lists.
function bar_rules(rule) {
    return bars_of(rule).bars.map(bar => {
        const out = Object.assign({}, rule, bar);
        delete out.second_bar;
        delete out.extra_bars;
        return out;
    });
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
    rule = fold_bars(rule);
    return rule && rule.position !== undefined ? "bars.json" : "default";
}

// The tracked rule with the shared layout, or the monitor's own override, and its saved position applied. `state` must be normalized.
function effective(rule, state, key) {
    if (!rule) return null;
    rule = fold_bars(rule);
    const out = Object.assign({}, rule, layout_of(rule));
    if (key && state.positions[key]) out.position = state.positions[key];
    // A Settings override like the shared layout, so it wins over the tracked rule; unlike that layout it also reaches monitors with their own.
    else if (state.shared.position) out.position = state.shared.position;
    const own = key && state.monitors[key];
    // The editor's per-module overrides win over the rule's, entry by entry, like its layout compact over the rule's.
    const with_overrides = layer => put_compact_modules(out, Object.assign(clean_compact_modules(rule.compact_modules), layer.compact_modules));
    // The rule decides whether the screen has a second bar; a saved second bar only fills one the rule has.
    const second = out.second_bar ? Object.assign({}, out.second_bar, lists_of(out.second_bar)) : null;
    if (second) out.second_bar = second;
    if (own) {
        for (const s of sides) out[s] = own[s].slice();
        if (second && own.second_bar) Object.assign(second, lists_of(own.second_bar));
        if (own.compact !== undefined) out.compact = own.compact;
        return with_overrides(own);
    }
    if (state.shared.compact !== undefined) out.compact = state.shared.compact;
    with_overrides(state.shared);
    const bars = second ? [out, second] : [out];
    const layers = second && state.shared.second_bar ? [state.shared, state.shared.second_bar] : [state.shared];
    layers.forEach((layer, b) => {
        for (const entry of Object.keys(layer.place)) {
            const to = layer.place[entry];
            // A plain entry's placement covers its twin too (system:cpu); a saved twin's own entry stays exact, so a stale one cannot hide the plain module.
            const is_entry = e => e === entry || (plain_entry(entry) === entry && plain_entry(e) === entry);
            const elsewhere = sides.some(s => bars[b][s].some(e => e !== entry && is_entry(e))) || bars.some((bar, i) => i !== b && sides.some(s => bar[s].some(is_entry)));
            if (to !== "hidden" && bars[b][to].indexOf(entry) >= 0 && !elsewhere) continue;
            // Off both bars, as a screen shows each module once, then onto this layer's bar.
            for (const bar of bars) {
                for (const s of sides) bar[s] = bar[s].filter(e => !is_entry(e));
            }
            if (to !== "hidden") bars[b][to].push(entry);
        }
    });
    bars.forEach((bar, b) => {
        const order = layers[b] ? layers[b].order : [];
        for (const s of sides) bar[s] = sort_side(bar[s], order);
    });
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
    for (const rule of rules) shown_entries(layout_of(rule)).forEach(add);
    Object.keys(state.shared.place).forEach(add);
    if (state.shared.second_bar) Object.keys(state.shared.second_bar.place).forEach(add);
    Object.keys(state.shared.last_side).forEach(add);
    for (const m of Object.values(state.monitors)) {
        shown_entries(m).forEach(add);
        Object.keys(m.last_side).forEach(add);
    }
    const shown = shown_entries(layout);
    return all.filter(e => shown.indexOf(e) < 0);
}

// Side a tracked rule gives an entry, else "".
function tracked_side(rules, entry) {
    for (const rule of rules) {
        const lists = layout_of(rule);
        const s = side_of(lists, entry) || (lists.second_bar ? side_of(lists.second_bar, entry) : "");
        if (s) return s;
    }
    return "";
}

// Which bar of `layout` (a layout_of view) shows `entry`: 0 the first, 1 the second, -1 neither.
function bar_holding(layout, entry) {
    if (side_of(layout, entry)) return 0;
    return layout.second_bar && side_of(layout.second_bar, entry) ? 1 : -1;
}

// The lists of bar `bar` (0 or 1) of a layout_of view; the first bar when the view has no second.
function bar_view(layout, bar) {
    return bar === 1 && layout.second_bar ? layout.second_bar : layout;
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
    for (const s of sides) out[s] = out[s].filter(e => plain_entry(e) !== plain_entry(op.entry));
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
    // A saved twin (system:cpu) holds the slot plain system takes back.
    const remembered_as = [entry].concat(Object.keys(same_as).filter(twin => same_as[twin] === entry)).find(e => last[e]);
    return last[remembered_as] || { side: tracked_side(rules, entry) || "right", index: -1 };
}

function without(map, key) {
    const out = Object.assign({}, map);
    delete out[key];
    return out;
}

// Forgets an entry everywhere in the state.
function purge(state, entry) {
    const next = normalize(state);
    delete next.shared.place[entry];
    delete next.shared.last_side[entry];
    next.shared.order = next.shared.order.filter(e => e !== entry);
    const drop_override = map => without(without(map, entry), plain_entry(entry));
    if (next.shared.compact_modules) put_compact_modules(next.shared, drop_override(next.shared.compact_modules));
    if (next.shared.second_bar) {
        delete next.shared.second_bar.place[entry];
        next.shared.second_bar.order = next.shared.second_bar.order.filter(e => e !== entry);
    }
    for (const m of Object.values(next.monitors)) {
        for (const s of sides) m[s] = m[s].filter(e => e !== entry);
        if (m.second_bar) for (const s of sides) m.second_bar[s] = m.second_bar[s].filter(e => e !== entry);
        delete m.last_side[entry];
        if (m.compact_modules) put_compact_modules(m, drop_override(m.compact_modules));
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
    const on = shown_entries(layout).map(plain_entry);
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
// `op.bar` (0, the default, or 1) is the bar the op works on: a show or side op lands the entry on that bar and takes it
// off the other one.
function edit(rule, state, key, op) {
    const next = normalize(state);
    const view = layout_of(effective(rule, next, key));
    const own = key && next.monitors[key];
    if (op.type === "remove") return purge(next, op.entry);
    const bar = op.bar === 1 && view.second_bar ? 1 : 0;
    const after = apply_op(bar_view(view, bar), op);
    const held_by = bar_holding(view, op.entry);
    const was_view = bar_view(view, held_by);
    const was = held_by < 0 ? "" : side_of(was_view, op.entry);
    const remembered = () => ({ side: was, index: was_view[was].indexOf(op.entry) });
    if (own) {
        const other = bar === 1 ? view : view.second_bar;
        const other_after = other && op.type !== "move" ? apply_op(other, { type: "hide", entry: op.entry }) : other;
        const first = bar === 1 ? other_after : after;
        next.monitors[key] = Object.assign({}, own, lists_of(first));
        if (view.second_bar) next.monitors[key].second_bar = lists_of(bar === 1 ? after : other_after);
        if (op.type === "hide" && was) next.monitors[key].last_side[op.entry] = remembered();
        return next;
    }
    const plain = plain_entry(op.entry);
    if (bar === 1 && !next.shared.second_bar) next.shared.second_bar = { place: {}, order: [] };
    const layers = [next.shared].concat(next.shared.second_bar ? [next.shared.second_bar] : []);
    // A new placement under the plain name replaces any saved twin placement, and the other bar's placement of it, which
    // `effective` would otherwise apply after it.
    // A hide is written on the first bar, whichever bar it came from.
    const home = op.type === "hide" ? 0 : bar;
    if (op.type !== "move") {
        layers.forEach((layer, b) => Object.keys(layer.place).filter(k => plain_entry(k) === plain && (k !== plain || b !== home)).forEach(k => delete layer.place[k]));
    }
    if (op.type === "hide") {
        next.shared.place[plain] = "hidden";
        if (was) next.shared.last_side[op.entry] = remembered();
    } else {
        if (op.type !== "move") layers[bar].place[plain] = op.side;
        layers[bar].order = order_from(after, layers[bar].order);
    }
    if (next.shared.second_bar && Object.keys(next.shared.second_bar.place).length === 0 && next.shared.second_bar.order.length === 0) delete next.shared.second_bar;
    return next;
}

function set_own(state, key, layout, compact, compact_modules) {
    const next = normalize(state);
    const lists = layout_of(layout);
    const own = Object.assign(lists_of(lists), { compact: compact });
    if (lists.second_bar) own.second_bar = lists_of(lists.second_bar);
    next.monitors[key] = put_compact_modules(own, compact_modules);
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
// `bar` (0 or 1) is the bar being edited.
function move_step(rule, state, key, entry, delta, sectioned, bar) {
    const next = normalize(state);
    const view = bar_view(layout_of(effective(rule, next, key)), bar);
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
        if (neighbor_side === side) return edit(rule, next, key, { type: "move", entry: entry, with: neighbor, bar: bar });
        // Onto the other side of the neighbor, so the two trade places in the drawn order.
        return edit(rule, next, key, { type: "side", entry: entry, side: neighbor_side, index: view[neighbor_side].indexOf(neighbor) + (delta > 0 ? 1 : 0), bar: bar });
    }
    const to = is_sectioned ? (delta < 0 ? "left" : undefined) : sides[sides.indexOf(side) + delta];
    if (to === undefined) return next;
    return edit(rule, next, key, { type: "side", entry: entry, side: to, index: delta > 0 ? 0 : -1, bar: bar });
}

// Moves `entry` onto bar `bar` (0 or 1), on the side it had, at that side's end. Nothing changes without a second bar
// or when the entry is already there.
function move_to_bar(rule, state, key, entry, bar) {
    const next = normalize(state);
    const view = layout_of(effective(rule, next, key));
    const from = bar_holding(view, entry);
    if (!view.second_bar || from < 0 || from === bar) return next;
    return edit(rule, next, key, { type: "side", entry: entry, side: side_of(bar_view(view, from), entry), index: -1, bar: bar });
}

// Takes the module off the bar into the hidden list. Nothing is purged, so it can come back.
function hide_entry(rule, state, key, entry) {
    return edit(rule, state, key, { type: "hide", entry: entry });
}

// Puts a hidden module back on the side it left (else the tracked side, else right), on bar `bar` (0 or 1), the one being edited.
function unhide_place(rules, rule, state, key, entry, bar) {
    const next = normalize(state);
    const back = restore_side(rules, next, key, entry);
    return edit(rule, next, key, { type: "show", entry: entry, side: back.side, index: back.index, bar: bar });
}

// `o`: a sharing monitor gets a copy of what it shows now; a monitor with its own layout goes back to the shared one.
function toggle_own(rule, state, key) {
    const next = normalize(state);
    if (!is_sharing(next, key)) return drop_own(next, key);
    const view = effective(rule, next, key);
    // Only the editor's overrides are copied: the rule's own still apply under an own layout.
    return set_own(next, key, view, !!(view && view.compact), next.shared.compact_modules);
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

// Whether `entry` draws compact on a bar showing `rule` (an effective one): its own override, else the layout's compact.
// system and system:cpu are one module, so they share one override.
function module_compact(rule, entry) {
    const map = (rule && rule.compact_modules) || {};
    const k = plain_entry(entry);
    return k in map ? map[k] : !!(rule && rule.compact);
}

function supports_compact(entry) {
    return BarModules.supports_compact(entry.split(":")[0]);
}

// The override `entry` draws with on the edited bar, from the rule's map and the editor's together: "inherit" (none, so the
// layout's compact decides), "on" or "off".
function compact_override(rule, state, key, entry) {
    const map = (effective(rule, normalize(state), key) || {}).compact_modules || {};
    const k = plain_entry(entry);
    return k in map ? (map[k] ? "on" : "off") : "inherit";
}

// `c` in NORMAL: steps `entry` inherit -> on -> off -> inherit from the override it draws with, writing the edited layout's
// own. When the rule names the entry, inherit would only bring the rule's value back (and get stuck there), so `c` writes
// the opposite of what is drawn instead. A module with no compact form is left alone.
function cycle_module_compact(rule, state, key, entry) {
    const next = normalize(state);
    if (!supports_compact(entry)) return next;
    const layer = is_sharing(next, key) ? next.shared : next.monitors[key];
    const k = plain_entry(entry);
    const drawn = compact_override(rule, next, key, entry);
    const rule_names = k in clean_compact_modules(rule && rule.compact_modules);
    const after = rule_names ? drawn !== "on" : { inherit: true, on: false, off: undefined }[drawn];
    const map = without(layer.compact_modules || {}, k);
    if (after !== undefined) map[k] = after;
    put_compact_modules(layer, map);
    return next;
}
