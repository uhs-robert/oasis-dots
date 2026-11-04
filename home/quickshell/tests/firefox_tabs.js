// Runs FirefoxTabs.js under node: reading firefox-tab's replies, tab order, the window filter and thumbnail sources.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const file = path.join(__dirname, "../.config/quickshell/features/launcher/FirefoxTabs.js");
const ctx = vm.createContext({});
const names = ["parse_reply", "short_host", "tab_item", "items_of", "windows_of", "cycled_filter", "kept_by_filter", "filter_label", "merged_thumbs", "thumb_of", "thumbnail_source", "favicon_source", "capture_batches"];
vm.runInContext(fs.readFileSync(file, "utf8").replace(/^\.pragma.*$/m, "") + "\nthis.api = { " + names.join(", ") + " };", ctx);
const F = ctx.api;

const tab = (id, window_id, last_accessed, extra) => Object.assign({ tab_id: id, window_id: window_id, title: "Tab " + id, url: "https://www.example.com/" + id, active: false, discarded: false, last_accessed: last_accessed, incognito: false, pinned: false, hidden: false, fav_icon_url: "", thumbnail: "", thumbnail_at: 0 }, extra || {});
const listed = [tab(1, 10, 100), tab(2, 20, 300, { active: true }), tab(3, 10, 200, { discarded: true }), tab(4, 20, 50, { hidden: true }), tab(5, 30, 400, { incognito: true })];
const items = F.items_of(listed);
const windows = F.windows_of(items);

const cases = [
  ["an ok reply carries its result", () => F.parse_reply('{"ok":true,"result":[1]}'), { state: "ok", result: [1], error: "" }],
  ["an unreachable host is unavailable", () => F.parse_reply('{"ok":false,"unavailable":true,"error":"no socket"}').state, "unavailable"],
  ["an error answer is an error, with its text", () => F.parse_reply('{"ok":false,"error":"refused"}'), { state: "error", result: null, error: "refused" }],
  ["no output at all (firefox-tab missing) is unavailable", () => [F.parse_reply("").state, F.parse_reply("sh: not found").state], ["unavailable", "unavailable"]],
  ["host: scheme, www, port, path and user go", () => [F.short_host("https://www.example.com:8080/a?b"), F.short_host("http://me@docs.example.org/x"), F.short_host("https://example.com")], ["example.com", "docs.example.org", "example.com"]],
  ["host: a URL with no host keeps its scheme", () => [F.short_host("about:config?filter=x"), F.short_host("file:///home/me/a.html"), F.short_host("moz-extension://abc/page.html"), F.short_host("")], ["about:config", "file", "abc", ""]],
  ["most recently used first", () => items.map(i => i.tab_id), [2, 3, 1]],
  ["hidden and private tabs never show", () => items.some(i => i.tab_id === 4 || i.tab_id === 5), false],
  ["a malformed tab is skipped, not fatal", () => F.items_of([{ tab_id: "x", window_id: 1 }, null, tab(7, 1, 0)]).map(i => i.id), ["7"]],
  ["a result that is not a list gives no tabs", () => F.items_of({ tabs: [] }), []],
  ["the title is the label, the URL searchable as the description, the host a keyword", () => { const i = F.tab_item(tab(1, 1, 0)); return [i.label, i.description, i.keywords]; }, ["Tab 1", "https://www.example.com/1", ["example.com"]]],
  ["an untitled tab is labelled by its URL", () => F.tab_item(tab(1, 1, 0, { title: "" })).label, "https://www.example.com/1"],
  ["a tie in recency puts the active tab first", () => F.items_of([tab(1, 1, 5), tab(2, 1, 5, { active: true })]).map(i => i.tab_id), [2, 1]],
  ["windows in the order their newest tab shows", () => windows, [20, 10]],
  ["f cycles all, each window, then all", () => [F.cycled_filter("all", windows), F.cycled_filter(20, windows), F.cycled_filter(10, windows)], [20, 10, "all"]],
  ["a gone window cycles back to all, and with no windows all stays", () => [F.cycled_filter(99, windows), F.cycled_filter("all", [])], ["all", "all"]],
  ["the filter keeps one window's tabs", () => items.filter(i => F.kept_by_filter(i, 10)).map(i => i.tab_id), [3, 1]],
  ["labels say all or the window's place", () => [F.filter_label("all", windows), F.filter_label(10, windows), F.filter_label(99, windows)], ["ALL", "WINDOW 2/2", "ALL"]],
  ["a capture adds its image; a failed one keeps the old", () => F.merged_thumbs({ "1": { thumbnail: "/c/a.jpg", thumbnail_at: 5 } }, [{ tab_id: 1, ok: false, error: "x" }, { tab_id: 2, ok: true, thumbnail: "/c/b.jpg", thumbnail_at: 9 }]), { "1": { thumbnail: "/c/a.jpg", thumbnail_at: 5 }, "2": { thumbnail: "/c/b.jpg", thumbnail_at: 9 } }],
  ["a capture result that is not a list changes nothing", () => F.merged_thumbs({}, "nope"), {}],
  ["the newer of the listed and captured image wins", () => [F.thumb_of({ id: "1", thumbnail: "/l.jpg", thumbnail_at: 3 }, { "1": { thumbnail: "/c.jpg", thumbnail_at: 7 } }).thumbnail, F.thumb_of({ id: "1", thumbnail: "/l.jpg", thumbnail_at: 9 }, { "1": { thumbnail: "/c.jpg", thumbnail_at: 7 } }).thumbnail], ["/c.jpg", "/l.jpg"]],
  ["a refreshed image at the same path gets a new URL", () => F.thumbnail_source({ thumbnail: "/c/a.jpg", thumbnail_at: 1 }) !== F.thumbnail_source({ thumbnail: "/c/a.jpg", thumbnail_at: 2 }), true],
  ["the source is an escaped file URL, none without an absolute path", () => [F.thumbnail_source({ thumbnail: "/my cache/#1.jpg", thumbnail_at: 4 }), F.thumbnail_source({ thumbnail: "", thumbnail_at: 0 }), F.thumbnail_source({ thumbnail: "rel.jpg", thumbnail_at: 0 })], ["file:///my%20cache/%231.jpg?at=4", "", ""]],
  ["favicons load only without the network", () => [F.favicon_source("data:image/png;base64,AAAA"), F.favicon_source("https://example.com/favicon.ico"), F.favicon_source("chrome://branding/icon.svg")], ["data:image/png;base64,AAAA", "", ""]],
  ["captures skip unloaded tabs, a few per batch", () => F.capture_batches(F.items_of([tab(1, 1, 9), tab(2, 1, 8, { discarded: true }), tab(3, 1, 7), tab(4, 1, 6), tab(5, 1, 5)]), 2), [[1, 3], [4, 5]]],
];

let failed = 0;
for (const [name, fn, expected] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(fn())), expected);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + "\n  " + e.message.split("\n")[0]);
  }
}
if (failed) process.exit(1);
console.log("firefox tabs: " + cases.length + " checks passed");
