// Runs TmuxWindows.js under node: reading tmux's lists, the session headers, both sorts, the session filter, pane
// cycling, the window the picker opens on and which terminal title shows a session.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const file = path.join(__dirname, "../.config/quickshell/features/launcher/TmuxWindows.js");
const ctx = vm.createContext({});
const names = ["sep", "missing_marker", "list_argv", "captures_argv", "split_captures", "parse_tails", "short_path", "parse_list", "sorts", "sort_labels", "sort_of", "cycled_sort", "arranged", "kept_order", "group_title", "cycled_filter", "kept_by_filter", "shown_filter", "filter_label", "cycled_pane", "pane_of", "pane_label", "client_of", "latest_client", "initial_index", "title_matches"];
vm.runInContext(fs.readFileSync(file, "utf8").replace(/^\.pragma.*$/m, "") + "\nthis.api = { " + names.join(", ") + " };", ctx);
const T = ctx.api;

const line = (...f) => f.join(T.sep);
// As tmux prints them: sessions, then every window, every pane and every client.
const listed = [
  line("S", "$1", "work", "1"),
  line("S", "$2", "notes", "0"),
  line("S", "$3", "empty", "0"),
  line("W", "$1", "@2", "2", "logs", "0", "300", "120", "30", "1"),
  line("W", "$1", "@1", "1", " edit ", "1", "100", "160", "40", "0"),
  line("W", "$2", "@5", "0", "todo", "1", "200", "80", "24", "0"),
  line("P", "@1", "%2", "80", "0", "1", "nvim", "/home/me/src", "80", "40"),
  line("P", "@1", "%1", "0", "0", "0", "zsh", "/home/me", "79", "19"),
  line("P", "@1", "%3", "0", "20", "0", "htop", "/tmp", "79", "20"),
  line("P", "@2", "%4", "0", "0", "1", "tail", "/var/log", "120", "30"),
  line("P", "@5", "%5", "0", "0", "1", "vim", "/home/me/notes", "80", "24"),
  line("C", "/dev/pts/1", "$1", "50"),
  line("C", "/dev/pts/2", "$2", "90"),
].join("\n");
const model = T.parse_list(listed, "/home/me");
const items = model.items;
const by_id = id => items.find(i => i.window_id === id);
// Window @7 linked into both sessions: `list-windows -a` and `list-panes -a` print it, and its pane, once per session.
const linked = T.parse_list([
  line("S", "$1", "work", "1"),
  line("S", "$2", "notes", "0"),
  line("W", "$1", "@7", "0", "shared", "1", "100"),
  line("W", "$2", "@7", "3", "shared", "0", "100"),
  line("P", "@7", "%9", "0", "0", "1", "vim", "/tmp"),
  line("P", "@7", "%9", "0", "0", "1", "vim", "/tmp"),
].join("\n"), "");

