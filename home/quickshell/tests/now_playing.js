// Runs NowPlaying.js under node: which tabs count as playing from the bridge's events, which one shows, how the
// one-time tab list at connect merges in, and the stream's first line.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const file = path.join(__dirname, "../.config/quickshell/features/desertfox/NowPlaying.js");
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(file, "utf8").replace(/^\.pragma.*$/m, "") + "\nthis.api = { empty, parse_line, is_refusal, reduce, seed, current, label_of, next_backoff_ms, pause_request };", ctx);
const N = ctx.api;

const audible = (id, on, title) => ({ event: "tab_audible", tab_id: id, window_id: 3, audible: on, title: title || "T" + id, url: "https://x/" + id });
const run = (events, from) => events.reduce(N.reduce, from || N.empty);
const ids = state => state.audible.map(t => t.tab_id);

const cases = [
  ["nothing plays at first", () => N.current(N.empty), null],
  ["an audible tab shows", () => N.current(run([audible(5, true)])).title, "T5"],
  ["the most recent of several audible tabs shows", () => N.current(run([audible(5, true), audible(7, true)])).tab_id, 7],
  ["the one before returns when the newest stops", () => N.current(run([audible(5, true), audible(7, true), audible(7, false)])).tab_id, 5],
  ["a repeated audible event moves the tab to the front", () => ids(run([audible(5, true), audible(7, true), audible(5, true)])), [7, 5]],
  ["silence clears the last tab", () => N.current(run([audible(5, true), audible(5, false)])), null],
  ["a removed tab goes", () => ids(run([audible(5, true), audible(7, true), { event: "tab_removed", tab_id: 7 }])), [5]],
  ["removing a tab that is not playing changes nothing", () => ids(run([audible(5, true), { event: "tab_removed", tab_id: 9 }])), [5]],
  ["tabs_off clears everything", () => run([audible(5, true), { event: "tabs_off" }]), N.empty],
  ["a title change reaches the playing tab", () => N.current(run([audible(5, true), { event: "tab_updated", tab_id: 5, window_id: 3, title: "Next song", url: "https://x/5" }])).title, "Next song"],
  ["a title change of a silent tab adds nothing", () => ids(run([{ event: "tab_updated", tab_id: 5, window_id: 3, title: "a", url: "b" }])), []],
  ["mode and activation events change nothing", () => run([audible(5, true), { event: "mode", id: "normal" }, { event: "tab_activated", tab_id: 8, window_id: 3 }]).audible.length, 1],
  ["the reducer does not change the state it is given", () => { const before = run([audible(5, true)]); const copy = JSON.stringify(before); run([audible(5, false)], before); return JSON.stringify(before) === copy; }, true],
  ["the window id comes through for the jump", () => N.current(run([audible(5, true)])).window_id, 3],

  ["a tab list adds audible tabs, the least recently used first", () => ids(N.seed(N.empty, { ok: true, tabs: [
    { tab_id: 1, audible: true, last_accessed: 30 }, { tab_id: 2, audible: false, last_accessed: 99 }, { tab_id: 3, audible: true, last_accessed: 10 }] })), [3, 1]],
  ["the tab list stays older than a tab an event named", () => ids(N.seed(run([audible(5, true)]), { ok: true, tabs: [{ tab_id: 1, audible: true, last_accessed: 99 }] })), [1, 5]],
  ["the tab list does not bring back a tab an event silenced", () => ids(N.seed(run([audible(5, true), audible(5, false)]), { ok: true, tabs: [{ tab_id: 5, audible: true, last_accessed: 1 }] })), []],
  ["a refused tab list changes nothing", () => N.seed(N.empty, { ok: false, message: "off" }), N.empty],
  ["a malformed tab list changes nothing", () => [N.seed(N.empty, null), N.seed(N.empty, { ok: true }), N.seed(N.empty, { ok: true, tabs: [null, { audible: true }] })].map(s => s.audible.length), [0, 0, 0]],

  ["the ack is the first line", () => N.parse_line('{"ok":true}').kind, "ack"],
  ["the cap refusal is told apart", () => N.is_refusal(N.parse_line('{"ok":false,"message":"too many subscribers"}')), true],
  ["another refusal is not the cap", () => N.is_refusal(N.parse_line('{"ok":false,"message":"rate limited"}')), false],
  ["an event line carries its fields", () => N.parse_line('{"event":"tabs_off","seq":4}').event.seq, 4],
  ["junk is junk", () => ["", "nope", "5", "null", "{}"].map(t => N.parse_line(t).kind), ["junk", "junk", "junk", "junk", "junk"]],

  ["a short title stays whole", () => N.label_of({ title: "Song", url: "u" }, 10), "Song"],
  ["a long title is cut with an ellipsis", () => N.label_of({ title: "abcdefghij", url: "u" }, 5), "abcd…"],
  ["a missing title falls back to the address", () => N.label_of({ title: "", url: "https://x" }, 40), "https://x"],
  ["no tab, no label", () => N.label_of(null, 5), ""],

  ["the backoff doubles to its cap", () => [0, 1000, 2000, 16000, 30000].map(N.next_backoff_ms), [2000, 2000, 4000, 30000, 30000]],
  ["pause is play_pause on that tab", () => N.pause_request(7), { verb: "run", command: "media play_pause", tab_id: 7 }],
];

let failed = 0;
for (const [name, fn, want] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(fn())), JSON.parse(JSON.stringify(want === undefined ? null : want)));
    console.log("ok   " + name);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + "\n  " + String(e.message).split("\n").join("\n  "));
  }
}
console.log(`\n${cases.length - failed}/${cases.length} passed`);
process.exit(failed ? 1 : 0);
