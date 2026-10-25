.pragma library

// The room the center island's cava tail may take below its modules on a side bar: from the modules' end (the island
// is centred by the modules alone, so the tail never moves them) to the bottom island, less `gap`.
function free_space(screen_length, module_length, bottom_length, bottom_inset, gap) {
    const modules_end = (screen_length + module_length) / 2;
    return screen_length - bottom_length - bottom_inset - gap - modules_end;
}

// The tail at full growth: what it wants, cut to the free room; none on a top or bottom bar.
function tail_target(vertical, wanted, free) {
    return vertical ? Math.max(0, Math.min(wanted, free)) : 0;
}

// The tail now: follows the bars' fade (`fade` 0..1, the bars' own animated opacity) so both start and stop together.
function tail_span(target, fade) {
    return target * Math.max(0, Math.min(1, fade));
}
