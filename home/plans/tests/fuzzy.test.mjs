// Tests the repo picker's matcher by cutting it out of board.html between the fuzzy markers.
// Run: node home/plans/tests/fuzzy.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const board_path = join(dirname(fileURLToPath(import.meta.url)), "../.local/lib/plans/plans/board.html");
const html = readFileSync(board_path, "utf8");
const block = html.split("// fuzzy:start")[1].split("// fuzzy:end")[0];
const { fuzzy_score, rank_repos } = new Function(`${block}\nreturn { fuzzy_score, rank_repos };`)();

const repo = (label, folder) => ({ label, root: `/home/me/${folder ?? label.split("/")[1]}` });
const labels = (query, repos) => rank_repos(query, repos).map((entry) => entry.label);

assert.ok(fuzzy_score("dtf", "me/dotfiles") >= 0, "subsequence matches");
assert.equal(fuzzy_score("fdt", "me/dotfiles"), -Infinity, "order matters");
assert.equal(fuzzy_score("zzz", "me/dotfiles"), -Infinity, "a missing letter fails");
assert.equal(fuzzy_score("DOT", "me/dotfiles"), fuzzy_score("dot", "ME/DOTFILES"), "case-insensitive");

assert.ok(fuzzy_score("dot", "me/dotfiles") > fuzzy_score("dot", "me/d-o-t-x"), "consecutive beats word-boundary scatter");
assert.ok(fuzzy_score("dot", "me/dotfiles") > fuzzy_score("dot", "me/mydxoxt"), "consecutive beats scattered");
assert.ok(fuzzy_score("tool", "me/my-tools") > fuzzy_score("tool", "me/atxoxoxl"), "word start beats scattered");
assert.ok(fuzzy_score("t", "me/tools") > fuzzy_score("t", "me/matt"), "word boundary beats mid-word");
assert.ok(fuzzy_score("dot", "me/dot") > fuzzy_score("dot", "me/dotfiles-extra"), "shorter text wins a tie");

const repos = [repo("a/alpha"), repo("a/dotfiles"), repo("a/dxoxtx"), repo("b/zeta", "dotty-checkout")];
assert.deepEqual(labels("", repos), ["a/alpha", "a/dotfiles", "a/dxoxtx", "b/zeta"], "empty query keeps order");
assert.equal(labels("dot", repos)[0], "a/dotfiles", "best match first");
assert.ok(labels("dot", repos).includes("b/zeta"), "matches the folder name when the label does not");
assert.ok(!labels("dot", repos).includes("a/alpha"), "non-matches are dropped");
assert.deepEqual(labels("a/al", repos), ["a/alpha"], "matches the owner/name label");
assert.deepEqual(labels("DOTTY", repos), ["b/zeta"], "folder match is case-insensitive");
const ties = [repo("a/aaa"), repo("b/aaa", "aaa2"), repo("c/aaa", "aaa3")];
assert.deepEqual(labels("aaa", ties), ["a/aaa", "b/aaa", "c/aaa"], "ties keep the input order");
assert.deepEqual(labels("qqq", repos), [], "no match gives an empty list");

// A late match in a long name scores below zero from the gap and length penalties. It is still a match.
const long_repos = [repo("me/my-long-project"), repo("me/jam")];
assert.ok(fuzzy_score("j", "my-long-project") > -Infinity, "a negative score is still a match");
assert.deepEqual(labels("j", [repo("me/my-long-project")]), ["me/my-long-project"], "a late short match is kept");
assert.deepEqual(labels("j", long_repos), ["me/jam", "me/my-long-project"], "the early match still ranks first");

console.log("fuzzy tests passed");
