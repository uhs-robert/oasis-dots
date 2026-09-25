.pragma library

// Style name to transition kind; anything unmapped plays "fade".
const by_style = {
    oasis: "sunrise",
    modern: "blur",
    neovim: "cursor",
    terminal: "cursor",
    crt: "crt",
    nes: "blocks",
    gameboy: "palette",
    snes: "mosaic",
    ps1: "flash",
    ff7: "flash",
    goldeneye: "iris",
    ps2: "towers",
    tie: "grid",
    halflife: "flicker",
    metroid: "visor",
    oblivion: "trace",
    mech: "trace"
};

// [cover, reveal] in ms: the old look is covered, the style swaps, then the new one is revealed.
const durations = {
    fade: [200, 300],
    blur: [250, 400],
    crt: [330, 470],
    flash: [250, 500],
    palette: [300, 400],
    mosaic: [300, 450],
    flicker: [300, 500],
    blocks: [300, 450],
    towers: [350, 550],
    visor: [350, 550],
    iris: [400, 500],
    grid: [300, 450],
    trace: [350, 500],
    cursor: [300, 400],
    sunrise: [400, 600]
};

// Kinds that redraw the bar itself; the rest paint a cover clipped to the islands.
const texture_kinds = ["fade", "blur", "crt", "flash", "palette", "mosaic", "flicker"];

function kind_for(name) {
    if (name in durations) return name;
    return by_style[name] || "fade";
}

function cover(kind) {
    return (durations[kind] || durations.fade)[0];
}

function reveal(kind) {
    return (durations[kind] || durations.fade)[1];
}

function is_texture(kind) {
    return texture_kinds.indexOf(kind) >= 0;
}
