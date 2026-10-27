// Runs AgentSessions.js under node: the row parsing, tmux argv and pane tails behind the agent sessions picker.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");
const os = require("os");
const { execFileSync } = require("child_process");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/launcher/AgentSessions.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { parse_sessions, capture_argv, split_capture, last_line, tails_argv, parse_tails };", context);
const { parse_sessions, capture_argv, split_capture, last_line, tails_argv, parse_tails } = context.api;
const plain = value => JSON.parse(JSON.stringify(value));
const home = "/home/me";

// tails_argv's script run for real against a stub tmux that prints a canned capture per pane ("gone" fails like a closed pane).
const stub_dir = fs.mkdtempSync(path.join(os.tmpdir(), "agent-tails-"));
fs.writeFileSync(path.join(stub_dir, "tmux"), [
  "#!/bin/sh",
  "for a; do last=$a; done",
  "case \"$1 $last\" in",
  "  \"-S %1\") printf 'socket %s\\nworking on it\\n\\n' \"$2\" ;;",
  "  *\" %2\") printf 'default server\\n\\342\\225\\255\\342\\224\\200\\342\\225\\256\\n' ;;",
  "  *) echo 'no pane' >&2; exit 1 ;;",
  "esac",
].join("\n") + "\n", { mode: 0o755 });
const run_tails = entries => {
  const argv = tails_argv(entries);
  return parse_tails(execFileSync(argv[0], argv.slice(1), { encoding: "utf8", env: { PATH: stub_dir + ":/usr/bin:/bin" } }));
};

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
  // req: PICKERS-09
  ["a row carries its agent, state and short cwd for the card", () => { const r = parse_sessions("[{\"id\":\"a\",\"agent\":\"claude\",\"state\":\"waiting\",\"cwd\":\"/home/me/x\"}]", home)[0]; return [r.agent, r.state, r.cwd_short]; }, ["claude", "waiting", "~/x"]],
  // req: PICKERS-08
  ["capture with a socket asks for the width first", () => capture_argv({ tmux_socket: "/run/t.sock", tmux_pane: "%4" }), ["tmux", "-S", "/run/t.sock", "display-message", "-p", "-t", "%4", "#{pane_width}", ";", "capture-pane", "-p", "-e", "-t", "%4"]],
  ["capture without a socket leaves -S out", () => capture_argv({ tmux_socket: "", tmux_pane: "%4" }), ["tmux", "display-message", "-p", "-t", "%4", "#{pane_width}", ";", "capture-pane", "-p", "-e", "-t", "%4"]],
  // req: PICKERS-08
  ["the width line splits off the capture", () => split_capture("212\nline one\nline two\n"), { width: 212, text: "line one\nline two\n" }],
  ["a capture without a width line keeps all its text", () => split_capture("line one\n"), { width: 0, text: "line one\n" }],
  ["a width with no capture after it", () => split_capture("80"), { width: 80, text: "" }],
  // req: PICKERS-09
  ["last line skips blank rows below it", () => last_line("first\nDone, tests pass.\n\n  \n"), "Done, tests pass."],
  ["last line skips a TUI's input box frame", () => last_line("Edited Picker.qml\n╭───╮\n│ >            │\n╰───╯\n"), "Edited Picker.qml"],
  ["last line trims the frame around words", () => last_line("│ > fix the bar │\n"), "fix the bar"],
  ["last line squeezes column padding", () => last_line("  ? for shortcuts" + " ".repeat(40) + "ctx 55%\n"), "? for shortcuts  ctx 55%"],
  ["a pane with no words has no last line", () => last_line("\n───\n"), ""],
  // req: PICKERS-09
  ["tails come back per session id", () => run_tails([{ id: "a", tmux_socket: "/run/t.sock", tmux_pane: "%1" }, { id: "b", tmux_socket: "", tmux_pane: "%2" }]), { a: "working on it", b: "default server" }],
  ["a gone pane or no pane gives an empty tail and keeps the rest", () => run_tails([{ id: "a", tmux_socket: "", tmux_pane: "%9" }, { id: "b", tmux_socket: "", tmux_pane: "" }, { id: "c", tmux_socket: "/s", tmux_pane: "%1" }]), { a: "", b: "", c: "working on it" }],
  ["no output gives no tails", () => parse_tails(""), {}],
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
fs.rmSync(stub_dir, { recursive: true, force: true });
if (failed > 0) {
  console.error(failed + " failed");
  process.exit(1);
}
console.log("agent_sessions: " + cases.length + " ok");