const cases = [
  ["no tmux binary reads as missing", () => T.parse_list(T.missing_marker + "\n", "").state, "missing"],
  ["no server (no output) reads as none", () => [T.parse_list("", "").state, T.parse_list("", "").items.length], ["none", 0]],
  ["a list reads as ok", () => model.state, "ok"],
  ["the list goes through sh, so a missing tmux prints the marker", () => [T.list_argv()[0], T.list_argv().indexOf("list-sessions") > 0], ["sh", true]],
  ["sessions keep tmux's order and a session with no windows is dropped", () => model.sessions.map(s => s.name + s.number), ["work1", "notes2"]],
  ["windows go by session, then by index", () => items.map(i => i.window_id), ["@1", "@2", "@5"]],
  ["a window name is trimmed into the label", () => by_id("@1").label, "edit"],
  ["panes are in reading order: top, then left", () => by_id("@1").panes.map(p => p.pane_id), ["%1", "%2", "%3"]],
  ["the active pane gives the command and short path", () => [by_id("@1").active_pane, by_id("@1").cmd, by_id("@1").short_path], ["%2", "nvim", "~/src"]],
  ["search covers the session, every command and every short path", () => [by_id("@1").description, by_id("@1").keywords], ["work", ["zsh", "nvim", "htop", "~", "~/src", "/tmp"]]],
  ["home shortens only at a path boundary", () => [T.short_path("/home/me", "/home/me"), T.short_path("/home/meg/x", "/home/me"), T.short_path("/x", "")], ["~", "/home/meg/x", "/x"]],
  ["s flips the sort, and an unknown sort is sessions", () => [T.cycled_sort("sessions"), T.cycled_sort("recent"), T.sort_of("bogus")], ["recent", "sessions", "sessions"]],
  ["recent orders by window activity, newest first", () => T.arranged(items, "recent", "all").map(i => i.window_id), ["@2", "@5", "@1"]],
  ["session order keeps the list", () => T.arranged(items, "sessions", "all").map(i => i.window_id), ["@1", "@2", "@5"]],
  ["the header counts the shown windows and says attached", () => [T.group_title("$1", 2, model.sessions), T.group_title("$2", 1, model.sessions)], ["SESSION 1 · work · 2 WINDOWS · ATTACHED", "SESSION 2 · notes · 1 WINDOW"]],
  ["a gone session has no header", () => T.group_title("$9", 1, model.sessions), ""],
  ["f cycles all, each session, then all", () => [T.cycled_filter("all", model.sessions), T.cycled_filter("$1", model.sessions), T.cycled_filter("$2", model.sessions)], ["$1", "$2", "all"]],
  ["a gone session cycles back to all, and with none all stays", () => [T.cycled_filter("$9", model.sessions), T.cycled_filter("all", [])], ["all", "all"]],
  ["the filter keeps one session's windows in either sort", () => [T.arranged(items, "sessions", "$1").map(i => i.window_id), T.arranged(items, "recent", "$1").map(i => i.window_id)], [["@1", "@2"], ["@2", "@1"]]],
  ["a filter on a gone session shows all", () => [T.shown_filter("$9", model.sessions), T.shown_filter("$2", model.sessions)], ["all", "$2"]],
  ["the corner names the session's place", () => [T.filter_label("all", model.sessions), T.filter_label("$2", model.sessions), T.filter_label("$9", model.sessions)], ["ALL", "SESSION 2/2", "ALL"]],
  ["] steps from the active pane in reading order, and wraps", () => [T.cycled_pane(by_id("@1"), "", 1), T.cycled_pane(by_id("@1"), "%2", 1), T.cycled_pane(by_id("@1"), "%3", 1)], ["%2", "%3", "%1"]],
  ["[ steps back and wraps", () => [T.cycled_pane(by_id("@1"), "%1", -1), T.cycled_pane(by_id("@1"), "%2", -1)], ["%3", "%1"]],
  ["a window with no panes cycles to nothing", () => T.cycled_pane({ panes: [] }, "", 1), ""],
  ["the shown pane is the chosen one, else the active one", () => [T.pane_of(by_id("@1"), "%3").pane_id, T.pane_of(by_id("@1"), "").pane_id, T.pane_of(by_id("@1"), "%99").pane_id, T.pane_of(null, "")], ["%3", "%2", "%2", null]],
  ["the preview corner names the pane's place and command", () => T.pane_label(by_id("@1"), T.pane_of(by_id("@1"), "%3")), "PANE 3/3 · htop"],
  ["the latest client is the most recently active", () => T.latest_client(model.clients).name, "/dev/pts/2"],
  ["client_of picks a session's own client, or none", () => [T.client_of(model.clients, "$1").name, T.client_of(model.clients, "$3")], ["/dev/pts/1", null]],
  ["the picker opens on the window the latest client shows", () => [T.initial_index(items, model.clients), T.initial_index(T.arranged(items, "recent", "all"), model.clients)], [2, 1]],
  ["no client opens on the first window", () => T.initial_index(items, []), 0],
  ["the tails keep each pane's last lines with text", () => T.parse_tails(T.sep + "PANE" + T.sep + "%1\na\n\nb\nc\n\n" + T.sep + "PANE" + T.sep + "%2\n", 2), { "%1": "b\nc", "%2": "" }],
  ["session order sorts by session then index, whatever order it gets", () => T.arranged(T.arranged(items, "recent", "all"), "sessions", "all").map(i => i.window_id), ["@1", "@2", "@5"]],
  ["a reload keeps the shown order though activity changed", () => T.kept_order(T.arranged(items, "recent", "all"), items.map(i => Object.assign({}, i, { activity: i.id === "@1" ? 999 : i.activity })), "recent").map(i => i.window_id), ["@2", "@5", "@1"]],
  ["a reload takes the fresh fields of a kept window", () => T.kept_order(items, items.map(i => Object.assign({}, i, { label: i.label + "!" })), "sessions").map(i => i.label), ["edit!", "logs!", "todo!"]],
  ["a reload drops a gone window", () => T.kept_order(items, items.filter(i => i.window_id !== "@2"), "sessions").map(i => i.window_id), ["@1", "@5"]],
  ["session sort: a new window goes after its session's last row", () => T.kept_order(items, items.concat([Object.assign({}, by_id("@1"), { id: "$1:@9", window_id: "@9", index: 0 })]), "sessions").map(i => i.window_id), ["@1", "@2", "@9", "@5"]],
  ["session sort: a new session's window goes at the end", () => T.kept_order(items, items.concat([Object.assign({}, by_id("@1"), { id: "$7:@9", window_id: "@9", session_id: "$7", session_number: 0 })]), "sessions").map(i => i.window_id), ["@1", "@2", "@5", "@9"]],
  ["recent sort: new windows go at the end, newest first", () => T.kept_order([by_id("@5")], items, "recent").map(i => i.window_id), ["@5", "@2", "@1"]],
  ["a row's id names its session and window, and keeps the window id apart", () => [by_id("@1").id, by_id("@1").window_id], ["$1:@1", "@1"]],
  ["a linked window gets one row per session, each with its own id", () => linked.items.map(i => [i.id, i.window_id, i.index]), [["$1:@7", "@7", 0], ["$2:@7", "@7", 3]]],
  ["a linked window's pane is listed once, not once per session", () => linked.items.map(i => i.panes.map(p => p.pane_id)), [["%9"], ["%9"]]],
  ["a reload keeps both rows of a linked window apart", () => T.kept_order(linked.items, linked.items.slice().reverse(), "sessions").map(i => i.id), ["$1:@7", "$2:@7"]],
  ["the filter keeps only one session's row of a linked window", () => T.arranged(linked.items, "sessions", "$2").map(i => i.id), ["$2:@7"]],
  ["the captures pass pane ids as arguments, not in the script", () => T.captures_argv(["%1", "%2"], true).slice(-2), ["%1", "%2"]],
  ["only a styled capture keeps the colour codes", () => [T.captures_argv(["%1"], true)[2].indexOf("-e") >= 0, T.captures_argv(["%1"], false)[2].indexOf("-e") >= 0], [true, false]],
  ["the captures split per pane, a gone pane missing", () => T.split_captures(T.sep + "PANE" + T.sep + "%1\na\n b\n" + T.sep + "PANE" + T.sep + "\n" + T.sep + "PANE" + T.sep + "%3\n\n"), { "%1": ["a", " b"], "%3": ["", ""] }],
  ["a window reads its size in cells and whether it is zoomed", () => [by_id("@1").width, by_id("@1").height, by_id("@1").zoomed, by_id("@2").zoomed], [160, 40, false, true]],
  ["a pane reads its size in cells", () => by_id("@1").panes.map(p => [p.pane_id, p.width, p.height]), [["%1", 79, 19], ["%2", 80, 40], ["%3", 79, 20]]],
];

