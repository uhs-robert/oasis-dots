// Runs SettingsScale.js under node: the text bump over the screen height, the row pitch it adds and the color lift.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/settings/SettingsScale.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { text_bump, pitch_extra, bump_of, lifted, fitted_bump, fit_zoom };", T);
const S = T.api;

const rgb = hex => ({ r: ((hex >> 16) & 255) / 255, g: ((hex >> 8) & 255) / 255, b: (hex & 255) / 255, a: 1 });
// Game Boy: text_dim and section_fg are both the second-brightest shade, text_fg the next.
const gb_dim = rgb(0x306230);
const gb_fg = rgb(0x0f380f);
const mid = (a, b) => [(a.r + b.r) / 2, (a.g + b.g) / 2, (a.b + b.b) / 2, 1];

const cases = [
  ["no bump at 1080p", () => S.text_bump(1080), 0],
  ["no bump below 1080p", () => [S.text_bump(1024), S.text_bump(720), S.text_bump(0), S.text_bump(undefined), S.text_bump(NaN)], [0, 0, 0, 0, 0]],
  ["no pitch change without a bump", () => S.pitch_extra(0), 0],
  ["one pixel over 1080p already rounds to none", () => S.text_bump(1081), 0],
  ["1440p gets +2", () => S.text_bump(1440), 2],
  ["portrait 1920 and 4K stay at the +3 ceiling", () => [S.text_bump(1920), S.text_bump(2160), S.text_bump(4320)], [3, 3, 3]],
  ["the bump never shrinks as the screen grows", () => { let prev = 0; for (let h = 0; h <= 4320; h += 10) { const b = S.text_bump(h); if (b < prev) return h; prev = b; } return "ok"; }, "ok"],
  ["a bump adds two pitch px per font px", () => S.pitch_extra(3), 6],
  ["bump_of reads the nearest ancestor", () => S.bump_of({ parent: { text_bump: 2, parent: { text_bump: 9 } } }), 2],
  ["bump_of outside Settings is 0", () => [S.bump_of({ parent: { parent: null } }), S.bump_of(null)], [0, 0]],
  ["fitted_bump never exceeds the wanted bump", () => { for (let wanted = 0; wanted <= 3; wanted++) for (let avail = 0; avail <= 3000; avail += 50) if (S.fitted_bump(wanted, 22, 6, 30, 16, avail) > wanted) return [wanted, avail]; return "ok"; }, "ok"],
  ["fitted_bump keeps the wanted bump when the list fits with room to spare", () => S.fitted_bump(3, 22, 6, 30, 16, 100000), 3],
  ["fitted_bump steps down when the wanted bump would not fit", () => S.fitted_bump(3, 22, 6, 30, 16, 1000) < 3, true],
  ["fitted_bump is 0 when nothing is wanted", () => [S.fitted_bump(0, 22, 6, 30, 16, 100000), S.fitted_bump(0, 22, 6, 30, 16, 0)], [0, 0]],
  ["fitted_bump is 0 when even the unbumped list does not fit", () => S.fitted_bump(3, 22, 6, 30, 16, 100), 0],
  ["fitted_bump never shrinks as the body grows", () => { let prev = 0; for (let avail = 0; avail <= 3000; avail += 10) { const b = S.fitted_bump(3, 22, 6, 30, 16, avail); if (b < prev) return avail; prev = b; } return "ok"; }, "ok"],
  ["lift by nothing leaves the base untouched", () => S.lifted(gb_dim, gb_fg, 0), [gb_dim.r, gb_dim.g, gb_dim.b, 1]],
  ["Game Boy group label: halfway to text_fg", () => S.lifted(gb_dim, gb_fg, 0.5), mid(gb_dim, gb_fg)],
  ["Game Boy value: 60% of the way to text_fg", () => S.lifted(gb_dim, gb_fg, 0.6).map(v => +v.toFixed(6)), [gb_dim.r + (gb_fg.r - gb_dim.r) * 0.6, gb_dim.g + (gb_fg.g - gb_dim.g) * 0.6, gb_dim.b + (gb_fg.b - gb_dim.b) * 0.6, 1].map(v => +v.toFixed(6))],
  ["the Game Boy blend differs from both inputs", () => { const c = S.lifted(gb_dim, gb_fg, 0.5); return c[0] !== gb_dim.r && c[0] !== gb_fg.r; }, true],
  ["alpha blends too", () => S.lifted({ r: 0, g: 0, b: 0, a: 0.5 }, { r: 1, g: 1, b: 1, a: 1 }, 0.5), [0.5, 0.5, 0.5, 0.75]],
  // req: MEDIASETTINGS-08
  ["the media preview keeps its zoom when the pane has room", () => S.fit_zoom(2, 1000, 300), 2],
  ["the media preview shrinks to the pane's width, below half size too", () => [S.fit_zoom(2, 300, 300), S.fit_zoom(2, 90, 300)], [1, 0.3]],
  ["a pane with no width yet shows nothing rather than spilling", () => S.fit_zoom(2, 0, 300), 0],
  ["nothing measured yet keeps the wanted zoom", () => S.fit_zoom(2, 500, 0), 2],
];

let failed = 0;
for (const [name, run, want] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(run())), want);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}
if (failed) process.exit(1);
console.log("settings scale: " + cases.length + " checks passed");
