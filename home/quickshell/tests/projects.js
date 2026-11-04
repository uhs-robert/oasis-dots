// Runs Projects.js under node: the layout names, reading the listing and matching layouts to running sessions. The
// listing script itself runs against a temp layout dir with tmux kept off the PATH.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const vm = require("vm");
const assert = require("assert");
const child_process = require("child_process");

const file = path.join(__dirname, "../.config/quickshell/features/launcher/Projects.js");
const ctx = vm.createContext({});
const names = ["list_script", "pretty_name", "parse_listing", "session_of", "items_of"];
vm.runInContext(fs.readFileSync(file, "utf8").replace(/^\.pragma.*$/m, "") + "\nthis.api = { " + names.join(", ") + " };", ctx);
const P = ctx.api;

function run_listing(layouts) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "projects-test-"));
  try {
    for (const [name, body] of Object.entries(layouts)) fs.writeFileSync(path.join(dir, name), body);
    fs.mkdirSync(path.join(dir, "folder.session.sh"));
    const env = { PATH: "/usr/bin:/bin", HOME: dir, TMUXIFIER_LAYOUT_PATH: dir };
    // A stub tmux on the PATH answers list-sessions, so the owner's server is never asked.
    const bin = path.join(dir, "bin");
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, "tmux"), "#!/bin/sh\nprintf 'S\\tweb\\nS\\tdots\\n'\n", { mode: 0o755 });
    env.PATH = bin + ":" + env.PATH;
    return child_process.execFileSync("sh", ["-c", P.list_script], { env: env, encoding: "utf8" });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const listing = P.parse_listing("L\tweb-app\t\nL\tdotfiles\tdots\nL\tnotes\t\nS\tdots\nS\tscratch\n");
const items = P.items_of(listing);

const cases = [
  ["dashes and underscores become spaces, each word capitalised", () => [P.pretty_name("my-web_app"), P.pretty_name("a--b__c"), P.pretty_name("-lead_")], ["My Web App", "A B C", "Lead"]],
  ["a capital inside a word stays", () => P.pretty_name("myAPI"), "MyAPI"],
  ["the listing splits into layouts and sessions", () => listing, { layouts: [{ stem: "web-app", session_name: "" }, { stem: "dotfiles", session_name: "dots" }, { stem: "notes", session_name: "" }], sessions: ["dots", "scratch"] }],
  ["blank and unknown lines are skipped", () => P.parse_listing("\nX\tfoo\nL\t\n"), { layouts: [], sessions: [] }],
  ["a layout's session is its session_name, else its file name", () => listing.layouts.map(P.session_of), ["web-app", "dots", "notes"]],
  ["layouts sort by file name", () => items.map(i => i.id), ["dotfiles", "notes", "web-app"]],
  ["a running session marks its layout by session_name", () => items.map(i => i.running), [true, false, false]],
  ["a session named like the file does not mark a layout with another session_name", () => P.items_of(P.parse_listing("L\tdotfiles\tdots\nS\tdotfiles\n"))[0].running, false],
  ["the match is exact, not by case or prefix", () => P.items_of(P.parse_listing("L\tweb\t\nS\tWeb\nS\tweb-2\n"))[0].running, false],
  ["a running layout carries the dot, the rest a blank glyph", () => items.map(i => i.glyph), ["\u25cf", " ", " "]],
  ["the label is the pretty name; the stem and session are searchable", () => [items[0].label, items[0].keywords, items[0].description, items[2].description], ["Dotfiles", ["dotfiles", "dots"], "dots · running", "web-app"]],
  ["the script lists each layout file with its session_name, then the sessions", () => P.parse_listing(run_listing({
    "web.session.sh": "session_root \"~/web\"\n  session_name=\"site\" # set\nsession_name=\"later\"\n",
    "plain_one.session.sh": "new_window\n",
    "notes.window.sh": "new_window\n",
  })), { layouts: [{ stem: "plain_one", session_name: "" }, { stem: "web", session_name: "site" }], sessions: ["web", "dots"] }],
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
console.log("projects: " + cases.length + " checks passed");
