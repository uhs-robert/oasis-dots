// Runs DirectoryFormat.js under node: the path shortening (last 3 dirs whole, 48 chars at most) and the three switches.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const script = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/bar/DirectoryFormat.js"), "utf8").replace(/^\.pragma.*$/gm, "");
const F = vm.createContext({});
vm.runInContext(script, F);

const home = "/home/me";
const all = { app_name: true, path: true, file_name: true };
const off = (...names) => Object.assign({}, all, ...names.map(n => ({ [n]: false })));
const file = "file:/home/me/projects/dotfiles/home/quickshell/init.lua";

const cases = [
  ["empty path is empty", () => F.shorten("", false, home), ""],
  ["home becomes ~", () => F.shorten("/home/me", false, home), "~"],
  ["a short path under home stays whole", () => F.shorten("/home/me/a/b", false, home), "~/a/b"],
  ["dirs above the last three shrink to a letter", () => F.shorten("/home/me/projects/dotfiles/home/quickshell", false, home), "~/p/dotfiles/home/quickshell"],
  ["dot-folders keep their name", () => F.shorten("/home/me/.config/quickshell/features/bar", false, home), "~/.config/quickshell/features/bar"],
  ["a file keeps one more segment", () => F.shorten("/home/me/projects/dotfiles/home/quickshell/init.lua", true, home), "~/p/dotfiles/home/quickshell/init.lua"],
  ["outside home nothing is replaced", () => F.shorten("/etc/systemd/system", false, home), "/etc/systemd/system"],
  ["a home-prefixed sibling is not home", () => F.shorten("/home/meow/x/y/z", false, home), "/h/m/x/y/z"],
  ["no home keeps the absolute path", () => F.shorten("/home/me/x/y/z", false, ""), "/h/m/x/y/z"],
  ["48 chars pass", () => F.shorten("/" + "x".repeat(47), false, home), "/" + "x".repeat(47)],
  ["49 chars are cut from the left at a slash", () => F.shorten("/usr/" + "a".repeat(20) + "/" + "b".repeat(20) + "/" + "c".repeat(20), false, home), "…/" + "b".repeat(20) + "/" + "c".repeat(20)],
  ["a cut never exceeds 48 chars", () => F.shorten("/" + "d".repeat(30) + "/" + "e".repeat(30) + "/" + "f".repeat(30) + "/" + "g".repeat(30), false, home).length <= 48, true],
  ["all on shows a directory", () => F.path_text("/home/me/a/b\n", all, home), "~/a/b"],
  ["path off hides a directory", () => F.path_text("/home/me/a/b", off("path"), home), ""],
  ["all on shows the file with its dirs", () => F.path_text(file, all, home), "~/p/dotfiles/home/quickshell/init.lua"],
  ["file name off shows the file's directory", () => F.path_text(file, off("file_name"), home), "~/p/dotfiles/home/quickshell"],
  ["path off keeps only the file name", () => F.path_text(file, off("path"), home), "init.lua"],
  ["path and file name off hide a file", () => F.path_text(file, off("path", "file_name"), home), ""],
  ["file name off leaves a directory alone", () => F.path_text("/home/me/a", off("file_name"), home), "~/a"],
  ["a file at the root keeps /", () => F.path_text("file:/init.lua", off("file_name"), home), "/"],
  ["empty output is empty", () => F.path_text("  \n", all, home), ""],
  ["app name on", () => F.app_text("Foot", all), "Foot"],
  ["app name off", () => F.app_text("Foot", off("app_name")), ""],
  ["default switches are all on", () => F.default_switches, all],
];

let failed = 0;
for (const [name, run, want] of cases) {
  let got;
  try {
    got = JSON.parse(JSON.stringify(run()));
  } catch (e) {
    got = "threw " + e;
  }
  if (JSON.stringify(got) !== JSON.stringify(want)) {
    failed += 1;
    console.log("FAIL " + name + "\n  want: " + JSON.stringify(want) + "\n  got:  " + JSON.stringify(got));
  }
}
console.log(cases.length - failed + "/" + cases.length + " passed");
process.exit(failed ? 1 : 0);
