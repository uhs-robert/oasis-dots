// Runs VerticalLayout.js under node: the column a side-bar module may use, text that fits it and the stacked clock.
// The script is a QML `.pragma library` file, loaded with that line stripped.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const src = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/bar/VerticalLayout.js"), "utf8").replace(/^\.(pragma|import).*$/gm, "");
const L = vm.createContext({});
vm.runInContext(src, L);

const advance = 0.6;
const cases = [
  ["cross width is the bar less the pad", () => L.cross_width(34, 4), 30],
  ["cross width never goes negative", () => L.cross_width(3, 10), 0],
  ["text that fits keeps the base size", () => L.fit_size(3, advance, 30, 14, 9), 14],
  ["text too wide shrinks to fit", () => L.fit_size(4, advance, 24, 16, 9), 10],
  ["fit_size never goes below the minimum", () => L.fit_size(10, advance, 10, 16, 9), 9],
  ["fit_size with no characters keeps the base", () => L.fit_size(0, advance, 30, 14, 9), 14],
  ["every width and length stays at or above the minimum", () => {
    for (let chars = 1; chars < 12; chars++) for (let avail = 0; avail < 60; avail += 3) if (L.fit_size(chars, advance, avail, 21, 9) < 9) return false;
    return true;
  }, true],
  ["a fitting number keeps its unit", () => L.too_wide(4, advance, 30, 9), false],
  ["a number needing under the minimum drops its unit", () => L.too_wide(6, advance, 30, 9), true],
  ["24-hour clock pads the hour", () => Array.from(L.clock_lines(7, 5, true)), ["07", "05"]],
  ["12-hour clock leaves the hour unpadded", () => Array.from(L.clock_lines(9, 41, false)), ["9", "41"]],
  ["12-hour midnight is 12", () => Array.from(L.clock_lines(0, 0, false)), ["12", "00"]],
  ["12-hour afternoon wraps", () => Array.from(L.clock_lines(15, 30, false)), ["3", "30"]],
  ["stack height adds spacing between parts", () => L.stack_height([16, 12], 2), 30],
  ["a hidden part adds no spacing", () => L.stack_height([16, 0, 12], 2), 30],
  ["an empty stack is flat", () => L.stack_height([], 2), 0],
  ["a stack in a column: icon over number fits the cross width's height budget", () => L.stack_height([14, 12], 2) <= 34, true],
];

let failed = 0;
for (const [name, run, want] of cases) {
  const got = run();
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { failed++; console.log(`FAIL ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); }
}
console.log(`${cases.length - failed}/${cases.length} passed`);
process.exit(failed ? 1 : 0);
