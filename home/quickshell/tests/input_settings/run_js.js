// Runs vectors.tsv through HyprInputValidation.js, the bar's validator, under node. The file is a QML
// `.pragma library`, so it is loaded as a script, as notification_markup.js does. Values are decoded with JSON.parse,
// which is the path the bar's JsonStore takes; run_lua.lua is the Lua twin.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const source = fs.readFileSync(path.join(__dirname, "../../.config/quickshell/features/settings/HyprInputValidation.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, ""), context);

const vectors = fs.readFileSync(path.join(__dirname, "vectors.tsv"), "utf8")
  .split("\n")
  .filter(line => line !== "" && !line.startsWith("#"))
  .map(line => line.split("\t"));

let failed = 0;
for (const [key, raw, verdict, note] of vectors) {
  const accepted = context.valid(key, JSON.parse(raw));
  if (accepted !== (verdict === "accept")) {
    failed += 1;
    console.log("FAIL " + key + " = " + raw + " (" + note + ")\n  want: " + verdict + "\n  got:  " + (accepted ? "accept" : "reject"));
  }
}
console.log(vectors.length - failed + "/" + vectors.length + " passed");
process.exit(failed ? 1 : 0);
