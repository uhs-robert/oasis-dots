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
    reticle: "trace"
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

// Styles whose popups swap (a hover moving from one module's popup to the next) with their own transition; the rest
// resize and crossfade ("fade"). A swap plays the transition at `scale` of its length.
const swap_styles = ["crt", "goldeneye", "nes", "gameboy", "snes", "ps1", "ff7", "halflife"];

function swap_kind(style) {
    return { kind: swap_styles.indexOf(style) >= 0 ? kind_for(style) : "fade", scale: 0.5 };
}
