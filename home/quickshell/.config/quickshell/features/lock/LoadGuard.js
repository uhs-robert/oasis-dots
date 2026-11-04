.pragma library

// The pure half of the lock's load guard (LoadGuard.qml, AgentCpuCap.qml): reading /proc and /sys text, deciding
// when a busy machine stills the lock, and the agents.slice CPU quota to set while locked.

const sample_ms = 5000;
const window_samples = 30000 / sample_ms;
// Load1 per thread. The gap between enter and leave keeps the lock from flapping around one value.
const enter_load = 0.75;
const leave_load = 0.5;
// PPT as a share of power1_cap. The leave level sits well below enter because the lock's own motion is part of PPT:
// going still drops it by the skin's GPU share, which must not count as the machine calming down.
const enter_power = 0.9;
const leave_power = 0.75;

// "0-15" or "0-3,6,8-9" (sysfs cpu lists) to a count; 0 when unreadable.
function thread_count(online_text) {
    const text = (online_text || "").trim();
    if (text === "") return 0;
    let count = 0;
    for (const part of text.split(",")) {
        const m = /^(\d+)(?:-(\d+))?$/.exec(part.trim());
        if (!m) return 0;
        const first = parseInt(m[1]);
        const last = m[2] === undefined ? first : parseInt(m[2]);
        if (last < first) return 0;
        count += last - first + 1;
    }
    return count;
}

// /proc/loadavg's one-minute load per thread, or NaN.
function load_ratio(loadavg_text, threads) {
    const load1 = parseFloat((loadavg_text || "").trim().split(/\s+/)[0]);
    if (!(threads > 0) || !isFinite(load1)) return NaN;
    return load1 / threads;
}

// hwmon power1_input over power1_cap (both microwatts), or NaN when either is missing.
function power_ratio(input_text, cap_text) {
    const input = parseFloat((input_text || "").trim());
    const cap = parseFloat((cap_text || "").trim());
    if (!isFinite(input) || !(cap > 0)) return NaN;
    return input / cap;
}

function initial() {
    return { still: false, loads: [], powers: [] };
}

function mean(values) {
    const known = values.filter(v => isFinite(v));
    if (known.length === 0) return NaN;
    return known.reduce((a, b) => a + b, 0) / known.length;
}

// One sample `{ load, power }` (ratios, NaN when unknown) into a new state. The decision uses the mean of the last
// window_samples, and only once the window is full, so the lock changes after about 30 s of a load, not one spike.
function step(state, sample) {
    const keep = list => list.slice(-(window_samples - 1));
    const loads = keep(state.loads).concat([sample.load]);
    const powers = keep(state.powers).concat([sample.power]);
    let still = state.still;
    if (loads.length >= window_samples) {
        const load = mean(loads);
        const power = mean(powers);
        const heavy = load >= enter_load || power >= enter_power;
        const calm = !(load >= leave_load) && !(power >= leave_power);
        if (!still && heavy) still = true;
        else if (still && calm) still = false;
    }
    return { still: still, loads: loads, powers: powers };
}

// The CPUQuota for agents.slice while locked, from `systemctl --user cat agents.slice`: X-LockedCPUQuota (percent of
// all threads, the last assignment winning as in systemd, an empty one unsetting it) times the thread count, e.g.
// "992%" for 62% of 16. "" when the key is absent, empty or not a percentage.
function locked_quota(unit_text, threads) {
    let value = "";
    for (const line of (unit_text || "").split("\n")) {
        const m = /^\s*X-LockedCPUQuota\s*=\s*(.*?)\s*$/.exec(line);
        if (m) value = m[1];
    }
    const m = /^(\d+(?:\.\d+)?)%?$/.exec(value);
    if (!m || !(threads > 0)) return "";
    const percent = parseFloat(m[1]);
    if (!(percent > 0) || percent > 100) return "";
    return Math.max(1, Math.round(percent * threads)) + "%";
}
