// Tests how the board takes the laptop key from the URL fragment, by cutting adopt_laptop_key out of board.html
// between the laptop-key markers and running it on fake location, history and storage objects.
// Run: node home/plans/tests/laptop_key.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const board_path = join(dirname(fileURLToPath(import.meta.url)), "../.local/lib/plans/plans/board.html");
const block = readFileSync(board_path, "utf8").split("// laptop-key:start")[1].split("// laptop-key:end")[0];
const { adopt_laptop_key, LAPTOP_KEY_STORE } = new Function(`${block}\nreturn { adopt_laptop_key, LAPTOP_KEY_STORE };`)();

const KEY = "Ab3_-".repeat(8) + "xyz";
assert.equal(KEY.length, 43);

function page(hash, saved) {
  const calls = [];
  const items = new Map(saved ? [[LAPTOP_KEY_STORE, saved]] : []);
  const location = { hash, pathname: "/", search: "" };
  const history = {
    state: { kept: true },
    replaceState(state, title, url) {
      calls.push([state, title, url]);
      location.hash = "";
    },
  };
  const storage = { getItem: (name) => items.get(name) ?? null, setItem: (name, value) => items.set(name, value) };
  return { location, history, storage, calls, items };
}

{
  const p = page(`#laptop-key=${KEY}`);
  assert.equal(adopt_laptop_key(p.location, p.history, p.storage), KEY, "the fragment key is taken");
  assert.deepEqual(p.calls, [[{ kept: true }, "", "/"]], "the fragment is stripped once, keeping path and state");
  assert.equal(p.items.get(LAPTOP_KEY_STORE), KEY, "the key is saved");
}
{
  const p = page("", KEY);
  assert.equal(adopt_laptop_key(p.location, p.history, p.storage), KEY, "a later load uses the saved key");
  assert.deepEqual(p.calls, [], "a load without the fragment leaves the URL alone");
}
{
  const p = page("#laptop-key=short", "old");
  assert.equal(adopt_laptop_key(p.location, p.history, p.storage), null, "a malformed key is not used");
  assert.equal(p.calls.length, 1, "a malformed key is still stripped");
  assert.equal(p.items.get(LAPTOP_KEY_STORE), "old", "a malformed key does not overwrite the saved one");
}
{
  const p = page(`#laptop-key=${KEY}`, "old");
  adopt_laptop_key(p.location, p.history, p.storage);
  assert.equal(p.items.get(LAPTOP_KEY_STORE), KEY, "a new key from the launcher replaces the saved one");
}
{
  const p = page("#other");
  assert.equal(adopt_laptop_key(p.location, p.history, p.storage), null, "no key and none saved");
  assert.deepEqual(p.calls, [], "another fragment stays");
}
{
  const p = page(`#laptop-key=${KEY}`);
  assert.equal(adopt_laptop_key(p.location, p.history, null), KEY, "blocked storage keeps the key for this page");
  assert.equal(p.calls.length, 1);
  const blocked = { getItem() { throw new Error("blocked"); }, setItem() { throw new Error("blocked"); } };
  const q = page("");
  assert.equal(adopt_laptop_key(q.location, q.history, blocked), null, "storage that throws reads as no key");
}

console.log("laptop_key ok");
