// Runs TmuxData.title_matches under node: a kitty title names its session, with the program after it and "Tmux " before it for a layout.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const script = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/overview/TmuxData.js"), "utf8").replace(/^\.pragma.*$/gm, "");
const D = vm.createContext({});
vm.runInContext(script + "\nthis.title_matches = title_matches;", D);

const names = ["Dev", "Dev tools", "nvim"];
const cases = [
  ["the bare session name", () => D.title_matches("UpHill", "UpHill"), true],
  ["session and program", () => D.title_matches("UpHill nvim", "UpHill"), true],
  ["layout prefix", () => D.title_matches("Tmux Config", "Config"), true],
  ["layout prefix and program", () => D.title_matches("Tmux Config zsh", "Config"), true],
  ["a name that only starts the same is no match", () => D.title_matches("UpHill2 nvim", "UpHill"), false],
  ["another session", () => D.title_matches("Other", "UpHill"), false],
  ["a program named like a session is not that session", () => D.title_matches("UpHill nvim", "nvim", ["UpHill", "nvim"]), false],
  ["the shorter name loses to a longer one that fits", () => D.title_matches("Dev tools nvim", "Dev", names), false],
  ["the longer name wins", () => D.title_matches("Dev tools nvim", "Dev tools", names), true],
  ["the shorter name still matches its own title", () => D.title_matches("Dev zsh", "Dev", names), true],
  ["layout prefix: the shorter name loses", () => D.title_matches("Tmux Dev tools zsh", "Dev", names), false],
];

let failed = 0;
for (const [name, run, want] of cases) {
  let got;
  try {
    got = run();
  } catch (e) {
    got = "threw " + e;
  }
  if (got !== want) {
    failed += 1;
    console.log("FAIL " + name + "\n  want: " + want + "\n  got:  " + got);
  }
}
console.log(cases.length - failed + "/" + cases.length + " passed");
process.exit(failed ? 1 : 0);
