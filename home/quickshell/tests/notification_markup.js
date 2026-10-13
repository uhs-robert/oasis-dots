// Runs NotificationMarkup.js under node. The file is a QML `.pragma library`, so it is loaded as a script.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/services/NotificationMarkup.js"), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, ""), context);
const sanitize = context.sanitize;

const cases = [
  ["plain text", "hello world", "hello world"],
  ["plain < and &", "a < b && c > d", "a &lt; b &amp;&amp; c &gt; d"],
  ["lone angle bracket at end", "x <", "x &lt;"],
  ["remote img dropped", "hi <img src=\"https://evil.example/p.png\"> there", "hi  there"],
  ["img alt shown as text", "<img src='https://e/x.png' alt='<b>cat</b>'>", "&lt;b&gt;cat&lt;/b&gt;"],
  ["img without close, upper case", "<IMG SRC=https://e/x.png/>x", "x"],
  ["b i u kept", "<b>a</b> <i>b</i> <u>c</u>", "<b>a</b> <i>b</i> <u>c</u>"],
  ["case folded", "<B>a</B>", "<b>a</b>"],
  ["tag attributes dropped", "<b onclick=\"x()\" style='y'>a</b>", "<b>a</b>"],
  ["nested", "<b>a <i>b <u>c</u></i></b>", "<b>a <i>b <u>c</u></i></b>"],
  ["crossed nesting repaired", "<b>a<i>b</b>c</i>", "<b>a<i>b</i></b><i>c</i>"],
  ["unclosed closed at end", "<b>bold <i>italic", "<b>bold <i>italic</i></b>"],
  ["stray close dropped", "a</b>b</a>", "ab"],
  ["https link kept", "<a href=\"https://x.example/?a=1&b=2\">x</a>", "<a href=\"https://x.example/?a=1&amp;b=2\">x</a>"],
  ["mailto link kept", "<a href='mailto:me@x.example'>m</a>", "<a href=\"mailto:me@x.example\">m</a>"],
  ["javascript href stripped", "<a href=\"javascript:alert(1)\">x</a>", "x"],
  ["obfuscated javascript href stripped", "<a href=\"  java&#10;script:alert(1)\">x</a>", "x"],
  ["file href stripped", "<a href=\"file:///etc/passwd\">x</a>", "x"],
  ["data href stripped", "<a href=\"data:text/html,x\">x</a>", "x"],
  ["relative href stripped", "<a href=\"/x\">x</a>", "x"],
  ["href without value", "<a href>x</a>", "x"],
  ["quote in href escaped", "<a href='https://x.example/\"onmouseover=\"y'>x</a>", "<a href=\"https://x.example/&quot;onmouseover=&quot;y\">x</a>"],
  ["unclosed link closed", "<a href=\"https://x.example\">x", "<a href=\"https://x.example\">x</a>"],
  ["h1 dropped, text kept", "<h1>Title</h1>rest", "Titlerest"],
  ["other tags dropped", "<table><tr><td>c</td></tr></table><font size=9>f</font><p>p", "cfp"],
  ["script text is only text", "<script>alert(1)</script>", "alert(1)"],
  ["br variants", "a<br>b<br/>c<BR />d", "a<br>b<br>c<br>d"],
  ["newline is a break", "a\nb\r\nc", "a<br>b<br>c"],
  ["entities decoded then escaped", "&amp; &lt;b&gt; &quot;q&quot; &#65;&#x42;", "&amp; &lt;b&gt; &quot;q&quot; AB"],
  ["escaped tag stays text", "&lt;img src=https://e/x.png&gt;", "&lt;img src=https://e/x.png&gt;"],
  ["double-encoded stays one level", "&amp;lt;", "&amp;lt;"],
  ["unknown entity shown", "&bogus; & x", "&amp;bogus; &amp; x"],
  ["bad numeric entity dropped", "a&#1114112;b&#0;c", "abc"],
  ["control chars removed", "a\u0000b\u001bc", "abc"],
  ["unterminated tag is text", "<b onclick=\"x", "&lt;b onclick=&quot;x"],
  ["not a tag", "1 <2 and 3> 2", "1 &lt;2 and 3&gt; 2"],
  ["depth capped, still balanced", "<b>".repeat(20) + "x", "<b>".repeat(8) + "x" + "</b>".repeat(8)],
  ["empty", "", ""],
  ["null", null, ""],
];

let failed = 0;
for (const [name, input, want] of cases) {
  const got = sanitize(input);
  if (got !== want) {
    failed += 1;
    console.log("FAIL " + name + "\n  input: " + JSON.stringify(input) + "\n  want:  " + JSON.stringify(want) + "\n  got:   " + JSON.stringify(got));
  }
}
console.log(cases.length - failed + "/" + cases.length + " passed");
process.exit(failed ? 1 : 0);
