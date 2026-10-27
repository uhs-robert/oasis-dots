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

// A reviewer file layer: { reviewers: [entry...] }; keeps the entries that are objects with a name.
function clean_layer(raw) {
    const given = is_object(raw) && Array.isArray(raw.reviewers) ? raw.reviewers : [];
    return { reviewers: given.filter(e => is_object(e) && typeof e.name === "string" && e.name !== "") };
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

// One row per entry. A Settings choice beats the files' value; a reviewer without a `local.binary` can't be probed
// and counts as installed.
function rows(entries, saved, installed) {
    return entries.map(e => {
        const mine = saved.reviewers[e.name] || {};
        const binary = is_object(e.local) && typeof e.local.binary === "string" ? e.local.binary : "";
        const present = binary === "" || installed.indexOf(binary) >= 0;
        const file_gate = valid("gate", e.gate) ? e.gate : "auto";
        return {
            name: e.name,
            label: typeof e.label === "string" && e.label !== "" ? e.label : e.name,
            binary,
            installed: present,
            local: present ? mine.local || scope_of(e.local) : "off",
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
