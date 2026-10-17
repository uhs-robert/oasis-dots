.pragma library

var scales = [0.75, 1, 1.25, 1.5, 1.6, 1.75, 2, 2.5, 3];
var rotations = [0, 1, 2, 3];
var nudge_step = 100;
var fine_step = 10;
var snap_reach = 24;

function round2(n) {
    return Math.round(n * 100) / 100;
}

function parse_modes(list) {
    const out = [];
    for (const text of Array.isArray(list) ? list : []) {
        const m = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(text);
        if (m) out.push({ w: +m[1], h: +m[2], r: round2(+m[3]) });
    }
    return out;
}

// Monitors from `hyprctl monitors all -j`, in Hyprland's order.
function parse_monitors(raw) {
    const out = [];
    for (const m of Array.isArray(raw) ? raw : []) {
        if (!m || typeof m.name !== "string") continue;
        const desc = typeof m.description === "string" ? m.description : "";
        out.push({
            name: m.name,
            description: desc,
            model: typeof m.model === "string" ? m.model : "",
            key: desc !== "" ? desc : m.name,
            disabled: m.disabled === true,
            width: m.width | 0,
            height: m.height | 0,
            refresh: round2(+m.refreshRate || 0),
            x: m.x | 0,
            y: m.y | 0,
            scale: round2(+m.scale || 1),
            transform: m.transform | 0,
            modes: parse_modes(m.availableModes)
        });
    }
    return out;
}

function mode_string(w, h, r) {
    return w + "x" + h + "@" + round2(r);
}

// The rule that reproduces a monitor as it is now.
function spec_of(m) {
    if (m.disabled) return { disabled: true };
    return { mode: mode_string(m.width, m.height, m.refresh), position: m.x + "x" + m.y, scale: m.scale, transform: m.transform };
}

function spec_with(m, patch) {
    const base = m.disabled ? { mode: "preferred", position: "auto", scale: m.scale, transform: m.transform } : spec_of(m);
    return Object.assign(base, patch);
}

// The monitor as `spec` will leave it, until the next refresh says what really happened.
function apply_spec(m, spec) {
    const out = Object.assign({}, m);
    if (spec.disabled) {
        out.disabled = true;
        return out;
    }
    out.disabled = false;
    const mode = /^(\d+)x(\d+)@([\d.]+)$/.exec(spec.mode || "");
    if (mode) {
        out.width = +mode[1];
        out.height = +mode[2];
        out.refresh = round2(+mode[3]);
    }
    const pos = /^(-?\d+)x(-?\d+)$/.exec(spec.position || "");
    if (pos) {
        out.x = +pos[1];
        out.y = +pos[2];
    }
    if (spec.scale !== undefined) out.scale = spec.scale;
    if (spec.transform !== undefined) out.transform = spec.transform;
    return out;
}

function is_sideways(transform) {
    return transform % 2 === 1;
}

function rect_of(m) {
    const w = is_sideways(m.transform) ? m.height : m.width;
    const h = is_sideways(m.transform) ? m.width : m.height;
    return { x: m.x, y: m.y, w: Math.round(w / m.scale), h: Math.round(h / m.scale) };
}

function overlaps(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

function fits(rect, others) {
    return !others.some(o => overlaps(rect, o));
}

function axis_stops(rect, others, axis) {
    const pos = axis === "x" ? "x" : "y";
    const len = axis === "x" ? "w" : "h";
    const out = [];
    for (const o of others) {
        out.push(o[pos], o[pos] + o[len], o[pos] - rect[len], o[pos] + o[len] - rect[len]);
    }
    return out;
}

// Moves `rect` one press along dir ("h", "j", "k", "l") to the next neighbor-edge stop or a fixed step; null when a monitor is in the way.
function nudge(rect, others, dir, fine) {
    const axis = dir === "h" || dir === "l" ? "x" : "y";
    const len = axis === "x" ? "w" : "h";
    const sign = dir === "l" || dir === "j" ? 1 : -1;
    const cur = rect[axis];
    let target = cur + sign * (fine ? fine_step : nudge_step);
    if (!fine) {
        const stops = axis_stops(rect, others, axis).filter(s => (s - cur) * sign > 0);
        if (stops.length > 0) target = stops.reduce((a, b) => Math.abs(a - cur) <= Math.abs(b - cur) ? a : b);
    }
    const swept = Object.assign({}, rect);
    swept[axis] = Math.min(cur, target);
    swept[len] = rect[len] + Math.abs(target - cur);
    if (!fits(swept, others)) return null;
    const next = Object.assign({}, rect);
    next[axis] = target;
    return { x: next.x, y: next.y };
}

// Pulls a dragged rect to the nearest neighbor edges within reach; null when it would overlap another monitor.
function settle(rect, others) {
    const out = Object.assign({}, rect);
    for (const axis of ["x", "y"]) {
        let best = null;
        for (const s of axis_stops(rect, others, axis)) {
            if (Math.abs(s - rect[axis]) <= snap_reach && (best === null || Math.abs(s - rect[axis]) < Math.abs(best - rect[axis]))) best = s;
        }
        if (best !== null) out[axis] = best;
    }
    out.x = Math.round(out.x);
    out.y = Math.round(out.y);
    return fits(out, others) ? { x: out.x, y: out.y } : null;
}

function lua_string(text) {
    return JSON.stringify(text).replace(/\\u([0-9a-fA-F]{4})/g, "\\u{$1}");
}

function selector(m) {
    return m.description !== "" ? "desc:" + m.description : m.name;
}

function lua_rule(m, spec) {
    const fields = ["output=" + lua_string(selector(m))];
    if (spec.disabled) {
        fields.push("disabled=true");
    } else {
        fields.push("mode=" + lua_string(spec.mode), "position=" + lua_string(spec.position), "scale=" + lua_string(String(spec.scale)), "transform=" + (spec.transform | 0));
    }
    return "hl.monitor({" + fields.join(",") + "})";
}

// One Lua chunk for `hyprctl eval`; specs maps connector name to rule.
function lua_chunk(monitors, specs) {
    return monitors.filter(m => specs[m.name]).map(m => lua_rule(m, specs[m.name])).join(";");
}

// The state file entry for a spec; the flag tells the Hyprland config the key is a description.
function state_entry(m, spec) {
    const out = Object.assign({}, spec);
    if (m.description !== "") out.description = true;
    return out;
}

function transform_text(t) {
    return t === 0 ? "Normal" : t === 1 ? "90" : t === 2 ? "180" : t === 3 ? "270" : "Flipped " + (t - 4) * 90;
}

function resolutions(m) {
    const out = [];
    for (const mode of m.modes) {
        const text = mode.w + "x" + mode.h;
        if (out.indexOf(text) < 0) out.push(text);
    }
    const now = m.width + "x" + m.height;
    if (out.indexOf(now) < 0) out.unshift(now);
    return out;
}

function refreshes(m) {
    const out = m.modes.filter(x => x.w === m.width && x.h === m.height).map(x => x.r);
    if (out.indexOf(m.refresh) < 0) out.push(m.refresh);
    return out.sort((a, b) => b - a);
}

// The mode for a resolution, keeping the refresh when it exists and otherwise taking the highest.
function mode_for(m, res) {
    const parts = res.split("x");
    const w = +parts[0];
    const h = +parts[1];
    const rates = m.modes.filter(x => x.w === w && x.h === h).map(x => x.r).sort((a, b) => b - a);
    if (rates.length === 0) return null;
    return mode_string(w, h, rates.indexOf(m.refresh) >= 0 ? m.refresh : rates[0]);
}
