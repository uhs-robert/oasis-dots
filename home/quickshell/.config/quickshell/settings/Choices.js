.pragma library

// A row's preset steps plus the current value when it is off the presets, kept in order.
function with_current(steps, current) {
    if (current === undefined || steps.indexOf(current) >= 0) return steps;
    return steps.concat([current]).sort((a, b) => a - b);
}
