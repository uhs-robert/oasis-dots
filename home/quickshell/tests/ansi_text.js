// Runs AnsiText.js under node: the SGR to StyledText converter behind the agent sessions preview.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/launcher/AnsiText.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { to_styled, bottom_lines };", context);
const { to_styled, bottom_lines } = context.api;
const styled = text => to_styled(text, "#cccccc");

const cases = [
  ["plain text", "hello", "hello"],
  ["html escaped", "a <b> & </b>", "a&nbsp;&lt;b&gt;&nbsp;&amp;&nbsp;&lt;/b&gt;"],
  ["spaces kept, StyledText collapses plain runs", "  a   b ", "&nbsp;&nbsp;a&nbsp;&nbsp;&nbsp;b&nbsp;"],
  ["newline", "a\nb", "a<br/>b"],
  ["carriage return dropped", "a\r\nb", "a<br/>b"],
  ["base fg", "\x1b[31mred\x1b[0m x", "<font color=\"#cd0000\">red</font>&nbsp;x"],
  ["bright fg", "\x1b[91mr", "<font color=\"#ff0000\">r</font>"],
  ["bold underline italic", "\x1b[1;3;4mx", "<b><i><u>x</u></i></b>"],
  ["bold off by 22", "\x1b[1mA\x1b[22mB", "<b>A</b>B"],
  ["reset by empty sgr", "\x1b[1mA\x1b[mB", "<b>A</b>B"],
  ["256 cube", "\x1b[38;5;196mx", "<font color=\"#ff0000\">x</font>"],
  ["256 grey", "\x1b[38;5;240mx", "<font color=\"#585858\">x</font>"],
  ["256 base", "\x1b[38;5;2mx", "<font color=\"#00cd00\">x</font>"],
  ["truecolor", "\x1b[38;2;1;2;255mx", "<font color=\"#0102ff\">x</font>"],
  ["truecolor colon form", "\x1b[38:2:1:2:255mx", "<font color=\"#0102ff\">x</font>"],
  ["truncated truecolor ignored", "\x1b[38;2;1mx", "x"],
  ["fg default 39", "\x1b[31mA\x1b[39mB", "<font color=\"#cd0000\">A</font>B"],
  ["background dropped", "\x1b[41mx", "x"],
  ["inverse stays visible: bold underline, no swap", "\x1b[7mx", "<b><u>x</u></b>"],
  ["inverse keeps the colour", "\x1b[31;7mx\x1b[27my", "<b><u><font color=\"#cd0000\">x</font></u></b><font color=\"#cd0000\">y</font>"],
  ["dim halves", "\x1b[2;38;2;200;100;50mx", "<font color=\"#643219\">x</font>"],
  ["colour kept across newline", "\x1b[32mA\nB", "<font color=\"#00cd00\">A</font><br/><font color=\"#00cd00\">B</font>"],
  ["cursor move dropped", "a\x1b[2Kb\x1b[1;1Hc", "abc"],
  ["private mode dropped", "\x1b[?25lx", "x"],
  ["osc with bel dropped", "\x1b]0;title\x07x", "x"],
  ["osc with st dropped", "\x1b]8;;http://e\x1b\\x", "x"],
  ["two char escape dropped", "\x1b(Bx", "x"],
  ["control chars dropped", "a\x00\x07b", "ab"],
  ["markup in coloured text escaped", "\x1b[31m<font color=red>", "<font color=\"#cd0000\">&lt;font&nbsp;color=red&gt;</font>"],
  ["colon truecolor with empty colour space", "\x1b[38:2::1:2:255mx", "<font color=\"#0102ff\">x</font>"],
  ["colon 256 colour", "\x1b[38:5:196mx", "<font color=\"#ff0000\">x</font>"],
  ["colon colour then bold", "\x1b[38:2::1:2:255;1mx", "<b><font color=\"#0102ff\">x</font></b>"],
  ["styled underline colon form", "\x1b[4:3mx\x1b[4:0my", "<u>x</u>y"],
  ["unterminated osc stops at the line end", "\x1b]0;title\nnext", "<br/>next"],
  ["unterminated escape at end", "x\x1b[", "x"],
];

let failed = 0;
for (const [name, input, expected] of cases) {
  try {
    assert.strictEqual(styled(input), expected);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + "\n  got:      " + styled(input) + "\n  expected: " + expected);
  }
}

const bottom = [
  ["keeps the tail", bottom_lines("a\nb\nc\nd", 2), "c\nd"],
  ["drops trailing blanks first", bottom_lines("a\nb\n\n\n  \n", 2), "a\nb"],
  ["short text whole", bottom_lines("a\nb", 5), "a\nb"],
  ["empty", bottom_lines("", 3), ""],
];
for (const [name, got, expected] of bottom) {
  try {
    assert.strictEqual(got, expected);
  } catch (e) {
    failed++;
    console.error("FAIL bottom_lines " + name + ": got " + JSON.stringify(got));
  }
}

if (failed > 0) {
  console.error(failed + " failed");
  process.exit(1);
}
console.log("ansi_text: " + (cases.length + bottom.length) + " ok");
