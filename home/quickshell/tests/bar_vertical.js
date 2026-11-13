// Runs VerticalLayout.js under node: the column a side-bar module may use, text that fits it and the stacked clock.
// Also BarLayout.js's lualine geometry down a column: section c and the mode chip.
// The scripts are QML `.pragma library` files, loaded with those lines stripped; BarLayout's `.import` of BarModules is
// stood in by loading that first.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const script = rel => fs.readFileSync(path.join(__dirname, "../.config/quickshell", rel), "utf8").replace(/^\.(pragma|import).*$/gm, "");
const L = vm.createContext({});
vm.runInContext(script("features/bar/VerticalLayout.js"), L);
const modules = vm.createContext({});
vm.runInContext(script("features/bar/BarModules.js"), modules);
const BL = vm.createContext({ BarModules: modules });
vm.runInContext(script("features/bar/BarLayout.js"), BL);
const island = (x, y, width, height, visible = true) => ({ x, y, width, height, visible });

// A text's metric: width = glyph_per_px * size + fixed (letter spacing).
const m = (glyph_per_px, fixed = 0) => ({ glyph_per_px, fixed });
const full = m(2.4);   // "100%" at 0.6 px advance per px per character
const short = m(1.8);  // "100"
const cases = [
  ["cross width is the bar less the pad", () => L.cross_width(34, 4), 30],
  ["cross width never goes negative", () => L.cross_width(3, 10), 0],
  ["text that fits keeps the base size", () => L.fit_size(m(1.8), 30, 14, 9), 14],
  ["text too wide shrinks to fit", () => L.fit_size(m(2.4), 24, 16, 9), 10],
  ["fit_size never goes below the minimum", () => L.fit_size(m(6), 10, 16, 9), 9],
  ["fit_size with no measure keeps the base", () => L.fit_size(m(0), 30, 14, 9), 14],
  ["letter spacing does not scale with the size: goldeneye's 4 x 1.5 px costs 6 px", () => L.fit_size(m(2.4, 6), 30, 14, 9), 10],
  ["the same text without spacing would have been given a bigger size", () => L.fit_size(m(2.4, 0), 30, 14, 9), 12],
  ["a base under the minimum is kept, not enlarged", () => L.fit_size(m(1), 40, 8, 9), 8],
  ["a base under the minimum is kept when the text does not fit either", () => L.fit_size(m(2.4), 12, 8, 9), 8],
  ["a fitted size is at or under the available width unless it sits on the floor", () => {
    for (let gpp = 0.5; gpp < 4; gpp += 0.5) for (let fixed = 0; fixed < 8; fixed += 1.5) for (let avail = 10; avail < 60; avail += 3) {
      const size = L.fit_size(m(gpp, fixed), avail, 21, 9);
      if (size > 9 && size * gpp + fixed > avail) return false;
    }
    return true;
  }, true],
  ["a fitting number keeps its unit", () => L.too_wide(m(2.4), 30, 14, 9), false],
  ["a number needing under the minimum drops its unit", () => L.too_wide(m(3.6), 30, 14, 9), true],
  ["letter spacing can tip a number into dropping its unit", () => L.too_wide(m(2.4, 10), 30, 14, 11), true],
  ["a base under the minimum is the floor for the unit drop", () => L.too_wide(m(2.4), 30, 8, 9), false],
  ["neovim's 18 px column: 100% drops to 100 at 10 px", () => L.fit_text(full, short, 18, 15, 9), { short: true, size: 10 }],
  ["a 28 px column keeps 100% at 11 px", () => L.fit_text(full, short, 28, 15, 9), { short: false, size: 11 }],
  ["a column wide enough keeps the base size and the unit", () => L.fit_text(full, short, 40, 14, 9), { short: false, size: 14 }],
  ["no short form: shrinks to the floor and keeps the text", () => L.fit_text(full, null, 18, 15, 9), { short: false, size: 9 }],
  ["a base under the minimum with no room: unit dropped, size stays the base", () => L.fit_text(m(2.4), m(1.8), 12, 8, 9), { short: true, size: 8 }],
  ["24-hour clock pads the hour", () => Array.from(L.clock_lines(7, 5, true)), ["07", "05"]],
  ["12-hour clock leaves the hour unpadded", () => Array.from(L.clock_lines(9, 41, false)), ["9", "41"]],
  ["12-hour midnight is 12", () => Array.from(L.clock_lines(0, 0, false)), ["12", "00"]],
  ["12-hour afternoon wraps", () => Array.from(L.clock_lines(15, 30, false)), ["3", "30"]],
  ["stack height adds spacing between parts", () => L.stack_height([16, 12], 2), 30],
  ["a hidden part adds no spacing", () => L.stack_height([16, 0, 12], 2), 30],
  ["an empty stack is flat", () => L.stack_height([], 2), 0],
  ["a single visible part has no spacing", () => L.stack_height([0, 12], 2), 12],
  ["lualine arrows are 0.4 of the bar, rounded", () => [BL.lualine_arrow(24), BL.lualine_arrow(34)], [10, 14]],
  ["the column mode chip is a square tile plus its arrow", () => BL.mode_chip_column_length(34), 48],
  // A 34 px column on a 1080 px screen: the a/b island is 120 tall at the top, the x/y/z island starts at 700.
  ["section c down a column runs from the a/b island's end to the x/y/z island", () => BL.lualine_c_extent(true, island(0, 0, 34, 120), island(0, 700, 34, 380), 0, 1080), { start: 120, end: 700 }],
  ["a column reads y and height, not x and width", () => BL.lualine_c_extent(true, island(5, 0, 34, 120), island(5, 700, 34, 380), 0, 1080), BL.lualine_c_extent(true, island(900, 0, 77, 120), island(900, 700, 77, 380), 0, 1080)],
  ["a row reads x and width", () => BL.lualine_c_extent(false, island(0, 0, 200, 24), island(1500, 0, 420, 24), 0, 1920), { start: 200, end: 1500 }],
  ["section c is in strip coordinates", () => BL.lualine_c_extent(false, island(40, 0, 200, 24), island(1500, 0, 380, 24), 40, 1880), { start: 200, end: 1460 }],
  ["with no a/b island section c starts at the strip's start", () => BL.lualine_c_extent(true, island(0, 0, 34, 120, false), island(0, 700, 34, 380), 0, 1080), { start: 0, end: 700 }],
  ["with no x/y/z island section c runs to the strip's end", () => BL.lualine_c_extent(true, island(0, 0, 34, 120), island(0, 700, 34, 380, false), 0, 1080), { start: 120, end: 1080 }],
];

let failed = 0;
for (const [name, run, want] of cases) {
  const got = run();
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { failed++; console.log(`FAIL ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); }
}
console.log(`${cases.length - failed}/${cases.length} passed`);
process.exit(failed ? 1 : 0);
