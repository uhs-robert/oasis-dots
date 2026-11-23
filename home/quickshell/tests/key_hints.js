// Runs KeyHints.js under node: which keys draw as controller glyphs, and that none draws for a key its face does not show.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/ui/keys/KeyHints.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { controller_parts, button_path, cap_pad_w, cap_gloss_h };", T);
const K = T.api;

const buttons = (pad, key) => K.controller_parts(pad, key).map(p => p.button || "text:" + p.text);

const cases = [
  ["Enter is START", () => buttons("ps2", "Enter"), ["start"]],
  ["Tab is SELECT", () => buttons("snes", "Tab"), ["select"]],
  ["Esc stays a plain cap", () => buttons("nes", "Esc"), []],
  ["q stays a plain cap", () => buttons("ps1", "q"), []],
  ["Backspace stays a plain cap", () => buttons("snes", "Backspace"), []],
  ["slash, t, gg and G stay plain caps", () => ["/", "t", "gg", "G"].map(k => buttons("ps2", k).length), [0, 0, 0, 0]],
  ["o is circle, x is cross", () => [buttons("ps2", "o"), buttons("ps1", "x")], [["circle"], ["cross"]]],
  ["SNES face letters", () => ["a", "b", "x", "y"].map(k => buttons("snes", k)[0]), ["a", "b", "x", "y"]],
  ["NES has a and b only", () => ["a", "b", "x", "y"].map(k => buttons("nes", k).length), [1, 1, 0, 0]],
  ["Game Boy follows NES", () => buttons("gameboy", "j"), ["dpad_down"]],
  ["single d-pad keys light one arm on every console", () => ["ps1", "ps2", "nes", "snes", "gameboy"].map(p => ["h", "j", "k", "l"].map(k => buttons(p, k)[0]).join()), Array(5).fill("dpad_left,dpad_down,dpad_up,dpad_right")],
  ["arrow words light one arm", () => ["Up", "Down", "Left", "Right"].map(k => buttons("ps2", k)[0]), ["dpad_up", "dpad_down", "dpad_left", "dpad_right"]],
  ["a pair keeps its axis", () => [buttons("ps2", "h/l"), buttons("nes", "j/k"), buttons("snes", "Up/Down")], [["dpad_h"], ["dpad_v"], ["dpad_v"]]],
  ["[ ] pair is the pair glyph on SNES", () => buttons("snes", "[ ]"), ["lr"]],
  ["[ ] pair is two shoulders on PS2", () => buttons("ps2", "[ ]"), ["l1", "r1"]],
  ["single shoulders", () => [buttons("snes", "["), buttons("ps1", "]")], [["l"], ["r1"]]],
  ["a modified key never draws", () => buttons("ps2", "Ctrl+Enter"), []],
  ["no glyphs without a console", () => buttons("", "Enter"), []],
  ["cap sizes per key_cap", () => ["none", "ps2_gloss", "ps1_dome", "snes_lavender", "nes_black"].map(c => [K.cap_pad_w({ key_cap: c }), K.cap_gloss_h({ key_cap: c })]), [[6, 0], [10, 3], [8, 2], [8, 2], [8, 2]]],
  ["an unknown key_cap is sized as a flat cap", () => [K.cap_pad_w({ key_cap: "nes_blk" }), K.cap_gloss_h({ key_cap: "nes_blk" })], [6, 0]],
  ["every console resolves a button file", () => ["nes", "snes", "ps1", "ps2", "gameboy"].map(p => K.button_path(p).endsWith(".qml")), Array(5).fill(true)],
];

let failed = 0;
for (const [name, run, want] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(run())), want);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + "\n" + e.message);
  }
}
if (failed) process.exit(1);
console.log(cases.length + " key hint cases passed");
