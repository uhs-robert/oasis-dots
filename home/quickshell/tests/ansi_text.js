// Runs AnsiText.js under node: the SGR to StyledText converter behind the agent sessions preview.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/launcher/AnsiText.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { to_styled, bottom_lines, hex_of, wrap_lines };", context);
const { to_styled, bottom_lines, hex_of, wrap_lines } = context.api;
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
const wrapped = [
  ["short line untouched", wrap_lines("abc\nde", 3), "abc\nde"],
  ["long line breaks at the width", wrap_lines("abcdefg", 3), "abc\ndef\ng"],
  ["escapes take no width", wrap_lines("\x1b[31mabc\x1b[0mdef", 3), "\x1b[31mabc\x1b[0m\ndef"],
  ["colour carries across the break", to_styled(wrap_lines("\x1b[31mabcd", 2), "#cccccc"), "<font color=\"#cd0000\">ab</font><br/><font color=\"#cd0000\">cd</font>"],
  ["frame line is cut, not wrapped", wrap_lines("\u256d\u2500\u2500\u2500\u2500\u256e", 3), "\u256d\u2500\u2500"],
  ["coloured frame keeps its escapes", wrap_lines("\x1b[2m\u2500\u2500\u2500\u2500\x1b[0m", 2), "\x1b[2m\u2500\u2500\x1b[0m"],
  ["text in a frame wraps", wrap_lines("\u2502 abcd", 3), "\u2502 a\nbcd"],
  ["astral character is one column", wrap_lines("\u{1F600}ab", 2), "\u{1F600}a\nb"],
  ["no width leaves it", wrap_lines("abcdef", 0), "abcdef"],
];
for (const [name, got, expected] of wrapped) {
  try {
    assert.strictEqual(got, expected);
  } catch (e) {
    failed++;
    console.error("FAIL wrap_lines " + name + ": got " + JSON.stringify(got));
  }
}

const oasis = ["#0c0e13", "#ff7979", "#7fcf78", "#f0e68c", "#81c0ff", "#c695ff", "#69c3aa", "#f5f5dc",
  "#4e6578", "#ffa0a0", "#a3e39a", "#f8b471", "#87ceeb", "#d2adff", "#8ad3be", "#fffff0"];
const with_palette = [
  ["palette remaps 31", to_styled("\x1b[31mx", "#cccccc", oasis), "<font color=\"#ff7979\">x</font>"],
  ["palette remaps 91", to_styled("\x1b[91mx", "#cccccc", oasis), "<font color=\"#ffa0a0\">x</font>"],
  ["palette remaps 38;5;4", to_styled("\x1b[38;5;4mx", "#cccccc", oasis), "<font color=\"#81c0ff\">x</font>"],
  ["palette leaves the 256 cube", to_styled("\x1b[38;5;196mx", "#cccccc", oasis), "<font color=\"#ff0000\">x</font>"],
  ["no palette keeps xterm", to_styled("\x1b[31mx\x1b[38;5;4my", "#cccccc"), "<font color=\"#cd0000\">x</font><font color=\"#0000ee\">y</font>"],
  ["dim blends toward the background", to_styled("\x1b[2;38;2;200;100;50mx", "#cccccc", oasis, "#204060"), "<font color=\"#745249\">x</font>"],
  ["dim default fg toward the background", to_styled("\x1b[2mx", "#f0f0f0", oasis, "#101010"), "<font color=\"#808080\">x</font>"],
  ["background-coloured text takes its dropped background", to_styled("\x1b[30;47mx", "#cccccc", oasis, "#0c0e13"), "<font color=\"#f5f5dc\">x</font>"],
  ["background-coloured text with no background stays", to_styled("\x1b[30mx", "#cccccc", oasis, "#0c0e13"), "<font color=\"#0c0e13\">x</font>"],
  ["hex_of drops alpha", hex_of({ r: 1, g: 0.5, b: 0, a: 0.5 }), "#ff8000"],
];
for (const [name, got, expected] of with_palette) {
  try {
    assert.strictEqual(got, expected);
  } catch (e) {
    failed++;
    console.error("FAIL " + name + ": got " + JSON.stringify(got));
  }
}

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
console.log("ansi_text: " + (cases.length + with_palette.length + bottom.length + wrapped.length) + " ok");
