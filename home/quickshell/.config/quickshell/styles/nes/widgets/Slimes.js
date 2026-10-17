.pragma library

// Dragon Quest slimes, shared by the NES weather Daily tower and the Slime Party workspaces.
// Rows index the NES weather palette (popups/weather/NesSprites.js): 0 outline, 1 eye white, 2 crown gold, 4 body, 5 shine, 7 jewel red; "." is clear.
// Recolouring 4 and 5 makes the other slimes. var, not const: QML only sees a library's var and function declarations.
var SIZE = 12;

var SLIME = [
    "......0.....",
    ".....040....",
    "....0440....",
    "...045440...",
    "..04544440..",
    ".0454444440.",
    "044114411440",
    "044104410440",
    "044044440440",
    "044400004440",
    ".0444444440.",
    "..00000000.."
];

// The curl gives way to a gold crown.
var KING_SLIME = [
    "...0.00.0...",
    "..02022020..",
    "..02222220..",
    "..02722720..",
    "..02222220..",
    ".0454444440.",
    "044114411440",
    "044104410440",
    "044044440440",
    "044400004440",
    ".0444444440.",
    "..00000000.."
];
