.pragma library

// Pure rules for Settings > Developer: the saved choices and the reviewer list the rows show.
// The reviewer file format is home/claude/.claude/skills/orchestrator/reviewers.md; reviewers.sh is the real resolver.

const choices = { local: ["off", "public", "all"], gate: ["auto", "always", "never"] };

function valid(key, value) {
    return !!choices[key] && choices[key].indexOf(value) >= 0;
}

function is_object(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
}

// developer.json: { reviewers: { name: { local?, gate? } } }. Anything else is dropped, so a hand edit can't leave a
// choice invalid; a field the user never changed stays absent so the user's own file still shows through.
function clean_saved(raw) {
    const reviewers = {};
    const given = is_object(raw) && is_object(raw.reviewers) ? raw.reviewers : {};
    for (const name in given) {
        if (!is_object(given[name])) continue;
        const entry = {};
        for (const key in choices) {
            if (valid(key, given[name][key])) entry[key] = given[name][key];
        }
        if (Object.keys(entry).length > 0) reviewers[name] = entry;
    }
    return { reviewers };
}

// One layer entry as reviewers.sh normalizes it, so merging here gives the resolver's answer: a string `local` is
// {scope}, any other non-object `local` is dropped (not allowed to wipe the lower layer's), an invalid scope or
// default becomes "off", an invalid gate or enabled is dropped, a null github is dropped.
function sanitize_entry(entry) {
    const e = Object.assign({}, entry);
    if (typeof e.local === "string") e.local = { scope: e.local };
    else if (!is_object(e.local)) delete e.local;
    else e.local = Object.assign({}, e.local);
    if (e.local) {
        for (const key of ["scope", "default"]) {
            if (e.local[key] !== undefined && e.local[key] !== null && !valid("local", e.local[key])) e.local[key] = "off";
        }
    }
    if ("gate" in e && !valid("gate", e.gate)) delete e.gate;
    if ("enabled" in e && typeof e.enabled !== "boolean") delete e.enabled;
    if ("github" in e && e.github === null) delete e.github;
    return e;
}

// A reviewer file layer: { reviewers: [entry...] }; keeps the entries that are objects with a name.
function clean_layer(raw) {
    const given = is_object(raw) && Array.isArray(raw.reviewers) ? raw.reviewers : [];
    return { reviewers: given.filter(e => is_object(e) && typeof e.name === "string" && e.name !== "").map(sanitize_entry) };
}

// Objects merge field by field, everything else (arrays included) is replaced, as reviewers.sh does.
function merge(base, over) {
    if (!is_object(base) || !is_object(over)) return over;
    const out = Object.assign({}, base);
    for (const key in over) out[key] = merge(base[key], over[key]);
    return out;
}

// Built-in then user entries merged by name; `enabled: false` drops one, a later layer can set it back.
function merged_entries(builtin, user) {
    const by_name = {};
    const order = [];
    for (const entry of builtin.concat(user)) {
        if (!(entry.name in by_name)) order.push(entry.name);
        by_name[entry.name] = merge(by_name[entry.name] || {}, entry);
    }
    return order.map(name => by_name[name]).filter(e => e.enabled !== false);
}

function scope_of(local) {
    if (typeof local === "string") return valid("local", local) ? local : "off";
    if (!is_object(local)) return "off";
    const scope = local.scope !== undefined && local.scope !== null ? local.scope : local.default;
    return valid("local", scope) ? scope : "off";
}

// Which cell a click at x lands on: the Local review cell (column 0) or the Merge gate cell (column 1), with the
// step direction by the cell's half. Anywhere else is null, so the click only selects the row.
function cell_click(x, local_left, gate_left, cell_width) {
    for (const [column, left] of [[0, local_left], [1, gate_left]]) {
        if (x >= left && x < left + cell_width) return { column, delta: x < left + cell_width / 2 ? -1 : 1 };
    }
    return null;
}

// One row per entry. A Settings choice beats the files' value; a reviewer without a `local.binary` can't be probed
// and counts as installed. `installed` is the probed binaries, or null before the first probe: a row with a binary
// is then `probing` (not installed, not editable) instead of flashing "no".
function rows(entries, saved, installed) {
    return entries.map(e => {
        const mine = saved.reviewers[e.name] || {};
        const binary = is_object(e.local) && typeof e.local.binary === "string" ? e.local.binary : "";
        const probing = binary !== "" && installed === null;
        const present = binary === "" || (installed !== null && installed.indexOf(binary) >= 0);
        const file_gate = valid("gate", e.gate) ? e.gate : "auto";
        return {
            name: e.name,
            label: typeof e.label === "string" && e.label !== "" ? e.label : e.name,
            binary,
            installed: present,
            probing,
            local: present || probing ? mine.local || scope_of(e.local) : "off",
            gate: mine.gate || file_gate
        };
    });
}

// The saved choices with one field changed; the other field of that reviewer is left as it was.
function with_choice(saved, name, key, value) {
    if (!valid(key, value)) return saved;
    const reviewers = Object.assign({}, saved.reviewers);
    reviewers[name] = Object.assign({}, reviewers[name], { [key]: value });
    return { reviewers };
}

function step(key, current, delta) {
    const list = choices[key];
    const at = list.indexOf(current);
    return list[((at < 0 ? 0 : at) + delta + list.length) % list.length];
}
