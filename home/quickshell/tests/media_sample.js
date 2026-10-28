// Runs MediaSample.js under node: when Settings > Media previews the live player, and the sample's moving parts.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/media/MediaSample.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { uses_live, levels, position };", T);
const M = T.api;

const in_range = list => list.every(v => v > 0 && v < 1);

const cases = [
  ["a playing player is previewed live", () => M.uses_live(true, true, false, "Song", "Band"), true],
  ["a playing player with no metadata (a radio stream) is still live", () => M.uses_live(true, true, false, "", ""), true],
  ["a player paused on a track is previewed live", () => [M.uses_live(true, false, false, "Song", ""), M.uses_live(true, false, false, "", "Band")], [true, true]],
  ["no player gets the sample", () => M.uses_live(false, false, false, "", ""), false],
  ["a stopped player gets the sample, even with a title left over", () => M.uses_live(true, false, true, "Song", "Band"), false],
  ["a paused player with no track gets the sample", () => M.uses_live(true, false, false, "", ""), false],
  ["the sample levels are one per bar and inside 0..1", () => { const l = M.levels(1.5, 48); return [l.length, in_range(l)]; }, [48, true]],
  ["the sample levels move over time", () => JSON.stringify(M.levels(0, 48)) !== JSON.stringify(M.levels(0.5, 48)), true],
  ["a single bar does not divide by zero", () => in_range(M.levels(2, 1)), true],
  ["the sample position runs and starts over at the end", () => [M.position(10, 200), M.position(210, 200)], [10, 10]],
  ["a track with no length stays at the start", () => M.position(10, 0), 0],
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
console.log("media sample: " + cases.length + " checks passed");
