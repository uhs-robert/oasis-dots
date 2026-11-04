// Runs LoadGuard.js under node: reading the cpu list, loadavg and hwmon power, the still and resume decision over
// sequences of samples, and the agents.slice quota read from `systemctl --user cat`.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/lock/LoadGuard.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { thread_count, load_ratio, power_ratio, initial, step, locked_quota, window_samples };", context);
const { thread_count, load_ratio, power_ratio, initial, step, locked_quota, window_samples } = context.api;

// The still flag after each sample of `samples` ([load, power] pairs), from a fresh state.
function run(samples, state) {
  let s = state || initial();
  const out = [];
  for (const [load, power] of samples) {
    s = step(s, { load: load, power: power });
    out.push(s.still);
  }
  return { flags: out, state: s };
}

const repeat = (n, sample) => Array.from({ length: n }, () => sample);
const busy = [0.9, NaN];
const idle = [0.2, NaN];
const stilled = run(repeat(window_samples, busy)).state;

const unit = ["# /usr/lib/systemd/user/agents.slice", "[Slice]", "X-LockedCPUQuota=62%", ""].join("\n");

const cases = [
  ["the window is 30 s of 5 s samples", () => window_samples, 6],
  ["a range counts its ends", () => thread_count("0-15\n"), 16],
  ["a mixed cpu list", () => thread_count("0-3,6,8-9"), 7],
  ["an unreadable cpu list is 0", () => ["", "x", "3-1", undefined].map(thread_count), [0, 0, 0, 0]],
  ["load1 per thread", () => load_ratio("12.00 4.88 5.27 4/2920 3581584\n", 16), 0.75],
  ["no threads or bad text is NaN", () => [load_ratio("1.0 1 1", 0), load_ratio("", 16)].map(isNaN), [true, true]],
  ["power over cap", () => power_ratio("31500000\n", "35000000\n"), 0.9],
  ["no cap is NaN", () => [power_ratio("31500000", ""), power_ratio("", "35000000")].map(isNaN), [true, true]],
  ["heavy load stills only once the window is full", () => run(repeat(window_samples, busy)).flags, repeat(window_samples - 1, false).concat([true])],
  ["one spike does not still", () => run(repeat(window_samples - 1, idle).concat([[1.5, NaN]])).flags.some(f => f), false],
  ["a few spikes that lift the mean do", () => run(repeat(4, idle).concat(repeat(2, [2, NaN]))).state.still, true],
  ["the load just under the enter level stays moving", () => run(repeat(window_samples * 2, [0.74, NaN])).state.still, false],
  ["power near the cap stills with light load", () => run(repeat(window_samples, [0.1, 0.92])).state.still, true],
  ["power unknown in some samples uses the known ones", () => run(repeat(3, [0.1, NaN]).concat(repeat(3, [0.1, 0.95]))).state.still, true],
  ["between the levels a still lock stays still", () => run(repeat(window_samples * 3, [0.6, NaN]), stilled).flags.every(f => f), true],
  ["between the levels a moving lock stays moving", () => run(repeat(window_samples * 3, [0.6, NaN])).flags.some(f => f), false],
  ["calm resumes after the window turns calm", () => run(repeat(window_samples, idle), stilled).flags, [true, true, true, false, false, false]],
  ["power still near its leave level holds the lock still", () => run(repeat(window_samples * 2, [0.1, 0.8]), stilled).state.still, true],
  ["a calm machine never stills", () => run(repeat(window_samples * 3, [0.1, 0.3])).flags.some(f => f), false],
  ["no data at all never stills", () => run(repeat(window_samples * 2, [NaN, NaN])).state.still, false],
  ["the window keeps window_samples entries", () => run(repeat(20, busy)).state.loads.length, window_samples],
  ["62% of 16 threads", () => locked_quota(unit, 16), "992%"],
  ["a drop-in's later line wins", () => locked_quota(unit + "\n# drop-in\n[Slice]\nX-LockedCPUQuota = 25\n", 16), "400%"],
  ["an empty later line unsets it", () => locked_quota(unit + "\n[Slice]\nX-LockedCPUQuota=\n", 16), ""],
  ["no key, no unit or no threads is no quota", () => [locked_quota("[Slice]\nCPUWeight=20\n", 16), locked_quota("", 16), locked_quota(unit, 0)], ["", "", ""]],
  ["a commented key does not count", () => locked_quota("[Slice]\n# X-LockedCPUQuota=50%\n", 16), ""],
  ["out of range or not a number is no quota", () => ["0%", "150%", "abc", "-5%"].map(v => locked_quota("X-LockedCPUQuota=" + v, 16)), ["", "", "", ""]],
  ["a tiny share still sets at least 1%", () => locked_quota("X-LockedCPUQuota=1%", 1), "1%"],
];

let failed = 0;
for (const [name, got, want] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(got())), want);
  } catch (e) {
    failed += 1;
    console.log("FAIL " + name + ": " + e.message.split("\n").slice(0, 6).join(" "));
  }
}
console.log(cases.length - failed + "/" + cases.length + " load guard cases pass");
process.exit(failed ? 1 : 0);
