.pragma library

// Pure helpers for CavaState and the frame cava (CavaWave, CavaRim), kept apart so tests/island_shapes.js can run them.

// Below this bass the rim is hidden, and below this peak a level counts as silence.
var SILENT = 0.03;
// Playing but silent this long folds the frame cava away; any sound unfolds it.
var FOLD_MS = 8000;
var BASS_BARS = 6;

// cava's lowest bars carry the kick; the 1.15 gain lets a hot track reach the top of the range.
function bass_of(levels) {
    var sum = 0;
    for (var i = 0; i < BASS_BARS; i++) sum += levels[i] || 0;
    return Math.min(1, Math.max(0, sum / BASS_BARS * 1.15));
}

// Fast rise, slow fall: a rim that followed the raw bass would flicker between beats.
function step_bass(current, target, dt) {
    var k = target > current ? 40 : 7;
    return current + (target - current) * (1 - Math.exp(-k * dt));
}

function peak_of(levels) {
    var peak = 0;
    for (var i = 0; i < levels.length; i++) peak = Math.max(peak, levels[i] || 0);
    return peak;
}

// The accumulated quiet time after one tick of dt ms: grows while the peak stays below SILENT, resets on any sound.
function quiet_after(quiet_ms, levels, dt) {
    return peak_of(levels) < SILENT ? quiet_ms + dt : 0;
}

// The wave and the cava line both read the smoothed line levels, which are only computed when one of them is on.
function smoothing_wanted(cava_line, cava_visual_effective) {
    return cava_line || cava_visual_effective === "wave";
}

function rim_width(bass) {
    return 2 + bass * 7;
}

function rim_alpha(bass) {
    return 0.5 + 0.5 * bass;
}

// The wave's polyline across `width` and the closed fill under it; `flipped` mirrors it for a bottom bar, which hangs
// from the top edge. Points are [x, y] pairs.
function wave_points(levels, width, height, amp, flipped) {
    var n = levels.length, line = [];
    for (var i = 0; i < n; i++) {
        var x = n <= 1 ? 0 : i / (n - 1) * width;
        var rise = (levels[i] || 0) * amp;
        line.push([x, flipped ? 1 + rise : height - 1 - rise]);
    }
    var edge = flipped ? 0 : height;
    return { line: line, fill: line.concat([[width, edge], [0, edge]]) };
}