const names_dev = ["Dev", "Dev tools", "nvim"];
const title_cases = [
  ["title: the bare session name", () => T.title_matches("UpHill", "UpHill"), true],
  ["title: session and program", () => T.title_matches("UpHill nvim", "UpHill"), true],
  ["title: layout prefix", () => T.title_matches("Tmux Config", "Config"), true],
  ["title: layout prefix and program", () => T.title_matches("Tmux Config zsh", "Config"), true],
  ["title: a name that only starts the same is no match", () => T.title_matches("UpHill2 nvim", "UpHill"), false],
  ["title: another session", () => T.title_matches("Other", "UpHill"), false],
  ["title: a program named like a session is not that session", () => T.title_matches("UpHill nvim", "nvim", ["UpHill", "nvim"]), false],
  ["title: the shorter name loses to a longer one that fits", () => T.title_matches("Dev tools nvim", "Dev", names_dev), false],
  ["title: the longer name wins", () => T.title_matches("Dev tools nvim", "Dev tools", names_dev), true],
  ["title: the shorter name still matches its own title", () => T.title_matches("Dev zsh", "Dev", names_dev), true],
  ["title: layout prefix, the shorter name loses", () => T.title_matches("Tmux Dev tools zsh", "Dev", names_dev), false],
];

let failed = 0;
const all = cases.concat(title_cases);
for (const [name, run, want] of all) {
  let got;
  try {
    got = JSON.parse(JSON.stringify(run()));
    assert.deepStrictEqual(got, want);
  } catch (e) {
    failed += 1;
    console.log("FAIL " + name + "\n  want: " + JSON.stringify(want) + "\n  got:  " + (got === undefined ? e : JSON.stringify(got)));
  }
}
console.log(all.length - failed + "/" + all.length + " passed");
process.exit(failed ? 1 : 0);
