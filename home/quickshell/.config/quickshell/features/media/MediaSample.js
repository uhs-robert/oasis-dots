.pragma library

// The made-up track Settings > Media previews when no player has one, pure so a node test covers it.

// Whether a preview shows the live player rather than the sample: one that plays, or one paused on a track. No player,
// a stopped one or one with no title and artist (nothing the text options could change) gets the sample, so every
// option still shows its effect.
function uses_live(present, playing, stopped, title, artist) {
    if (!present) return false;
    if (playing) return true;
    return !stopped && !!(title || artist);
}

// The sample's visualizer at `t` seconds: `count` levels in 0..1 from a few drifting sines, louder in the low bands,
// so the bars and the line move the way music does. Never 0 or 1, so both ends of a bar's range stay readable.
function levels(t, count) {
    const out = [];
    for (let i = 0; i < count; i++) {
        const x = count <= 1 ? 0 : i / (count - 1);
        const wave = Math.sin(t * 2.3 + x * 9) * 0.5 + Math.sin(t * 3.7 - x * 17) * 0.3 + Math.sin(t * 1.1 + x * 4) * 0.2;
        const level = (0.55 - x * 0.25) + wave * 0.35;
        out.push(Math.max(0.04, Math.min(0.96, level)));
    }
    return out;
}

// The sample's position at `t` seconds into a track `length` seconds long, starting over at the end.
function position(t, length) {
    if (!(length > 0)) return 0;
    return ((t % length) + length) % length;
}
