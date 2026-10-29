.pragma library

// Orders the window selection sends home/hypr/.config/hypr/lib/selection.lua makes, as the bar receives them:
// by generation (one per Hyprland config load, only ever growing), then by serial within it. Each send is its own
// qs-ipc process, so an older one can land last, and a reload restarts the serial. Pure, so node can test it.
// A state is { generation, serial, selected }; each function returns the next state, or null to keep the current one.

// A selection `{ generation, serial, windows }`, kept when it is newer than the last one applied.
function after_selection(state, spec) {
    const newer = spec.generation !== state.generation ? spec.generation > state.generation : spec.serial > state.serial;
    if (!newer) return null;
    return { generation: spec.generation, serial: spec.serial, selected: spec.windows.map(a => String(a).replace(/^0x/, "")) };
}

// A config load's clear: a new generation with nothing selected. One from a generation already seen (it lost a race
// to that load's first selection) or an older one changes nothing.
function after_clear(state, generation) {
    if (!(generation > state.generation)) return null;
    return { generation: generation, serial: 0, selected: [] };
}
