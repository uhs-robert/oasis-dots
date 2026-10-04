.pragma library

// What the cursor is completing: a command name, a command's Nth argument, or a shell command after `!`.
function context_of(spec, line) {
    let head = "";
    let seg = line;
    if (spec.chain && !/^(?:!|silent\s+!|%?s\/)/.test(line)) {
        const cut = line.lastIndexOf("|");
        if (cut >= 0) {
            const rest = line.slice(cut + 1);
            const lead = rest.match(/^\s*/)[0];
            head = line.slice(0, cut + 1) + lead;
            seg = rest.slice(lead.length);
        }
    }
    const shell = seg.match(/^((?:silent\s+)?!)(\S*)$/);
    if (shell) return spec.shell_source ? { kind: "shell", head: head + shell[1], cur: shell[2] } : { kind: "none" };
    if (/^(?:silent\s+)?!/.test(seg) || /^%?s\//.test(seg)) return { kind: "none" };
    const space = seg.indexOf(" ");
    if (space < 0) return { kind: "command", head: head, cur: seg };
    const words = seg.slice(space + 1).split(/\s+/).filter(w => w !== "");
    const trailing = /\s$/.test(seg);
    const cur = trailing ? "" : words[words.length - 1] || "";
    const pos = trailing ? words.length + 1 : words.length;
    return { kind: "arg", head: head + seg.slice(0, seg.length - cur.length), cmd: seg.slice(0, space), pos: pos, cur: cur, prev: words.slice(0, pos - 1).join(" ") };
}

function canonical(spec, cmd) {
    const args = spec.args || {};
    if (args[cmd]) return cmd;
    const entry = (spec.completions || []).find(c => (c.aliases || []).indexOf(cmd) >= 0);
    return entry ? entry.name : cmd;
}

function arg_spec_for(spec, cmd, pos) {
    const positions = (spec.args || {})[canonical(spec, cmd)];
    return positions && pos >= 1 && pos <= positions.length ? positions[pos - 1] : null;
}

function entry_for(spec, cmd) {
    return (spec.completions || []).find(c => c.name === cmd || (c.aliases || []).indexOf(cmd) >= 0) || null;
}

// First required argument the line leaves empty, or 0. A spec without min_args never holds Enter.
function missing_pos(spec, c) {
    if (c.kind !== "command" && c.kind !== "arg") return 0;
    const entry = entry_for(spec, c.kind === "command" ? c.cur : c.cmd);
    const need = entry && entry.min_args > 0 ? entry.min_args : 0;
    const filled = c.kind === "command" ? 0 : c.cur !== "" ? c.pos : c.pos - 1;
    return filled < need ? filled + 1 : 0;
}

// "value<TAB>description[<TAB>insert]" lines; a line with no value is not a candidate.
function parse_source(text) {
    const out = [];
    for (const line of text.split("\n")) {
        const f = line.split("\t");
        const value = f[0].trim();
        if (value === "") continue;
        out.push({ label: value, description: f[1] || "", insert: (f[2] || value) + " " });
    }
    return out;
}
