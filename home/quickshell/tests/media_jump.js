// Runs MediaJump.js under node: which MPRIS players count as Firefox and which tab a jump lands on.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/media/MediaJump.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { is_firefox_player, pick_tab, raise_filter };", T);
const M = T.api;

const { execFileSync } = require("child_process");
const raised = clients => execFileSync("jq", ["-r", M.raise_filter], { input: JSON.stringify(clients) }).toString().trim();
const win = (address, cls, history) => ({ address, class: cls, focusHistoryID: history });

const tab = (id, title, extra) => Object.assign({ tab_id: id, window_id: 1, title, url: "https://example.com/" + id, audible: false, last_accessed: 0 }, extra);
const pick = (rows, title, url, playing) => {
  const t = M.pick_tab(rows, title, url, playing);
  return t ? t.tab_id : null;
};

const cases = [
  ["firefox desktop entry", () => M.is_firefox_player("firefox", ""), true],
  ["firefox-esr desktop entry", () => M.is_firefox_player("firefox-esr", ""), true],
  ["flatpak desktop entry", () => M.is_firefox_player("org.mozilla.firefox", ""), true],
  ["entry is case-insensitive", () => M.is_firefox_player("Firefox", ""), true],
  ["bus name alone", () => M.is_firefox_player("", "org.mpris.MediaPlayer2.firefox.instance_123"), true],
  ["a set entry beats the bus name", () => M.is_firefox_player("spotify", "org.mpris.MediaPlayer2.firefox.instance_1"), false],
  ["spotify", () => M.is_firefox_player("spotify", "org.mpris.MediaPlayer2.spotify"), false],
  ["nothing known", () => M.is_firefox_player("", ""), false],
  ["missing values", () => M.is_firefox_player(undefined, null), false],
  ["a bus name that only ends in firefox", () => M.is_firefox_player("", "org.mpris.MediaPlayer2.firefox"), false],

  ["raise: the most recently focused Firefox window", () => raised([win("0xa", "firefox", 3), win("0xb", "firefox", 1), win("0xc", "kitty", 0)]), "0xb"],
  ["raise: a never-focused Firefox window is skipped", () => raised([win("0xa", "firefox", -1), win("0xb", "firefox", 4), win("0xc", "kitty", 0)]), "0xb"],
  ["raise: only a never-focused Firefox window gives nothing", () => raised([win("0xa", "firefox", -1), win("0xc", "kitty", 0)]), ""],
  ["raise: flatpak and mixed-case classes count", () => raised([win("0xa", "org.mozilla.firefox", 2), win("0xb", "Firefox", 5)]), "0xa"],
  ["raise: a class that only contains firefox does not", () => raised([win("0xa", "notfirefox", 0)]), ""],
  ["raise: no clients", () => raised([]), ""],
  ["one audible tab", () => pick([tab(1, "a"), tab(2, "b", { audible: true })], "x", "", true), 2],
  ["title match beats recency among audible tabs", () => pick([tab(1, "Song A - YouTube", { audible: true, last_accessed: 5 }), tab(2, "Song B - YouTube", { audible: true, last_accessed: 9 })], "Song A", "", true), 1],
  ["url match beats recency", () => pick([tab(1, "x", { audible: true, last_accessed: 5, url: "https://v/1" }), tab(2, "y", { audible: true, last_accessed: 9, url: "https://v/2" })], "", "https://v/1", true), 1],
  ["an exact url beats a more recent title match", () => pick([tab(1, "Song A", { audible: true, last_accessed: 9, url: "https://v/other" }), tab(2, "Different", { audible: true, last_accessed: 1, url: "https://v/2" })], "Song A", "https://v/2", true), 2],
  ["an exact url beats a title match when paused", () => pick([tab(1, "Song A", { last_accessed: 9 }), tab(2, "Other", { last_accessed: 1, url: "https://v/2" })], "Song A", "https://v/2", false), 2],
  ["no match among audible tabs: most recent wins", () => pick([tab(1, "a", { audible: true, last_accessed: 5 }), tab(2, "b", { audible: true, last_accessed: 9 })], "zzz", "", true), 2],
  ["title match ignores whitespace differences", () => pick([tab(1, "Song   A", { audible: true }), tab(2, "Other", { audible: true, last_accessed: 9 })], " Song A ", "", true), 1],
  ["a non-audible title match is ignored while others are audible", () => pick([tab(1, "Song A"), tab(2, "Other", { audible: true })], "Song A", "", true), 2],
  ["playing with no audible tab matches by title across all", () => pick([tab(1, "a"), tab(2, "Song A")], "Song A", "", true), 2],
  ["playing with no audible tab and no match: nothing", () => pick([tab(1, "a")], "Song A", "", true), null],
  ["paused matches by title across all tabs", () => pick([tab(1, "a"), tab(2, "Song A - YouTube")], "Song A", "", false), 2],
  ["paused with two title matches: most recent", () => pick([tab(1, "Song A", { last_accessed: 3 }), tab(2, "Song A", { last_accessed: 8 })], "Song A", "", false), 2],
  ["paused with no match: nothing, never a guess", () => pick([tab(1, "a", { audible: true, last_accessed: 9 })], "Song A", "", false), null],
  ["hidden tabs are skipped", () => pick([tab(1, "Song A", { hidden: true, audible: true }), tab(2, "b", { audible: true })], "Song A", "", true), 2],
  ["an empty track title never matches everything", () => pick([tab(1, "a"), tab(2, "b")], "", "", false), null],
  ["rows without a numeric id are skipped", () => pick([{ title: "Song A", audible: true }, tab(2, "b", { audible: true })], "Song A", "", true), 2],
  ["missing last_accessed counts as zero", () => pick([tab(1, "a", { audible: true, last_accessed: undefined }), tab(2, "b", { audible: true, last_accessed: 1 })], "q", "", true), 2],
  ["not a list", () => pick(null, "a", "", true), null],
  ["empty list", () => pick([], "a", "", true), null],
];

let failed = 0;
for (const [name, run, want] of cases) {
  try {
    assert.deepStrictEqual(run(), want);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}
if (failed) process.exit(1);
console.log("media jump: " + cases.length + " checks passed");
