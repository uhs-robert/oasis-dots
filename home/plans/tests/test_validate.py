"""Every lint rule, and the detection of each old layout."""

import os
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".local", "lib", "plans"))
from plans import parse, validate  # noqa: E402

# Git sets these in hooks, where the check can run. Inherited, they point every git call here at that other repo.
for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
             "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_PREFIX"):
    os.environ.pop(name, None)

GOOD_KEYS = {
    "id": "demo", "project": "proj", "kind": "feature", "status": "planned", "owner_session": "none", "rank": "10",
    "depends_on": "[]", "waiting_on": '""', "issue": "none", "pr": "none", "branch": "none", "fix_rounds": "0", "updated": '"2026-11-05"',
}
GOOD_BODY = "# demo\n\n## Goal\n\n## Decisions\n\n## Plan\n\n## Open questions\n\n- [ ] One?\n  more of it\n- [x] Two\n\n## Owner checks\n"


def make(keys=None, drop=(), body=GOOD_BODY, name="demo"):
    merged = {**GOOD_KEYS, **(keys or {})}
    head = "".join(f"{key}: {value}\n" for key, value in merged.items() if key not in drop)
    return parse.Doc(f"/r/.plans/proj/{name}.md", f"---\n{head}---\n{body}")


def rules(doc):
    return [finding.rule for finding in validate.lint_doc(doc)]


class DocRulesTest(unittest.TestCase):
    def test_good_doc_is_clean(self):
        self.assertEqual(validate.lint_doc(make()), [])

    def test_front_matter_subset(self):
        doc = make({"waiting_on": "owner: x"})
        self.assertEqual(rules(doc), ["front-matter"])
        self.assertEqual(validate.lint_doc(doc)[0].line, 9)

    def test_missing_keys(self):
        findings = validate.lint_doc(make(drop=("branch", "updated")))
        self.assertEqual([f.rule for f in findings], ["missing-key", "missing-key"])
        self.assertIn("no branch key", findings[0].message)

    def test_closed_sets(self):
        self.assertEqual(rules(make({"kind": "feat"})), ["kind"])
        self.assertEqual(rules(make({"status": "active"})), ["status"])

    def test_old_kind_names_the_scheme_only(self):
        findings = validate.lint_doc(make({"kind": "tracker"}, drop=("id", "rank"), body="no sections\n"))
        self.assertEqual([f.rule for f in findings], ["old-kind"])
        self.assertIn("plan/tracker/handoff", findings[0].message)
        self.assertIn("migrate this repo", findings[0].message)

    def test_id_matches_file_name(self):
        self.assertEqual(rules(make(name="other")), ["id"])

    def test_rank_integer(self):
        self.assertEqual(rules(make({"rank": "high"})), ["rank"])

    def test_fix_rounds_integer_and_optional(self):
        self.assertEqual(rules(make({"fix_rounds": "two"})), ["fix-rounds"])
        self.assertEqual(rules(make(drop=("fix_rounds",))), [])

    def test_owner_session(self):
        for good in ("none", "dotfiles-56", "desertfox-5c", "my-repo-00"):
            self.assertEqual(rules(make({"owner_session": good})), [], good)
        for bad in ("dotfiles", "Dotfiles-56", '"dotfiles 56"'):
            self.assertEqual(rules(make({"owner_session": bad})), ["owner-session"], bad)

    def test_owner_session_values(self):
        for good in ({"owner_session_id": "47d3359c-f126", "owner_session_pid": "3470032"}, {"owner_session_id": '""', "owner_session_pid": '""'}):
            self.assertEqual(rules(make(good)), [], good)
        self.assertEqual(rules(make({"owner_session_id": "[a]"})), ["owner-session-id"])
        self.assertEqual(rules(make({"owner_session_pid": "abc"})), ["owner-session-pid"])

    def test_last_owner_values(self):
        for good in ({"last_owner_session": "dotfiles-56", "last_owner_session_id": "47d3359c"}, {"last_owner_session": '""', "last_owner_session_id": '""'}):
            self.assertEqual(rules(make(good)), [], good)
        self.assertEqual(rules(make({"last_owner_session": "Bad Name"})), ["last-owner-session"])
        self.assertEqual(rules(make({"last_owner_session_id": "[a]"})), ["last-owner-session-id"])

    def test_depends_on_is_a_list(self):
        self.assertEqual(rules(make({"depends_on": "other"})), ["list"])

    def test_sections(self):
        body = GOOD_BODY.replace("## Plan\n", "## Plans\n").replace("## Owner checks\n", "")
        findings = validate.lint_doc(make(body=body))
        self.assertEqual([f.message for f in findings], ["no `## Plan` section", "no `## Owner checks` section"])

    def test_open_questions_only_checklist(self):
        body = GOOD_BODY.replace("- [x] Two\n", "- [x] Two\nA loose note\n- plain bullet\n")
        findings = validate.lint_doc(make(body=body))
        self.assertEqual([f.rule for f in findings], ["open-questions", "open-questions"])
        doc = make(body=body)
        self.assertEqual(doc.text.splitlines()[findings[0].line - 1], "A loose note")


class RepoRulesTest(unittest.TestCase):
    def test_unique_ids(self):
        first, second = make(), parse.Doc("/r/.plans/other/demo.md", make().text)
        findings = validate.lint_repo([first, second])
        self.assertEqual([f.rule for f in findings], ["duplicate-id", "duplicate-id"])

    def test_depends_on_must_name_a_doc(self):
        dependent = make({"depends_on": "[demo-b, gone]"})
        other = make({"id": "demo-b"}, name="demo-b")
        findings = validate.lint_repo([dependent, other])
        self.assertEqual([(f.rule, f.message.split(";")[0]) for f in findings], [("depends-on", "no doc 'gone'")])


class ConflictFindingTest(unittest.TestCase):
    def test_one_finding_per_copy(self):
        findings = validate.conflict_findings(["/r/.plans/p/a.sync-conflict-1.md"])
        self.assertEqual(findings, [validate.Finding("/r/.plans/p/a.sync-conflict-1.md", 1, "conflict",
                                                     "merge a.md by hand, then delete the copy")])


class OldLayoutTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = self.temp.name
        subprocess.run(["git", "init", "-q", self.repo], check=True)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, rel, text="x\n"):
        path = os.path.join(self.repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            handle.write(text)

    def test_clean_repo(self):
        self.write(".plans/proj/demo.md")
        self.assertEqual(validate.old_layouts(self.repo), [])

    def test_each_layout(self):
        self.write(".planning/roadmap.md")
        self.write(".plans/roadmap.md")
        self.write(".plans/projects/x.md")
        self.write("NOTES.md")
        self.write("README.md")
        self.write("my notes.md")
        self.write("other.txt")
        subprocess.run(["git", "-C", self.repo, "add", "README.md", "my notes.md"], check=True)
        with open(os.path.join(self.repo, ".git", "info", "exclude"), "a") as handle:
            handle.write("/NOTES.md\n*.md\nother.txt\n")
        found = validate.old_layouts(self.repo)
        self.assertEqual(found, [
            ".planning/roadmap.md; migrate this repo",
            ".plans/roadmap.md; migrate this repo",
            ".plans/projects/; migrate this repo",
            "root docs in info/exclude: NOTES.md; migrate this repo",
        ])


if __name__ == "__main__":
    unittest.main()
