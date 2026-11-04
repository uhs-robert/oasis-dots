// Runs ClipboardFilter.js under node: the clipboard picker's type filter.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/launcher/ClipboardFilter.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { cycled_filter, kept_by_filter, filter_labels };", context);
const { cycled_filter, kept_by_filter, filter_labels } = context.api;

const cases = [
  ["f cycles all, text, images and back", () => ["all", "text", "image", "bogus"].map(cycled_filter), ["text", "image", "all", "all"]],
  ["binary entries show only under all", () => ["all", "text", "image"].map(f => ["text", "image", "binary"].filter(k => kept_by_filter(k, f))), [["text", "image", "binary"], ["text"], ["image"]]],
  ["each filter has a label for the search bar", () => ["all", "text", "image"].map(f => filter_labels[f]), ["ALL", "TEXT", "IMAGES"]],
];

let failed = 0;
for (const [name, run, expected] of cases) {
  try {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(run())), expected);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + ": " + e.message.split("\n")[0]);
  }
}
if (failed > 0) {
  console.error(failed + " failed");
  process.exit(1);
}
console.log("clipboard_filter: " + cases.length + " ok");
