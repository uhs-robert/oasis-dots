.pragma library
.import "GameboySprites.js" as Gameboy

// Pixel icon sets a bar style can draw in place of the Nerd Font glyphs: set name -> icon name -> variant -> sprite rows.
var sets = {
    "gameboy": Gameboy.sprites
};

var names = Object.keys(sets);

// The sprite rows, or null when the module should draw its glyph: no set, an icon or variant the set lacks, or one not drawn yet (an empty array).
function sprite(set, name, variant) {
    const table = sets[set];
    const icon = table ? table[name] : undefined;
    const rows = icon ? icon[variant] : undefined;
    return rows && rows.length > 0 ? rows : null;
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
        if (!rows || rows.length === 0) continue;
        columns = Math.max(columns, rows[0].length);
        height = Math.max(height, rows.length);
    }
    return columns > 0 ? { columns: columns, rows: height } : null;
}
