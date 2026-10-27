// Runs ScrollCue.js under node: which edges hide content, and that a revealed row stays clear of the fade.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/settings/ScrollCue.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { hidden_edges, reveal_target };", T);
const S = T.api;

const view = 700;
const content = 900;
const lead = 24;
const foot = 20;
const row = 28;
const pitch = 32;
const last_scroll = content - view;

// Every row index, from every starting scroll: after the reveal the row is in view, clear of the bottom fade unless
// the content ends there (the fade is gone then) and clear of the top fade unless it starts there.
function worst_clearance(lead, foot) {
  let worst = Infinity;
  for (let start = 0; start <= last_scroll; start += 7) {
    for (let top = 40; top + row <= content; top += pitch) {
      const y = S.reveal_target(top, row, start, view, content, lead, foot);
      const fade_below = y + view < content - 1;
      const below = y + view - (top + row);
      const above = top - y;
      if (below < 0 || above < 0) return -1;
      if (fade_below) worst = Math.min(worst, below);
      if (y > 1) worst = Math.min(worst, above - foot);
    }
  }
  return worst;
}

const cases = [
  ["content that fits hides no edge", () => S.hidden_edges(0, 700, 700), { top: false, bottom: false }],
  ["content shorter than the view hides no edge", () => S.hidden_edges(0, 700, 300), { top: false, bottom: false }],
  ["at the top only the bottom is hidden", () => S.hidden_edges(0, view, content), { top: false, bottom: true }],
  ["in the middle both are hidden", () => S.hidden_edges(100, view, content), { top: true, bottom: true }],
  ["at the end only the top is hidden", () => S.hidden_edges(last_scroll, view, content), { top: true, bottom: false }],
  ["a fractional settle at the end shows no bottom cue", () => S.hidden_edges(last_scroll - 0.4, view, content).bottom, false],
  ["a row already in view does not scroll", () => S.reveal_target(300, row, 100, view, content, lead, foot), 100],
  ["a row under the bottom fade scrolls it clear", () => S.reveal_target(100 + view - 10 - row, row, 100, view, content, lead, foot), 100 + view - 10 - row + row - view + foot],
  ["a row just above the fade stays put", () => S.reveal_target(100 + view - foot - row, row, 100, view, content, lead, foot), 100],
  ["a row above the view scrolls to its lead", () => S.reveal_target(150, row, 300, view, content, lead, foot), 150 - lead],
  ["the last row scrolls to the end", () => S.reveal_target(content - row, row, 0, view, content, lead, foot), last_scroll],
  ["the first row scrolls to the top", () => S.reveal_target(0, row, 300, view, content, lead, foot), 0],
  ["short content never scrolls", () => S.reveal_target(100, row, 0, view, 300, lead, foot), 0],
  ["a row above the view clears a fade taller than the lead", () => S.reveal_target(150, row, 300, view, content, 12, 28), 150 - 28],
  ["no revealed row ends under a visible fade", () => worst_clearance(lead, foot) >= 0, true],
  ["nor when the fade is taller than the lead", () => worst_clearance(12, 28) >= 0, true],
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
console.log("scroll cue: " + cases.length + " checks passed");
