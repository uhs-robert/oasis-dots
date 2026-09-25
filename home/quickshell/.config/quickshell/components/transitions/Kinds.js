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

const durations = {
    fade: 450,
    blur: 600,
    crt: 820,
    flash: 700,
    palette: 600,
    mosaic: 640,
    flicker: 700,
    blocks: 650,
    towers: 850,
    visor: 800,
    iris: 900,
    grid: 700,
    trace: 800,
    cursor: 650,
    sunrise: 850
};

// Kinds that redraw the bar itself; the rest paint a cover clipped to the islands.
const texture_kinds = ["fade", "blur", "crt", "flash", "palette", "mosaic", "flicker"];

function kind_for(name) {
    if (name in durations) return name;
    return by_style[name] || "fade";
}

function duration(kind) {
    return durations[kind] || durations.fade;
}

function is_texture(kind) {
    return texture_kinds.indexOf(kind) >= 0;
}
