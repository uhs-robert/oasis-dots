// Runs MediaText.js under node: the media well's text rules and its marquee gate.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/bar/MediaText.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { clip, lines, format_time, ratio, marquee_running, marquee_cycle, stacked_sizes };", T);
const M = T.api;
const plain = v => JSON.parse(JSON.stringify(v));

const cases = [
  ["short text is not cut", () => M.clip("abc", 5), "abc"],
  ["text at the cap is not cut", () => M.clip("abcde", 5), "abcde"],
  ["long text is cut with an ellipsis within the cap", () => M.clip("abcdefgh", 5), "abcd…"],
  ["trailing space before the ellipsis is dropped", () => M.clip("ab cdefgh", 4), "ab…"],
  ["inline is Artist - Title", () => plain(M.lines("T", "A", true, true, "inline")), [{ text: "A - T", small: false }]],
  ["inline with the artist hidden", () => plain(M.lines("T", "A", true, false, "inline")), [{ text: "T", small: false }]],
  ["inline with no artist known", () => plain(M.lines("T", "", true, true, "inline")), [{ text: "T", small: false }]],
  ["stacked puts the title over a small artist", () => plain(M.lines("T", "A", true, true, "stacked")), [{ text: "T", small: false }, { text: "A", small: true }]],
  ["stacked artist alone is not small", () => plain(M.lines("T", "A", false, true, "stacked")), [{ text: "A", small: false }]],
  ["no title and no artist falls back to the player identity", () => plain(M.lines("", "", true, true, "inline", "Radio")), [{ text: "Radio", small: false }]],
  ["the fallback is off when both fields are hidden", () => M.lines("", "", false, false, "inline", "Radio").length, 0],
  ["metadata wins over the identity", () => plain(M.lines("T", "", true, true, "inline", "Radio")), [{ text: "T", small: false }]],
  ["both hidden leaves no lines", () => M.lines("T", "A", false, false, "inline").length, 0],
  ["time under an hour", () => M.format_time(75), "1:15"],
  ["time over an hour", () => M.format_time(3725), "1:02:05"],
  ["time of nothing", () => M.format_time(undefined), "0:00"],
  ["ratio clamps", () => [M.ratio(5, 10), M.ratio(20, 10), M.ratio(-1, 10), M.ratio(3, 0)], [0.5, 1, 0, 0]],
  ["one marquee cycle is pause, slide, pause: no way back", () => plain(M.marquee_cycle(60, 30, 1200)), { start_pause: 1200, travel: 2000, end_pause: 1200 }],
  ["no overflow or a zero speed never gives a negative or infinite slide", () => [M.marquee_cycle(-5, 30, 100).travel, M.marquee_cycle(50, 0, 100).travel], [0, 50000]],
  ["marquee runs only when wanted, visible and overflowing", () => [M.marquee_running(true, true, 10), M.marquee_running(false, true, 10), M.marquee_running(true, false, 10), M.marquee_running(true, true, 0)], [true, false, false, false]],
  ["stacked lines fit the inner height for every inner height from 20 up", () => { const bad = []; for (let h = 20; h <= 40; h++) { const z = M.stacked_sizes(h, 13); if ((z.title + z.artist) * 1.3 > h + 1e-9) bad.push(h); } return bad; }, []],
  ["stacked lines fit with a tall face (line height 1.7 times its size) from 24 px up", () => { const bad = []; for (let h = 24; h <= 40; h++) { const z = M.stacked_sizes(h, 13, 1.7); if ((z.title + z.artist) * 1.7 > h + 1e-9) bad.push(h); } return bad; }, []],
  ["the stacked title is the larger line and never above the bar font", () => { const z = M.stacked_sizes(26, 13); return [z.title > z.artist, z.title <= 13]; }, [true, true]],
  ["the old 16px inner height did not fit two legible lines", () => { const z = M.stacked_sizes(16, 13); return (z.title + z.artist) * 1.3 > 16; }, true],
];

let failed = 0;
for (const [name, fn, want] of cases) {
  try { assert.deepStrictEqual(fn(), want); console.log("ok   " + name); } catch (e) { failed++; console.log("FAIL " + name + "\n  " + e.message); }
}
process.exit(failed ? 1 : 0);
