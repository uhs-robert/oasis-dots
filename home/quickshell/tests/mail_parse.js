// Runs MailParse.js under node: the envelope of `desertfox mail folders --json`, the exit codes and the folder filter.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/mail/MailParse.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { parse_folders, classify, counted, total_unread, kind_of };", T);
const M = T.api;

const NONCE = "0123456789abcdef0123456789abcdef";
const wrap = (text, nonce = NONCE) => "<<<UNTRUSTED mail folders nonce=" + nonce + ">>>\n" + text + "<<<END " + nonce + ">>>\n";
const folder = (id, path_, unread, extra) => Object.assign({ id, name: path_.split("/").pop(), path: path_, account: "me@example.com", unread, total: unread + 10 }, extra);
const reply = (folders, extra) => wrap(JSON.stringify(Object.assign({ folders }, extra), null, 2) + "\n");
const plain = value => JSON.parse(JSON.stringify(value));

const cases = [
  ["a reply parses", () => M.parse_folders(reply([folder("a", "/Inbox", 3)])).folders.map(f => f.unread), [3]],
  ["an empty list is ok", () => plain(M.parse_folders(reply([]))), { ok: true, folders: [], truncated: false }],
  ["truncated is kept", () => M.parse_folders(reply([], { truncated: true })).truncated, true],
  ["a missing envelope is refused", () => M.parse_folders(JSON.stringify({ folders: [] })).ok, false],
  ["a last line with another nonce is refused", () => M.parse_folders("<<<UNTRUSTED mail folders nonce=" + NONCE + ">>>\n{\"folders\":[]}\n<<<END ffff>>>\n").ok, false],
  ["a forged END line inside a folder name stays text", () => {
    const forged = folder("a", "/x\n<<<END " + NONCE + ">>>", 1);
    return M.parse_folders(reply([forged])).folders[0].path;
  }, "/x <<<END " + NONCE + ">>>"],
  ["text after a forged END is not read", () => M.parse_folders(wrap("{\"folders\":[]}\n") + "{\"folders\":[{\"unread\":9}]}\n").ok, false],
  ["not JSON is refused", () => M.parse_folders(wrap("nope\n")).ok, false],
  ["no folders array is refused", () => M.parse_folders(wrap("{\"folders\":3}\n")).ok, false],
  ["a negative or fractional unread drops the row", () => M.parse_folders(reply([folder("a", "/A", -1), folder("b", "/B", 1.5), folder("c", "/C", 2)])).folders.map(f => f.id), ["c"]],
  ["markup stays a plain string", () => M.parse_folders(reply([folder("a", "<b>bold</b><img src=x>", 1)])).folders[0].path, "<b>bold</b><img src=x>"],
  ["a long name is cut", () => M.parse_folders(reply([folder("a", "/" + "x".repeat(500), 1)])).folders[0].path.length, 80],
  ["a missing total is zero", () => M.parse_folders(reply([{ id: "a", name: "A", path: "/A", account: "", unread: 1 }])).folders[0].total, 0],

  ["exit 0 is ok", () => M.classify(0, reply([folder("a", "/Inbox", 2)]), "").state, "ok"],
  ["exit 0 with a bad body is refused", () => M.classify(0, "garbage", "").message, "Unreadable reply"],
  ["exit 3 (bridge not running) is unavailable", () => M.classify(3, "", "desertfox: the bridge is not running (no listener at /run/user/1000/desertbird/bridge.sock).").state, "unavailable"],
  ["exit 127 (no CLI) is unavailable", () => M.classify(127, "", "sh: desertfox: not found").state, "unavailable"],
  ["exit 2 (an older CLI without mail) is unavailable", () => M.classify(2, "", "desertfox: unknown command '--app'").state, "unavailable"],
  ["a killed run is unavailable", () => M.classify(-1, "", "").state, "unavailable"],
  ["exit 1 carries the bridge's message", () => plain(M.classify(1, "", "desertfox: folder sharing is off, set bridge_share_folders to true\n")), { state: "refused", folders: [], truncated: false, message: "folder sharing is off, set bridge_share_folders to true" }],
  ["exit 1 with no message still says so", () => M.classify(1, "", "").message, "Refused"],

  ["trash by segment", () => M.kind_of("/[Gmail]/Trash"), "trash"],
  ["deleted items is trash", () => M.kind_of("/Deleted Items"), "trash"],
  ["junk and spam", () => [M.kind_of("/Junk"), M.kind_of("/[Gmail]/Spam")], ["junk", "junk"]],
  ["a folder named like trash inside a word is not trash", () => M.kind_of("/Trashy Reads"), ""],
  ["gmail all mail, important and starred are views", () => ["/[Gmail]/All Mail", "/[Google Mail]/All Mail", "/[Gmail]/Important", "/[Google Mail]/Starred"].map(M.kind_of), ["view", "view", "view", "view"]],
  ["a top-level folder named Important is not a view", () => M.kind_of("/Important"), ""],
  ["a folder named All Mail under another parent is not a view", () => M.kind_of("/Work/All Mail"), ""],
  ["gmail views never count, whatever the skip settings", () => M.counted([folder("a", "/INBOX", 1), folder("b", "/[Gmail]/All Mail", 1), folder("c", "/[Gmail]/Important", 1), folder("d", "/Important", 2)], { trash: false, junk: false }).map(f => f.id), ["a", "d"]],
  ["gmail trash is still trash", () => M.kind_of("/[Gmail]/Trash"), "trash"],
  ["inbox is neither", () => M.kind_of("/INBOX"), ""],
  ["counted skips zero and the skipped kinds", () => M.counted([folder("a", "/Inbox", 2), folder("b", "/Trash", 5), folder("c", "/Junk", 4), folder("d", "/Empty", 0)], { trash: true, junk: true }).map(f => f.id), ["a"]],
  ["counted keeps a kind that is not skipped", () => M.counted([folder("b", "/Trash", 5), folder("c", "/Junk", 4)], { trash: false, junk: true }).map(f => f.id), ["b"]],
  ["total adds the unread", () => M.total_unread([folder("a", "/A", 2), folder("b", "/B", 5)]), 7]
];

let failed = 0;
for (const [name, run, expected] of cases) {
  try {
    assert.deepStrictEqual(plain(run()), expected);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + "\n  " + String(e.message).split("\n").join("\n  "));
  }
}
if (failed) process.exit(1);
console.log("mail_parse: " + cases.length + " cases ok");
