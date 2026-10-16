.pragma library

// Party-menu mini sprites per agent, rows of PixelSprite shade digits: claude is a spark, codex a terminal prompt.
const claude = [
    "....3....",
    ".3..3..3.",
    "..3.3.3..",
    "...333...",
    "333323333",
    "...333...",
    "..3.3.3..",
    ".3..3..3.",
    "....3...."
];

const codex = [
    ".33333333.",
    "3........3",
    "3.3......3",
    "3..3.....3",
    "3.3......3",
    "3....333.3",
    "3........3",
    ".33333333."
];

function sprite(agent) {
    return agent === "codex" ? codex : claude;
}
