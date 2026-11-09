.pragma library

// The pure half of the lock's load guard (LoadGuard.qml, AgentCpuCap.qml): reading /proc and /sys text, deciding
// when a busy machine stills the lock, and the agents.slice CPU quota to set while locked.

const sample_ms = 5000;
const window_samples = 30000 / sample_ms;
// CPU threads the agents.slice cgroup keeps busy, as a share of all threads. The gap between enter and leave keeps
// the lock from flapping around one value.
const enter_agents = 0.25;
const leave_agents = 0.125;
// Load1 per thread, used only where agents.slice has no cpu.stat (the agents package is not installed).
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

// The real uid from /proc/self/status, or "".
function status_uid(status_text) {
    const m = /^Uid:\s+(\d+)/m.exec(status_text || "");
    return m ? m[1] : "";
}

// The cgroup v2 cpu.stat of the user's agents.slice, under `sys_root` (the test seam, "" for the real one).
function agents_cpu_stat_path(sys_root, uid) {
    if (uid === "") return "";
    return sys_root + "/sys/fs/cgroup/user.slice/user-" + uid + ".slice/user@" + uid + ".service/agents.slice/cpu.stat";
}

// cpu.stat's usage_usec, or NaN.
function usage_usec(stat_text) {
    const m = /^usage_usec\s+(\d+)\s*$/m.exec(stat_text || "");
    return m ? parseInt(m[1]) : NaN;
}

// The threads' share agents.slice kept busy between two readings `{ usec, ms }` (usage_usec and wall time). NaN for a
// first reading, a missing one, or a counter that went back (the slice was recreated), rather than a spike.
function agents_ratio(prev, next, threads) {
    if (!prev || !next || !isFinite(prev.usec) || !isFinite(next.usec) || !(threads > 0)) return NaN;
    const used_ms = (next.usec - prev.usec) / 1000;
    const wall_ms = next.ms - prev.ms;
    if (used_ms < 0 || !(wall_ms > 0)) return NaN;
    return used_ms / wall_ms / threads;
}

function initial() {
    return { still: false, trigger: "", agents: [], loads: [], powers: [] };
}

function mean(values) {
    const known = values.filter(v => isFinite(v));
    if (known.length === 0) return NaN;
    return known.reduce((a, b) => a + b, 0) / known.length;
}

// One sample `{ agents, load, power }` (ratios, NaN when unknown) into a new state. The decision uses the mean of the
// last window_samples, and only once the window is full, so the lock changes after about 30 s of a load, not one
// spike. Agent CPU decides when the window holds any of it; the load average stands in where agents.slice is absent.
// `trigger` names what the last change went on: agents, load or power.
function step(state, sample) {
    const keep = list => list.slice(-(window_samples - 1));
    const next = {
        still: state.still,
        trigger: state.trigger,
        agents: keep(state.agents).concat([sample.agents]),
        loads: keep(state.loads).concat([sample.load]),
        powers: keep(state.powers).concat([sample.power])
    };
    if (next.loads.length < window_samples) return next;
    const agents = mean(next.agents);
    const use_agents = isFinite(agents);
    const cpu = use_agents ? agents : mean(next.loads);
    const cpu_name = use_agents ? "agents" : "load";
    const power = mean(next.powers);
    const cpu_heavy = cpu >= (use_agents ? enter_agents : enter_load);
    const calm = !(cpu >= (use_agents ? leave_agents : leave_load)) && !(power >= leave_power);
    if (!next.still && (cpu_heavy || power >= enter_power)) {
        next.still = true;
        next.trigger = cpu_heavy ? cpu_name : "power";
    } else if (next.still && calm) {
        next.still = false;
        next.trigger = cpu_name;
    }
    return next;
}

// The value of an X- key from `systemctl --user cat agents.slice` (X-LockedCPUQuota, X-UnlockedCPUQuota) as a percent
// of all threads, or NaN when the key is absent, empty or not a percentage in (0, 100]. The last assignment wins as
// in systemd, and an empty one unsets it.
function share(unit_text, key) {
    let value = "";
    for (const line of (unit_text || "").split("\n")) {
        const m = new RegExp("^\\s*" + key + "\\s*=\\s*(.*?)\\s*$").exec(line);
        if (m) value = m[1];
    }
    const m = /^(\d+(?:\.\d+)?)%?$/.exec(value);
    const percent = m ? parseFloat(m[1]) : NaN;
    return percent > 0 && percent <= 100 ? percent : NaN;
}

// The share of `key` as a CPUQuota percent of the thread count (62% of 16 threads is 992), NaN without a share or threads.
function share_quota(unit_text, threads, key) {
    const percent = share(unit_text, key);
    if (!isFinite(percent) || !(threads > 0)) return NaN;
    return Math.max(1, Math.round(percent * threads));
}

// The quota percent of the CPUQuota the user configured, NaN for none.
function configured_percent(unit_text) {
    const m = /^(\d+(?:\.\d+)?)%$/.exec(configured_quota(unit_text));
    const percent = m ? parseFloat(m[1]) : NaN;
    return percent > 0 ? percent : NaN;
}

// The smallest of the numbers that are real, NaN when none is.
function tightest(...values) {
    const real = values.filter(isFinite);
    return real.length ? Math.min(...real) : NaN;
}

// The CPUQuota agents.slice should have now, e.g. "992%", or null to leave it alone. set-property replaces a quota the
// user configured rather than adding a ceiling, so a tighter configured quota wins in both states. Locked is the
// locked share, never above the unlocked share. Unlocked is the unlocked share. Without an unlocked share the unlock
// restores the configured quota ("" clears ours), but only when a cap of ours may be in place: this bar set one
// (`capped`) or a locked share exists, which a bar that died while locked used. Threads not read yet give null, so
// nothing is applied until they arrive.
function slice_quota(unit_text, threads, locked, capped) {
    const configured = configured_percent(unit_text);
    const unlocked = share_quota(unit_text, threads, "X-UnlockedCPUQuota");
    if (locked) {
        const own = share_quota(unit_text, threads, "X-LockedCPUQuota");
        return isFinite(own) ? tightest(own, unlocked, configured) + "%" : null;
    }
    if (isFinite(unlocked)) return tightest(unlocked, configured) + "%";
    if (isFinite(share(unit_text, "X-UnlockedCPUQuota"))) return null;
    const may_hold_ours = capped || isFinite(share(unit_text, "X-LockedCPUQuota"));
    return may_hold_ours ? configured_quota(unit_text) : null;
}

// The CPUQuota the user configured for agents.slice, for the unlock to put back: the last `CPUQuota=` in `systemctl
// --user cat` outside the control drop-ins that `systemctl set-property` writes (ours among them), "" for none.
function configured_quota(unit_text) {
    let ours = false;
    let value = "";
    for (const line of (unit_text || "").split("\n")) {
        const file = /^# (\/\S+)\s*$/.exec(line);
        if (file) {
            ours = file[1].indexOf("/systemd/user.control/") >= 0 || /\/50-CPUQuota\.conf$/.test(file[1]);
            continue;
        }
        const m = /^\s*CPUQuota\s*=\s*(.*?)\s*$/.exec(line);
        if (m && !ours) value = m[1];
    }
    return value;
}
