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
