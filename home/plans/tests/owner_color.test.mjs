// Tests the owner color assignment by cutting it out of board.html between the fuzzy markers.
// Run: node home/plans/tests/owner_color.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const board_path = join(dirname(fileURLToPath(import.meta.url)), "../.local/lib/plans/plans/board.html");
const block = readFileSync(board_path, "utf8").split("// fuzzy:start")[1].split("// fuzzy:end")[0];
const { assign_owner_colors, ASSIGNEE_SLOTS } =
  new Function(`${block}\nreturn { assign_owner_colors, ASSIGNEE_SLOTS };`)();

const names = ["dotfiles-5d", "alpha", "beta", "gamma", "delta"];
const colors = assign_owner_colors(names);
assert.equal(colors.size, 5);
assert.deepEqual([...new Set(colors.values())].sort(), [...ASSIGNEE_SLOTS].sort(), "five names take five distinct slots");
assert.deepEqual([...assign_owner_colors([...names].reverse())], [...colors], "input order does not matter");
assert.deepEqual([...assign_owner_colors([...names, "alpha", "beta"])], [...colors], "duplicates do not shift colors");
assert.equal(assign_owner_colors(["alpha"]).get("alpha"), assign_owner_colors(["alpha"]).get("alpha"), "stable");

const grays = ["none", "", "(assigned)".replace(/^/, "\u0000"), "\u0000unset", "\u0000assigned"];
const mixed = assign_owner_colors([...grays, "alpha", "beta"]);
assert.deepEqual([...mixed.keys()].sort(), ["alpha", "beta"], "none, empty and synthetic rows stay gray");
assert.deepEqual([...mixed], [...assign_owner_colors(["alpha", "beta"])], "gray rows take no slot");

const many = assign_owner_colors(["a", "b", "c", "d", "e", "f", "g"]);
assert.equal(many.size, 7, "every name gets a color past five");
assert.ok([...many.values()].every((color) => ASSIGNEE_SLOTS.includes(color)));

console.log("owner_color ok");
