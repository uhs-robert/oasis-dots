.pragma library
.import "GameboySprites.js" as Gameboy
.import "NesSprites.js" as Nes
.import "SnesSprites.js" as Snes
.import "Ps1Sprites.js" as Ps1
.import "OasisVectors.js" as Oasis
.import "GoldeneyeVectors.js" as Goldeneye
.import "GoldeneyeGadgetVectors.js" as GoldeneyeGadgets
.import "MetroidVectors.js" as Metroid
.import "Ff7Vectors.js" as Ff7
.import "CrtVectors.js" as Crt
.import "Ps2Vectors.js" as Ps2
.import "HalflifeVectors.js" as Halflife
.import "TieVectors.js" as Tie
.import "ReticleVectors.js" as Reticle
.import "ModernVectors.js" as Modern
.import "TerminalEmoji.js" as Terminal

// Icon sets a bar style can draw in place of the Nerd Font glyphs: set name -> icon name -> variant -> sprite rows or vector.
var sets = {
    "gameboy": Gameboy.sprites,
    "nes": Nes.sprites,
    "snes": Snes.sprites,
    "ps1": Ps1.sprites,
    "oasis": Oasis.vectors,
    "goldeneye": Goldeneye.vectors,
    "goldeneye_gadgets": GoldeneyeGadgets.vectors,
    "metroid": Metroid.vectors,
    "ff7": Ff7.vectors,
    "crt": Crt.vectors,
    "ps2": Ps2.vectors,
    "halflife": Halflife.vectors,
    "tie": Tie.vectors,
    "reticle": Reticle.vectors,
    "modern": Modern.vectors,
    "terminal": Terminal.icons
};

var names = Object.keys(sets);

// An entry is sprite rows (an array of strings), a vector { w, h, body, accent?, fill_rule? } drawn on a viewBox w wide and h (24) tall, or text { text, font? } such as an emoji.
function entry(set, name, variant) {
    const table = sets[set];
    const icon = table ? table[name] : undefined;
    return icon ? icon[variant] : undefined;
}

// The sprite rows, or null when the module should draw its glyph: no set, an icon or variant the set lacks, one not drawn yet (an empty array), a vector or text.
function sprite(set, name, variant) {
    const rows = entry(set, name, variant);
    return Array.isArray(rows) && rows.length > 0 ? rows : null;
}

// The vector entry, or null when the set has no vector for this icon and variant. An entry may be all accent (every segment lit), with an empty body.
function vector(set, name, variant) {
    const drawn = entry(set, name, variant);
    return drawn && !Array.isArray(drawn) && (drawn.body || drawn.accent) ? drawn : null;
}

// The text entry { text, font? }, or null when the set has no text for this icon and variant.
function text(set, name, variant) {
    const drawn = entry(set, name, variant);
    return drawn && !Array.isArray(drawn) && drawn.text ? drawn : null;
}

// The longest text among all of an icon's variants, which a fixed slot measures to stay as wide as its widest variant, or "" when the set draws no text for it.
function widest_text(set, name) {
    const table = sets[set];
    const icon = table ? table[name] : undefined;
    let widest = "";
    for (const variant in icon) {
        const drawn = icon[variant];
        if (drawn && drawn.text && drawn.text.length > widest.length) widest = drawn.text;
    }
    return widest;
}

// The widest and tallest sprite among all of an icon's variants, in sprite pixels, or null when the set does not draw it.
function extent(set, name) {
    const table = sets[set];
    const icon = table ? table[name] : undefined;
    if (!icon) return null;
    let columns = 0;
    let height = 0;
    for (const variant in icon) {
        const rows = icon[variant];
        if (!Array.isArray(rows) || rows.length === 0) continue;
        columns = Math.max(columns, rows[0].length);
        height = Math.max(height, rows.length);
    }
    return columns > 0 ? { columns: columns, rows: height } : null;
}

// The widest and tallest vector among all of an icon's variants, in viewBox units, or null when the set draws no vector for it.
function vector_extent(set, name) {
    const table = sets[set];
    const icon = table ? table[name] : undefined;
    if (!icon) return null;
    let width = 0;
    let height = 0;
    for (const variant in icon) {
        const drawn = icon[variant];
        if (!drawn || Array.isArray(drawn) || !(drawn.body || drawn.accent)) continue;
        width = Math.max(width, drawn.w);
        height = Math.max(height, drawn.h);
    }
    return width > 0 ? { w: width, h: height } : null;
}
