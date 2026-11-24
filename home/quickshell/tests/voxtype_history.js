// Runs VoxtypeHistory.js under node: the voxtype history picker's parsing, day headers and filter.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/launcher/VoxtypeHistory.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { parse, group_title, cycled_filter, kept_by_filter, filter_labels };", context);
const { parse, group_title, cycled_filter, kept_by_filter, filter_labels } = context.api;

// Local times, so the day keys hold in any time zone the test runs in.
function iso(y, mo, d, h, mi) {
  return new Date(y, mo - 1, d, h, mi).toISOString();
}

const listing = JSON.stringify({
  enabled: true,
  paused: false,
  entries: [
    { id: "a", app: "firefox", outcome: "delivered", text: "hello\n  world", raw_text: "hello world", ts_start: iso(2026, 11, 24, 14, 7) },
    { id: "b", app: "kitty", outcome: "cancelled", text: "", raw_text: "heard this", ts_start: iso(2026, 11, 23, 9, 30) },
    { id: "c", outcome: "delivered", text: "typed", correction: "fixed", ts_start: iso(2026, 11, 20, 8, 0) },
    { id: "d", outcome: "no_speech", text: "", raw_text: "" },
    { app: "kitty", text: "no id" },
  ],
});
const now = new Date(2026, 10, 24, 18, 0);

const cases = [
  ["entries keep their order and skip ones with no id or no text", () => parse(listing).entries.map(e => e.id), ["a", "b", "c"]],
  ["the label folds whitespace, the text stays whole", () => { const e = parse(listing).entries[0]; return [e.label, e.text]; }, ["hello world", "hello\n  world"]],
  ["text falls back to what the engine heard, and a correction wins", () => parse(listing).entries.map(e => e.text), ["hello\n  world", "heard this", "fixed"]],
  ["day and time are local", () => parse(listing).entries.map(e => [e.day, e.time]), [["2026-11-24", "14:07"], ["2026-11-23", "09:30"], ["2026-11-20", "08:00"]]],
  ["the app is a search keyword", () => parse(listing).entries.map(e => e.keywords), [["firefox"], ["kitty"], []]],
  ["a missing voxtype, bad output and history off are states", () => [parse("missing\n").state, parse("oops").state, parse("{}").state, parse('{"enabled":false,"entries":[]}').state, parse(listing).state], ["missing", "error", "error", "off", "ok"]],
  ["paused shows through", () => parse('{"enabled":true,"paused":true,"entries":[]}').paused, true],
  ["day headers read today, yesterday, a weekday, then a date", () => ["2026-11-24", "2026-11-23", "2026-11-20", "2026-11-10", ""].map(k => group_title(k, 1, now)), ["TODAY · 1 DICTATION", "YESTERDAY · 1 DICTATION", "FRI · 1 DICTATION", "NOV 10 · 1 DICTATION", "UNDATED · 1 DICTATION"]],
  ["headers count in plural", () => group_title("2026-11-24", 3, now), "TODAY · 3 DICTATIONS"],
  ["f cycles delivered and all", () => ["delivered", "all", "bogus"].map(cycled_filter), ["all", "delivered", "delivered"]],
  ["delivered keeps delivered and unknown outcomes", () => parse(listing).entries.concat([{ outcome: "" }]).map(e => kept_by_filter(e, "delivered")), [true, false, true, true]],
  ["all keeps everything", () => parse(listing).entries.map(e => kept_by_filter(e, "all")), [true, true, true]],
  ["only all shows in the search bar", () => [filter_labels.delivered, filter_labels.all], ["", "ALL"]],
];

let failed = 0;
for (const [name, run, expected] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(run())), expected);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}
if (failed > 0) {
  console.error(failed + " failed");
  process.exit(1);
}
console.log("voxtype_history: " + cases.length + " ok");
