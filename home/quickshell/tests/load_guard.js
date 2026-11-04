// Runs LoadGuard.js under node: reading the cpu list, loadavg, hwmon power and the agents.slice CPU rate, the still and resume decision over
// sequences of samples, and the agents.slice quota read from `systemctl --user cat`.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/lock/LoadGuard.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { thread_count, load_ratio, power_ratio, initial, step, locked_quota, window_samples, status_uid, agents_cpu_stat_path, usage_usec, agents_ratio };", context);
const { thread_count, load_ratio, power_ratio, initial, step, locked_quota, window_samples, status_uid, agents_cpu_stat_path, usage_usec, agents_ratio } = context.api;

// The still flag after each sample of `samples` ([load, power, agents] triples, agents NaN when left out), from a
// fresh state.
function run(samples, state) {
  let s = state || initial();
  const out = [];
  for (const [load, power, agents] of samples) {
    s = step(s, { agents: agents === undefined ? NaN : agents, load: load, power: power });
    out.push(s.still);
  }
  return { flags: out, state: s };
}

const repeat = (n, sample) => Array.from({ length: n }, () => sample);
const busy = [0.9, NaN];
const idle = [0.2, NaN];
const stilled = run(repeat(window_samples, busy)).state;

// Agent shares with the load average pinned high, so only the agent rate can decide.
const agent = share => [0.9, NaN, share];
const agents_stilled = run(repeat(window_samples, agent(0.3))).state;
const stat = usec => "usage_usec " + usec + "\nuser_usec 1\nsystem_usec 1\n";

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
  ["the uid comes from the real Uid column", () => status_uid("Name:\tqs\nUid:\t1000\t1000\t1000\t1000\n"), "1000"],
  ["no Uid line is no uid", () => status_uid("Name:\tqs\n"), ""],
  ["the agents cpu.stat path", () => agents_cpu_stat_path("/fix", "1000"), "/fix/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/agents.slice/cpu.stat"],
  ["no uid is no path", () => agents_cpu_stat_path("", ""), ""],
  ["usage_usec reads its own line only", () => [usage_usec(stat(5544922601)), isNaN(usage_usec("user_usec 5\n")), isNaN(usage_usec(""))], [5544922601, true, true]],
  ["4 threads busy for 5 s is a quarter of 16", () => agents_ratio({ usec: 1000000, ms: 0 }, { usec: 21000000, ms: 5000 }, 16), 0.25],
  ["the first reading has no rate", () => isNaN(agents_ratio(null, { usec: 5, ms: 5000 }, 16)), true],
  ["a missing reading has no rate", () => [agents_ratio({ usec: 5, ms: 0 }, { usec: NaN, ms: 5000 }, 16), agents_ratio({ usec: NaN, ms: 0 }, { usec: 5, ms: 5000 }, 16)].map(isNaN), [true, true]],
  ["a counter that went back has no rate, not a spike", () => isNaN(agents_ratio({ usec: 9e12, ms: 0 }, { usec: 1000, ms: 5000 }, 16)), true],
  ["no time passed or no threads has no rate", () => [agents_ratio({ usec: 0, ms: 5 }, { usec: 9, ms: 5 }, 16), agents_ratio({ usec: 0, ms: 0 }, { usec: 9, ms: 5 }, 0)].map(isNaN), [true, true]],
  ["agents over a quarter still the lock, on agents", () => [agents_stilled.still, agents_stilled.trigger], [true, "agents"]],
  ["agents decide over a high load average", () => run(repeat(window_samples * 2, agent(0.2))).state.still, false],
  ["a first sample with no rate does not block the decision", () => run([agent(NaN)].concat(repeat(window_samples - 1, agent(0.3)))).flags.slice(-1)[0], true],
  ["between the agent levels a still lock stays still", () => run(repeat(window_samples * 2, agent(0.2)), agents_stilled).state.still, true],
  ["agents under an eighth resume, on agents", () => { const s = run(repeat(window_samples, agent(0.1)), agents_stilled).state; return [s.still, s.trigger]; }, [false, "agents"]],
  ["without agents.slice the load average decides", () => [stilled.still, stilled.trigger], [true, "load"]],
  ["power names itself when it alone stills", () => run(repeat(window_samples, [0.1, 0.95, 0.01])).state.trigger, "power"],
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
