// Runs AgentSessions.js under node: the row parsing and tmux argv behind the agent sessions picker.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/launcher/AgentSessions.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { parse_sessions, capture_argv };", context);
const { parse_sessions, capture_argv } = context.api;
const plain = value => JSON.parse(JSON.stringify(value));
const home = "/home/me";

const cases = [
  ["bad json gives no rows", () => parse_sessions("not json", home), []],
  ["non-list gives no rows", () => parse_sessions("{\"id\":\"a\"}", home), []],
  ["empty output gives no rows", () => parse_sessions("", home), []],
  ["rows without an id are dropped", () => parse_sessions("[null, {\"agent\":\"claude\"}, 3]", home), []],
  ["state running reads as working", () => parse_sessions("[{\"id\":\"a\",\"agent\":\"claude\",\"state\":\"running\",\"title\":\"T\",\"cwd\":\"/home/me/x\"}]", home).map(r => [r.label, r.description]), [["T", "claude · working · ~/x"]]],
  ["state done reads as idle", () => parse_sessions("[{\"id\":\"a\",\"agent\":\"codex\",\"state\":\"done\",\"cwd\":\"/home/me\"}]", home).map(r => [r.label, r.description]), [["codex", "codex · idle · ~"]]],
  ["cwd outside home stays whole", () => parse_sessions("[{\"id\":\"a\",\"agent\":\"c\",\"cwd\":\"/home/mexyz\"}]", home)[0].description, "c · /home/mexyz"],
  ["numeric id becomes a string", () => parse_sessions("[{\"id\":7}]", home)[0].id, "7"],
  ["missing tmux fields become empty", () => { const r = parse_sessions("[{\"id\":\"a\"}]", home)[0]; return [r.tmux_socket, r.tmux_pane]; }, ["", ""]],
  ["capture with a socket", () => capture_argv({ tmux_socket: "/run/t.sock", tmux_pane: "%4" }), ["tmux", "-S", "/run/t.sock", "capture-pane", "-p", "-e", "-t", "%4"]],
  ["capture without a socket leaves -S out", () => capture_argv({ tmux_socket: "", tmux_pane: "%4" }), ["tmux", "capture-pane", "-p", "-e", "-t", "%4"]],
];

let failed = 0;
for (const [name, run, expected] of cases) {
  try {
    assert.deepStrictEqual(plain(run()), expected);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}
if (failed > 0) {
  console.error(failed + " failed");
  process.exit(1);
}
console.log("agent_sessions: " + cases.length + " ok");
