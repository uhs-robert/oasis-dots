.pragma library

// The Resident Evil condition look for an agent session's state, shared by the keeptabs Condition screen and the
// agent picker's cards. The word is always the session's own state, so the screen never makes you translate a game
// term back. Idle, and any state keeptabs-hook adds later, shows in grey with a flat line instead of a guessed beat.
// The picker relabels "running" as "working", so both names take the running beat.
function look(state, colors) {
    var s = state || "idle";
    var running = { color: colors.ok, beat: "running", ms: 1000 };
    var by_state = {
        waiting: { color: colors.warning, beat: "waiting", ms: 1500 },
        running: running,
        working: running,
        done: { color: colors.info, beat: "done", ms: 2400 }
    };
    var found = by_state[s] || { color: colors.dim, beat: "idle", ms: 0 };
    return { word: s.toUpperCase(), color: found.color, beat: found.beat, ms: found.ms };
}
