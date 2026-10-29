// Runs UsageProjection.js under node: reading the reset text, the year it falls in, the pace maths and the line it
// gives, and the `date` loop ClaudeUsageState runs on the specs. Dates are built on the local clock, so any TZ passes.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");
const { execFileSync } = require("child_process");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/keeptabs/UsageProjection.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { is_weekly, reset_parts, date_spec, project, when_label, describe, week_ms, date_script };", context);
const { is_weekly, reset_parts, date_spec, project, when_label, describe, week_ms, date_script } = context.api;

const hour = 3600000;
const hour_label = h => (h % 12 || 12) + (h < 12 ? "am" : "pm");
// Mon 15 Jun 2026 09:00 local; the week began Mon 8 Jun, with no DST change between in any zone.
const reset = new Date(2026, 5, 15, 9).getTime();
const start = reset - week_ms;

const cases = [
  ["weekly labels only", () => ["Current week (all models)", "Current week (Opus)", "Current session", undefined].map(is_weekly), [true, true, false, false]],
  ["a reset with a zone", () => reset_parts("Nov 2, 9am (Europe/London)", new Date(2026, 9, 30).getTime()), { year: 2026, month: 11, day: 2, hour: 9, minute: 0, zone: "Europe/London" }],
  ["minutes, pm, no comma, no zone", () => reset_parts("Oct 31 5:59pm", new Date(2026, 9, 30).getTime()), { year: 2026, month: 10, day: 31, hour: 17, minute: 59, zone: "" }],
  ["12am is midnight and 12pm noon", () => ["Nov 2, 12am", "Nov 2, 12pm"].map(r => reset_parts(r, reset).hour), [0, 12]],
  ["a long month name and 'at'", () => reset_parts("November 2 at 9am (America/New_York)", reset).zone, "America/New_York"],
  ["Jan read in late Dec is next year", () => reset_parts("Jan 2, 9am (UTC)", new Date(2026, 11, 30).getTime()).year, 2027],
  ["Dec read in early Jan is last year", () => reset_parts("Dec 31, 9am", new Date(2027, 0, 1).getTime()).year, 2026],
  ["text that is not a date is null", () => ["", "9am (Europe/London)", "Foo 3, 9am", "Nov 2, 13pm", "Nov 2", undefined].map(r => reset_parts(r, reset)), [null, null, null, null, null, null]],
  ["a zone that could break out of date's quotes is null", () => ["Nov 2, 9am (Europe/\"x)", "Nov 2, 9am ($(id))", "Nov 2, 9am (a b)"].map(r => reset_parts(r, reset)), [null, null, null]],
  ["the spec date reads", () => [date_spec(reset_parts("Nov 2, 9am (Europe/London)", reset)), date_spec(reset_parts("Jun 20, 5:59pm", reset)), date_spec(null)], ["Europe/London|2026-11-02 09:00", "|2026-06-20 17:59", ""]],
  ["before 12h into the week, no projection", () => project(10, reset, start + 11 * hour), null],
  ["at 12h it shows", () => project(10, reset, start + 12 * hour) !== null, true],
  ["0%, a past reset and an unknown reset show nothing", () => [project(0, reset, start + 3 * 24 * hour), project(50, reset, reset + 1), project(50, NaN, start + 3 * 24 * hour)], [null, null, null]],
  ["half the limit in two days hits it on day four", () => { const p = project(50, reset, start + 48 * hour); return [p.over, (p.full_ms - start) / hour]; }, [true, 96]],
  ["a quarter in four days ends the week near 44%", () => project(25, reset, start + 96 * hour), { over: false, full_ms: start + 384 * hour, end_percent: 44 }],
  ["exactly on pace reaches 100 at the reset, not over", () => project(50, reset, start + 84 * hour).over, false],
  ["the hour rounds to the nearest", () => [when_label(new Date(2026, 9, 30, 15, 29).getTime(), hour_label), when_label(new Date(2026, 9, 30, 15, 30).getTime(), hour_label)], ["Fri 3pm", "Fri 4pm"]],
  ["rounding past midnight moves the day", () => when_label(new Date(2026, 9, 30, 23, 45).getTime(), hour_label), "Sat 12am"],
  ["over pace names the hit time", () => describe("Current week (all models)", 50, reset, start + 48 * hour, hour_label), { shown: true, over: true, text: "At this rate you'll hit the limit by Fri 9am", short: "full by Fri 9am", when: "Fri 9am", end_percent: 175 }],
  ["under pace names the end percent and the reset", () => (({ text, short }) => [text, short])(describe("Current week (Opus)", 25, reset, start + 96 * hour, hour_label)), ["On pace for ~44% by Mon 9am", "~44% by Mon 9am"]],
  ["the session row never projects", () => describe("Current session", 90, reset, start + 96 * hour, hour_label).shown, false],
];

{
  const run = specs => execFileSync("sh", ["-c", date_script, "sh", ...specs], { encoding: "utf8" }).trim().split("\n");
  cases.push(
    ["date reads the spec in its zone", () => run(["Europe/London|2026-11-02 09:00", "America/New_York|2026-11-02 09:00"]), ["1793610000", "1793628000"]],
    ["an unknown zone or bad time is '-', not UTC", () => run(["Bogus/Zone|2026-11-02 09:00", "UTC|2026-13-45 99:00"]), ["-", "-"]],
    ["no zone is local time", () => run(["|2026-11-02 09:00"]), [String(new Date(2026, 10, 2, 9).getTime() / 1000)]],
  );
}

let failed = 0;
for (const [name, fn, expected] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(fn())), expected);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}
if (failed > 0) {
  console.error(failed + " failed");
  process.exit(1);
}
console.log("usage_projection: " + cases.length + " ok");
