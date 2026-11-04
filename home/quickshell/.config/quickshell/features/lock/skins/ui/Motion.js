.pragma library

// Keyframe tracks for the skins' looping motion, evaluated from a MotionClock instead of run as Animations.

// Qt's curves of the same names (QEasingCurve), on 0..1.
const eases = {
    linear: x => x,
    in_quad: x => x * x,
    out_quad: x => x * (2 - x),
    in_out_quad: x => x < 0.5 ? 2 * x * x : 1 - 2 * (1 - x) * (1 - x),
    in_cubic: x => x * x * x,
    out_cubic: x => 1 + Math.pow(x - 1, 3),
    in_out_sine: x => (1 - Math.cos(Math.PI * x)) / 2,
    out_back: x => {
        const s = 1.70158, y = x - 1;
        return y * y * ((s + 1) * y + s) + 1;
    }
};

function ease(name, x) {
    return (eases[name] || eases.linear)(Math.max(0, Math.min(1, x)));
}

// The value `ms` into a track that repeats forever. keys: [[duration_ms, to, ease], ...], each segment running from the
// one before. The first pass starts at `first`; later passes start at the last key's value, as an infinite
// SequentialAnimation of NumberAnimations without `from` does. A key with to === null holds the value (a pause).
function track(ms, keys, first) {
    if (!keys || keys.length === 0) return first;
    let total = 0;
    for (const k of keys) total += k[0];
    const last = keys.reduce((v, k) => k[1] === null ? v : k[1], first);
    let at = ms;
    let from = first;
    if (total > 0 && ms >= total) {
        at = ms % total;
        from = last;
    }
    for (const k of keys) {
        const to = k[1] === null ? from : k[1];
        if (at < k[0]) return from + (to - from) * ease(k[2], at / k[0]);
        at -= k[0];
        from = to;
    }
    return from;
}

// The fraction 0..1 through a repeating period, `s` seconds in.
function cycle(s, period) {
    return period > 0 ? ((s % period) + period) % period / period : 0;
}
