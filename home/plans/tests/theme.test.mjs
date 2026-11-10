// Tests the board's theme choice by cutting it out of board.html between the theme-logic markers.
// Run: node home/plans/tests/theme.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const board_path = join(dirname(fileURLToPath(import.meta.url)), "../.local/lib/plans/plans/board.html");
const html = readFileSync(board_path, "utf8");
const block = html.split("// theme-logic:start")[1].split("// theme-logic:end")[0];

function make_page(saved_value, throws = false, cached_desktop = null) {
  const storage = new Map();
  if (saved_value) storage.set("plans-theme", saved_value);
  if (cached_desktop) storage.set("plans-desktop-theme", cached_desktop);
  const page = { select: "" };
  const localStorage = {
    getItem: (key) => { if (throws) throw new Error("blocked"); return storage.get(key) ?? null; },
    setItem: (key, value) => storage.set(key, value),
    removeItem: (key) => storage.delete(key),
  };
  const root = { dataset: {} };
  const listeners = {};
  const select = {
    get value() { return page.select; }, set value(value) { page.select = value; },
    options: [], append(...options) { this.options.push(...options); },
    addEventListener(type, handler) { listeners[type] = handler; },
  };
  const Option = function (label, value) { this.label = label; this.value = value; };
  const THEMES = [["night_dark", "Night"], ["midnight_dark", "Midnight"], ["moonlight_dark", "Moonlight"]];
  const code = `${block}\nreturn { apply_theme, build_theme_picker, set_board: (value) => { board = value; } };`;
  const api = new Function("localStorage", "document", "element", "THEMES", "FALLBACK_THEME", "THEME_KEY",
    "DESKTOP_THEME_KEY", "FOLLOW", "Option", `let board = null;\n${code}`)(localStorage, { documentElement: root },
    () => select, THEMES, "night_dark", "plans-theme", "plans-desktop-theme", "follow", Option);
  const choose = (value) => { select.value = value; listeners.change(); };
  return { ...api, root, page, storage, select, choose };
}

let page = make_page(null);
page.apply_theme();
assert.equal(page.root.dataset.theme, "night_dark", "before the first board load the theme is night");
assert.equal(page.page.select, "follow", "nothing saved shows Follow desktop");

page.set_board({ desktop_theme: "moonlight_dark" });
page.apply_theme();
assert.equal(page.root.dataset.theme, "moonlight_dark", "follow desktop applies the desktop theme");
page.set_board({ desktop_theme: "moonlight_dark", version: 2 });
page.apply_theme();
assert.equal(page.root.dataset.theme, "moonlight_dark", "a live update keeps the theme instead of flickering to night");

page = make_page("midnight_dark");
page.set_board({ desktop_theme: "moonlight_dark" });
page.apply_theme();
assert.equal(page.root.dataset.theme, "midnight_dark", "a saved theme wins over the desktop one");
assert.equal(page.page.select, "midnight_dark");

page = make_page("gone_dark");
page.set_board({ desktop_theme: "moonlight_dark" });
page.apply_theme();
assert.equal(page.root.dataset.theme, "moonlight_dark", "a saved name that no longer exists follows the desktop");
assert.equal(page.page.select, "follow");

for (const desktop of [null, undefined, "nope_dark"]) {
  page = make_page(null);
  page.set_board({ desktop_theme: desktop });
  page.apply_theme();
  assert.equal(page.root.dataset.theme, "night_dark", `desktop ${desktop} falls back to night`);
}

page = make_page(null, true);
page.set_board({ desktop_theme: "moonlight_dark" });
page.apply_theme();
assert.equal(page.root.dataset.theme, "moonlight_dark", "blocked storage still follows the desktop");

// The first paint of a reload uses the cached desktop theme, not night.
page = make_page(null, false, "moonlight_dark");
page.apply_theme();
assert.equal(page.root.dataset.theme, "moonlight_dark", "before the board loads the cached desktop theme paints");
page.set_board({ desktop_theme: "midnight_dark" });
page.apply_theme();
assert.equal(page.root.dataset.theme, "midnight_dark", "the loaded board replaces the cache");
assert.equal(page.storage.get("plans-desktop-theme"), "midnight_dark");
page.set_board({ desktop_theme: null });
page.apply_theme();
assert.equal(page.storage.has("plans-desktop-theme"), false, "a vanished desktop theme leaves the cache");
assert.equal(page.root.dataset.theme, "night_dark");

// The select: its options, saving a pick, and Follow desktop clearing the save.
page = make_page(null);
page.build_theme_picker();
assert.deepEqual(page.select.options.map((option) => option.label), ["Follow desktop", "Night", "Midnight", "Moonlight"]);
page.set_board({ desktop_theme: "moonlight_dark" });
page.choose("midnight_dark");
assert.equal(page.storage.get("plans-theme"), "midnight_dark", "a pick is saved");
assert.equal(page.root.dataset.theme, "midnight_dark", "a pick applies at once");
page.choose("follow");
assert.equal(page.storage.has("plans-theme"), false, "Follow desktop clears the save");
assert.equal(page.root.dataset.theme, "moonlight_dark", "Follow desktop applies the desktop theme");

const names = [...html.matchAll(/\["(\w+_dark)", "[A-Z]\w+"\]/g)].map((match) => match[1]);
assert.equal(names.length, 16, "the page lists 16 themes");
console.log("theme tests passed");
