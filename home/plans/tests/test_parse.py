"""The front matter subset, the body sections and the line-preserving render."""

import os
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".local", "lib", "plans"))
from plans import parse  # noqa: E402

DOC = """---
id: demo
project: proj
kind: feature
status: planned
owner_session: none
rank: 20
depends_on: [a, "b c"]
waiting_on: "owner: pick a colour"
issue: 12
pr: none
branch: feat/demo
fix_rounds: 1
updated: "2026-11-05"
---
# demo

## Goal

Do it.

```
## Not a section
```

## Open questions

- [ ] Which colour?
- [x] Done one
"""


def doc(text, path="/r/.plans/proj/demo.md"):
    return parse.Doc(path, text)


def front(*lines):
    return "---\n" + "".join(line + "\n" for line in lines) + "---\nbody\n"


class ParseTest(unittest.TestCase):
    def test_values(self):
        parsed = doc(DOC)
        self.assertEqual(parsed.errors, [])
        self.assertEqual(parsed.keys["rank"], 20)
        self.assertEqual(parsed.keys["issue"], 12)
        self.assertEqual(parsed.keys["depends_on"], ["a", "b c"])
        self.assertEqual(parsed.keys["waiting_on"], "owner: pick a colour")
        self.assertEqual(parsed.keys["branch"], "feat/demo")
        self.assertEqual(parsed.keys["fix_rounds"], 1)
        self.assertEqual(parsed.keys["updated"], "2026-11-05")
        self.assertEqual(list(parsed.keys), list(parse.KEY_ORDER))

    def test_escapes_and_empty(self):
        parsed = doc(front(r'a: "say \"hi\" \\ there"', 'b: ""', "c: []", "d: [ x ,z ]"))
        self.assertEqual(parsed.errors, [])
        self.assertEqual(parsed.keys, {"a": 'say "hi" \\ there', "b": "", "c": [], "d": ["x", "z"]})

    def test_rejects_outside_subset(self):
        bad_lines = [
            "nested:", "  child: x", "key:value", "key:  two spaces", "Key: caps", "a: x # comment", "a: 'single'",
            "a: yes", "a: null", "a: 1.5", "a: 2026-11-05", "a: [a, b", "a: {x: 1}", "a: x: y", "a: -x", 'a: "\\n"',
            "# comment", "", "a: trailing ", "- item", "a: [a b, ]",
        ]
        for line in bad_lines:
            with self.subTest(line=line):
                parsed = doc(front(line))
                self.assertEqual(len(parsed.errors), 1, parsed.errors)
                self.assertEqual(parsed.errors[0][0], 2)

    def test_duplicate_key(self):
        self.assertEqual(doc(front("a: x", "a: y")).errors, [(3, "duplicate key a")])

    def test_missing_front_matter(self):
        self.assertIn("no front matter", doc("# title\n").errors[0][1])
        self.assertIn("no closing", doc("---\na: x\n").errors[0][1])

    def test_sections_skip_fences(self):
        sections = doc(DOC).sections()
        self.assertEqual(list(sections), ["Goal", "Open questions"])
        line, content = sections["Open questions"]
        self.assertEqual(DOC.splitlines()[line - 1], "")
        self.assertIn("- [ ] Which colour?", content)
        self.assertIn("## Not a section", sections["Goal"][1])

    def test_render_changes_only_the_changed_lines(self):
        parsed = doc(DOC)
        text = parsed.render({"status": "building", "depends_on": [], "waiting_on": "", "new_key": "x"})
        before, after = DOC.splitlines(), text.splitlines()
        changed = [i for i, (a, b) in enumerate(zip(before[:14], after[:14])) if a != b]
        self.assertEqual(changed, [4, 7, 8])
        self.assertEqual(after[4], "status: building")
        self.assertEqual(after[7], "depends_on: []")
        self.assertEqual(after[8], 'waiting_on: ""')
        self.assertEqual(after[14], "new_key: x")
        self.assertEqual(after[15:], before[14:])
        self.assertTrue(text.endswith(parsed.body))
        self.assertEqual(text.split("---\n", 2)[2], parsed.body)

    def test_render_body_and_crlf_body_kept(self):
        text = "---\na: x\n---\nline one\r\nline two\r\n"
        parsed = doc(text)
        self.assertEqual(parsed.render({"a": "z"}), "---\na: z\n---\nline one\r\nline two\r\n")
        self.assertEqual(parsed.render({parse.BODY: "new\n"}), "---\na: x\n---\nnew\n")

    def test_format_round_trips(self):
        values = ["plain", "two words", "", "owner: wait", "yes", "12", "2026-11-05", 'q"uote', "back\\slash", "#x",
                  "-dash", 7, 0, [], ["a", "b c", "d,e", "12"]]
        for value in values:
            with self.subTest(value=value):
                parsed = doc(front("k: " + parse.format_value(value)))
                self.assertEqual(parsed.errors, [])
                self.assertEqual(parsed.keys["k"], value)

    def test_id_falls_back_to_file_name(self):
        self.assertEqual(doc(front("a: x"), "/r/.plans/p/file-name.md").id, "file-name")


if __name__ == "__main__":
    unittest.main()
