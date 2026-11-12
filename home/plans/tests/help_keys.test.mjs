// Checks that the help modal lists every board key and nothing else, by cutting both lists out of board.html.
// Run: node home/plans/tests/help_keys.test.mjs [path to a board.html copy]
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const board_path = process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)), "../.local/lib/plans/plans/board.html");
const html = readFileSync(board_path, "utf8");
const cut = (name) => html.split(`// ${name}:start`)[1].split(`// ${name}:end`)[0];
const help_sections = new Function(`${cut("help-keys")}\nreturn HELP_SECTIONS;`)();
// The actions are arrow functions that only run on a key press, so the map builds without the page.
const board_keys = Object.keys(new Function(`${cut("board-keys")}\nreturn KEYS;`)());

const help_keys = new Set(help_sections.flatMap(([, rows]) => rows.flatMap(([keys]) => keys)));
// g is the two-press chord and Esc closes panels. Neither sits in KEYS, which holds single-press actions.
const not_in_keys = new Set(["g", "Esc"]);

for (const key of board_keys) assert.ok(help_keys.has(key), `KEYS has "${key}" but the help modal does not list it`);
for (const key of help_keys) {
  if (!not_in_keys.has(key)) assert.ok(board_keys.includes(key), `the help modal lists "${key}" but KEYS has no such key`);
}
console.log("help keys ok");
