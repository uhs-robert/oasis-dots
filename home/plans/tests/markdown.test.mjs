// Tests the doc view's markdown renderer by cutting it out of board.html between the markdown markers.
// Run: node home/plans/tests/markdown.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const board_path = join(dirname(fileURLToPath(import.meta.url)), "../.local/lib/plans/plans/board.html");
const html = readFileSync(board_path, "utf8");
const block = html.split("// markdown:start")[1].split("// markdown:end")[0];
const { render_markdown, escape_html } = new Function(`${block}\nreturn { render_markdown, escape_html };`)();

const issue_href = (number) => `https://github.com/me/repo/issues/${number}`;
const render = (text) => render_markdown(text, { issue_href });

// The safety check: every tag in the output is one the renderer makes, with only its own attributes, and every link
// goes to http(s). Text between tags holds no < or > at all, so nothing else can parse as markup.
const ALLOWED_TAGS = new Set(["h1", "h2", "h3", "h4", "h5", "h6", "p", "ul", "ol", "li", "input", "code", "pre",
  "strong", "em", "a", "table", "tr", "th", "td", "hr"]);
const ALLOWED_ATTRIBUTES = {
  href: /^https?:\/\/[^"]*$/i, target: /^_blank$/, rel: /^noopener noreferrer$/, class: /^(task|front-matter|table)$/,
  type: /^checkbox$/, disabled: null, checked: null, start: /^[0-9]+$/, colspan: /^2$/,
};

function assert_inert(output, input) {
  const context = `input: ${JSON.stringify(input)}\noutput: ${output}`;
  const text = output.replace(/<\/?([a-z0-9]+)((?:\s+[a-z]+(?:="[^"]*")?)*)\s*>/g, (tag, name, attributes) => {
    assert.ok(ALLOWED_TAGS.has(name), `tag <${name}> is not allowed\n${context}`);
    for (const [, key, value] of attributes.matchAll(/\s+([a-z]+)(?:="([^"]*)")?/g)) {
      assert.ok(key in ALLOWED_ATTRIBUTES, `attribute ${key} is not allowed\n${context}`);
      const rule = ALLOWED_ATTRIBUTES[key];
      if (rule) assert.ok(value !== undefined && rule.test(value), `attribute ${key}="${value}" is not allowed\n${context}`);
    }
    return "";
  });
  assert.ok(!/[<>]/.test(text), `a bare < or > outside the renderer's tags\n${context}`);
  assert.ok(!text.includes("\u0000"), `a placeholder leaked\n${context}`);
}

const check = (input) => {
  const output = render(input);
  assert_inert(output, input);
  return output;
};

// The subset.
assert.equal(check("# Title"), "<h1>Title</h1>");
assert.equal(check("### Plan ###"), "<h3>Plan</h3>");
assert.equal(check("#12 is a ref, not a heading"), '<p><a href="https://github.com/me/repo/issues/12" target="_blank" rel="noopener noreferrer">#12</a> is a ref, not a heading</p>');
assert.equal(check("- a\n- b"), "<ul>\n<li>a\n</li>\n<li>b\n</li></ul>");
assert.equal(check("1. one\n2. two"), "<ol>\n<li>one\n</li>\n<li>two\n</li></ol>");
assert.equal(check("3. three"), '<ol start="3">\n<li>three\n</li></ol>', "a list that starts later keeps its number");
assert.equal(check("- a\n  - b\n- c"), "<ul>\n<li>a\n<ul>\n<li>b\n</li></ul>\n</li>\n<li>c\n</li></ul>", "nesting by indent");
assert.equal(check("- a\n  1. b"), "<ul>\n<li>a\n<ol>\n<li>b\n</li></ol>\n</li></ul>", "a numbered list nests in a bullet");
assert.equal(check("- a\n  more"), "<ul>\n<li>a\n\nmore\n</li></ul>", "an indented line continues the item");
assert.equal(check("- [ ] open\n- [x] done"),
  '<ul>\n<li class="task"><input type="checkbox" disabled> open\n</li>\n<li class="task"><input type="checkbox" disabled checked> done\n</li></ul>');
assert.equal(check("```\n<b>x</b>\n# not a heading\n```"), "<pre><code>&lt;b&gt;x&lt;/b&gt;\n# not a heading</code></pre>");
assert.equal(check("```js\nunclosed"), "<pre><code>unclosed</code></pre>", "an unclosed fence runs to the end");
assert.equal(check("use `a <b>` here"), "<p>use <code>a &lt;b&gt;</code> here</p>");
assert.equal(check("`**not bold**`"), "<p><code>**not bold**</code></p>", "code keeps its stars");
assert.equal(check("**bold** and *it* and _it_"), "<p><strong>bold</strong> and <em>it</em> and <em>it</em></p>");
assert.equal(check("owner_session_id stays"), "<p>owner_session_id stays</p>", "snake_case is no italic");
assert.equal(check("a * b * c"), "<p>a * b * c</p>", "spaced stars are no italic");
assert.equal(check("---\nid: demo\nwaiting_on: \"a: b\"\n---\n# Goal"),
  '<table class="front-matter"><tr><th>id</th><td>demo</td></tr><tr><th>waiting_on</th><td>&quot;a: b&quot;</td></tr></table>\n<h1>Goal</h1>');
assert.equal(check("a\n\n---\n\nb"), "<p>a</p>\n<hr>\n<p>b</p>");
assert.equal(check("| a | b |\n|---|---|"), '<pre class="table">| a | b |\n|---|---|</pre>', "a table stays text");
assert.equal(check("> quoted"), "<p>&gt; quoted</p>", "anything else stays text");
assert.equal(check("line one\nline two"), "<p>line one\nline two</p>");

// Links.
const link = (href, label) => `<a href="${href}" target="_blank" rel="noopener noreferrer">${label}</a>`;
assert.equal(check("[docs](https://example.com/a?b=1&c=2)"), `<p>${link("https://example.com/a?b=1&amp;c=2", "docs")}</p>`);
assert.equal(check("see https://example.com/x."), `<p>see ${link("https://example.com/x", "https://example.com/x")}.</p>`);
assert.equal(check("[a `b`](http://x.org)"), `<p>${link("http://x.org", "a <code>b</code>")}</p>`);
assert.equal(check("[#12](https://x.org)"), `<p>${link("https://x.org", "#12")}</p>`, "no link in a link");
assert.equal(check("me/other#12 and a#12 and ##12"), "<p>me/other#12 and a#12 and ##12</p>", "only a lone #N links");
assert.equal(check("it's #5"), `<p>it&#39;s ${link("https://github.com/me/repo/issues/5", "#5")}</p>`);
assert.equal(render_markdown("#12", {}), "<p>#12</p>", "no origin leaves the ref as text");
assert.equal(render_markdown("#12", { issue_href: () => "javascript:alert(1)" }), "<p>#12</p>", "a bad issue target is no link");
assert.equal(render_markdown("#12", { issue_href: () => 'https://x.org/"><script>' }),
  `<p>${link("https://x.org/&quot;&gt;&lt;script&gt;", "#12")}</p>`, "the issue target is escaped");

// Hostile docs stay inert text.
const hostile = [
  "<script>alert(1)</script>",
  "# <script>alert(1)</script>",
  "- <img src=x onerror=alert(1)>",
  '<a href="javascript:alert(1)">x</a>',
  "<div onclick=\"alert(1)\">x</div>",
  "[x](javascript:alert(1))",
  "[x](JavaScript:alert(1))",
  "[x](data:text/html;base64,PHNjcmlwdD4=)",
  "[x](//evil.example)",
  "[x](vbscript:msgbox)",
  "[x](java&#x09;script:alert(1))",
  '[x](https://a.org/"onmouseover="alert(1))',
  "[x](https://a.org/'onmouseover='alert(1))",
  'https://a.org/"onmouseover="alert(1)',
  "https://a.org/<script>",
  "javascript:alert(1)",
  "data:text/html,<script>alert(1)</script>",
  "`</code><script>alert(1)</script>`",
  "**<b onmouseover=alert(1)>x</b>**",
  "[<img src=x onerror=alert(1)>](https://a.org)",
  "---\n<script>: <img onerror=alert(1)>\n---",
  "```\n</pre><script>alert(1)</script>\n```",
  "| <script> |",
  "x\u00000\u0000y [a](https://a.org)",
  "&lt;script&gt; &amp; &#60;",
];
for (const input of hostile) {
  const output = check(input);
  // An event handler stays as text: assert_inert already refused it as an attribute.
  assert.ok(!/<script|<img|<div|<b |href="(?!https?:)/i.test(output), `${input} -> ${output}`);
}
assert.equal(check("[x](javascript:alert(1))"), "<p>[x](javascript:alert(1))</p>");
assert.equal(check("<script>alert(1)</script>"), "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>");
assert.equal(check("&lt;"), "<p>&amp;lt;</p>", "an entity in the doc shows as typed");
assert.equal(escape_html(`<>&"'`), "&lt;&gt;&amp;&quot;&#39;");

// Random docs from the characters and words the patterns key on. Each output must pass the same check.
let seed = 1587;
const random = () => {
  seed = (seed * 1103515245 + 12345) % 2147483648;
  return seed / 2147483648;
};
const pieces = ["<", ">", '"', "'", "&", "&amp;", "&#39;", "[", "]", "(", ")", "`", "```", "*", "**", "_", "__", "#",
  "#12", "-", "- ", "1. ", "- [ ] ", "  ", "\n", "\n\n", "---", "|", "x", "a b", "https://", "http://a.org/",
  "javascript:", "data:", "onerror=", "<script>", "/", "=", "\u0000", "\t", ".", ":"];
for (let round = 0; round < 3000; round += 1) {
  let input = "";
  const length = 1 + Math.floor(random() * 30);
  for (let index = 0; index < length; index += 1) input += pieces[Math.floor(random() * pieces.length)];
  check(input);
}

console.log("markdown tests passed");
