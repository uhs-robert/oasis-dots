// Checks the Music mode row in StyleSection: with the style's screen frame off it shows the fixed text and ignores a set.
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/settings/sections/StyleSection.qml"), "utf8");
const block = source.match(/\{\s*label: "Music mode",[\s\S]*?\n        \}/);
if (!block) { console.error("FAIL no Music mode row in StyleSection.qml"); process.exit(1); }

function row_for(frame_on) {
  const Style = { screen_frame_on: frame_on };
  const MusicModeSettings = { on: false, set_on(v) { this.on = v; } };
  const row = new Function("Style", "MusicModeSettings", "return (" + block[0] + ");")(Style, MusicModeSettings);
  return { row, MusicModeSettings };
}

const off = "off (needs the screen frame)";
const cases = [
  ["frame off: one fixed value", () => row_for(false).row.values(), [off]],
  ["frame off: value is the fixed text", () => row_for(false).row.value(), off],
  ["frame off: row does not cycle or pick", () => { const r = row_for(false).row; return [r.cycle, r.pick]; }, [false, false]],
  ["frame off: set is ignored", () => { const { row, MusicModeSettings } = row_for(false); row.set("on"); return MusicModeSettings.on; }, false],
  ["frame on: on and off", () => row_for(true).row.values(), ["on", "off"]],
  ["frame on: set changes the state", () => { const { row, MusicModeSettings } = row_for(true); row.set("on"); return [MusicModeSettings.on, row.value()]; }, [true, "on"]],
  ["frame on: the row cycles", () => row_for(true).row.cycle, true],
];

let failed = 0;
for (const [name, run, want] of cases) {
  let got;
  try { got = run(); } catch (e) { got = "threw " + e.message; }
  try { assert.deepStrictEqual(got, want); } catch (e) { failed++; console.error("FAIL " + name + ": got " + JSON.stringify(got) + ", want " + JSON.stringify(want)); }
}
if (failed) process.exit(1);
console.log(cases.length + " music mode row checks passed");
