// Runs MediaSettings.js under node: the cava-line migration and the island_mode rules the bar wires.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/media/MediaSettings.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { migrated_cava_line, module_listed, edge_cava_allowed, module_position_only, edge_strip, strip_listed, scroll_effect, well_shown, right_side, container_look, vertical_cells };", T);
const M = T.api;

const cases = [
  // Migration: the old style.json value moves once and never overwrites media.json.
  ["no media.json: take the old value (off)", () => M.migrated_cava_line({}, false), false],
  ["no media.json: take the old value (on)", () => M.migrated_cava_line({}, true), true],
  ["media.json already holds cava_line: no migration (false)", () => M.migrated_cava_line({ cava_line: false }, true), null],
  ["media.json already holds cava_line: no migration (true)", () => M.migrated_cava_line({ cava_line: true }, false), null],
  ["media.json without the key still migrates", () => M.migrated_cava_line({ island_mode: "split" }, false), false],
  ["a non-boolean cava_line counts as missing", () => M.migrated_cava_line({ cava_line: "yes" }, false), false],
  ["corrupt raw (null) falls back to the old value", () => M.migrated_cava_line(null, false), false],
  ["old style.json without the key means on", () => M.migrated_cava_line({}, undefined), true],
  // island_mode only touches island styles.
  ["cava_under_island hides the module in an island style", () => M.module_listed(true, "cava_under_island"), false],
  ["module_only shows the module in an island style", () => M.module_listed(true, "module_only"), true],
  ["split shows the module in an island style", () => M.module_listed(true, "split"), true],
  ["strip/frame styles always show the module", () => ["cava_under_island", "module_only", "split"].map(m => M.module_listed(false, m)), [true, true, true]],
  ["module_only draws no island-edge cava", () => M.edge_cava_allowed(true, "module_only"), false],
  ["cava_under_island and split keep the island-edge cava", () => [M.edge_cava_allowed(true, "cava_under_island"), M.edge_cava_allowed(true, "split")], [true, true]],
  ["strip/frame styles never gain or lose edge cava from the mode", () => ["cava_under_island", "module_only", "split"].map(m => M.edge_cava_allowed(false, m)), [true, true, true]],
  ["split forces position on the module in an island style", () => M.module_position_only(true, "split"), true],
  ["other modes and non-island styles leave the module's side alone", () => [M.module_position_only(true, "module_only"), M.module_position_only(false, "split"), M.module_position_only(true, "cava_under_island")], [false, false, false]],
  ["on AC the edge strip is cava in an island style", () => ["cava_under_island", "split"].map(m => M.edge_strip(true, m, true, "hide")), ["cava", "cava"]],
  ["on battery the edge strip follows battery_fallback in an island style", () => [M.edge_strip(true, "cava_under_island", false, "position"), M.edge_strip(true, "split", false, "hide")], ["position", "none"]],
  ["module_only never draws the edge strip, on AC or battery", () => [M.edge_strip(true, "module_only", true, "position"), M.edge_strip(true, "module_only", false, "position")], ["none", "none"]],
  ["outside island styles battery draws nothing at the edge", () => M.edge_strip(false, "cava_under_island", false, "position"), "none"],
  ["lualine forces position on the module whatever the mode", () => ["cava_under_island", "module_only", "split"].map(m => M.module_position_only(false, m, true)), [true, true, true]],
  ["a media entry alone asks for the clock-island strip", () => [M.strip_listed(false, true), M.strip_listed(true, false), M.strip_listed(false, false)], [true, true, false]],
  ["the right side seeks whatever scroll_action says", () => ["volume_seek", "skip", "none"].map(a => M.scroll_effect(true, a)), ["seek", "seek", "seek"]],
  ["elsewhere the wheel follows scroll_action", () => ["volume_seek", "skip", "none"].map(a => M.scroll_effect(false, a)), ["volume", "skip", "none"]],
  ["an unknown scroll_action acts as volume_seek off the right side", () => M.scroll_effect(false, "bogus"), "volume"],
  ["a player with no metadata still shows the well", () => M.well_shown(true, false, false, true, true), true],
  ["no player shows nothing; the cava alias on a side bar stays hidden", () => [M.well_shown(false, false, false, true, true), M.well_shown(true, true, true, true, true), M.well_shown(true, true, false, true, true)], [false, false, true]],
  ["a side bar hides the well when art and button are both off", () => [M.well_shown(true, true, false, false, false), M.well_shown(true, true, false, true, false), M.well_shown(true, true, false, false, true)], [false, true, true]],
  ["off a side bar the well shows with art and button off (cava only)", () => M.well_shown(true, false, false, false, false), true],
  ["a side bar stacks one cell per shown part", () => [M.vertical_cells(true, true), M.vertical_cells(true, false), M.vertical_cells(false, true), M.vertical_cells(false, false)], [2, 1, 1, 0]],
  ["the setting decides the right side for every entry", () => ["cava", "position"].map(s => M.right_side("", s, true, "position")), ["cava", "position"]],
  ["a forced side (split, lualine) beats the setting", () => [M.right_side("position", "cava", true, "hide"), M.right_side("cava", "position", true, "hide")], ["position", "cava"]],
  ["on battery cava follows battery_fallback, position stays", () => [M.right_side("", "cava", false, "hide"), M.right_side("", "position", false, "hide")], ["hide", "position"]],
  ["inset presses in: shadow fill, soft border, top shadow", () => M.container_look("inset"), { fill: "shadow", border: "soft", top_shadow: true }],
  ["border outlines with no fill", () => M.container_look("border"), { fill: "none", border: "strong", top_shadow: false }],
  ["raised washes with no border", () => M.container_look("raised"), { fill: "wash", border: "none", top_shadow: false }],
  ["none draws no plate, border or shadow", () => M.container_look("none"), { fill: "none", border: "none", top_shadow: false }],
  ["an unknown container style acts as inset", () => M.container_look("bogus"), { fill: "shadow", border: "soft", top_shadow: true }],
  ["an unknown mode behaves as cava_under_island", () => [M.module_listed(true, "bogus"), M.edge_cava_allowed(true, "bogus")], [false, true]],
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
console.log("media settings: " + cases.length + " checks passed");
