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
    "halflife": Halflife.vectors
};

var names = Object.keys(sets);

// An entry is either sprite rows (an array of strings) or a vector: { w, h, body, accent?, fill_rule? }, drawn on a viewBox w wide and h (24) tall.
function entry(set, name, variant) {
    const table = sets[set];
    const icon = table ? table[name] : undefined;
    return icon ? icon[variant] : undefined;
}

// The sprite rows, or null when the module should draw its glyph: no set, an icon or variant the set lacks, one not drawn yet (an empty array), or a vector.
function sprite(set, name, variant) {
    const rows = entry(set, name, variant);
    return Array.isArray(rows) && rows.length > 0 ? rows : null;
}

// The vector entry, or null when the set has no vector for this icon and variant. An entry may be all accent (every segment lit), with an empty body.
function vector(set, name, variant) {
    const drawn = entry(set, name, variant);
    return drawn && !Array.isArray(drawn) && (drawn.body || drawn.accent) ? drawn : null;
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
