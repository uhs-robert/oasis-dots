"""Tests for plain_writing_lint.py: each rule, the exemptions, and the three triggers (commit, gh body, Markdown edit)."""
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HOOK = pathlib.Path(__file__).resolve().parent.parent / "plain_writing_lint.py"
spec = importlib.util.spec_from_file_location("plain_writing_lint", HOOK)
lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lint)

FILLER = lint.filler_pattern(lint.load_filler_words(lint.word_swaps_path()))


def categories(text):
    return [category for _, category, _ in lint.lint_text(text, FILLER)]


def run_hook(event):
    with mock.patch("sys.stdin", io.StringIO(json.dumps(event))), mock.patch("sys.stdout", new_callable=io.StringIO) as out:
        assert lint.main() == 0
    text = out.getvalue()
    return json.loads(text)["hookSpecificOutput"]["additionalContext"] if text else None


class Rules(unittest.TestCase):
    def test_clean_text_has_no_hits(self):
        self.assertEqual(categories("The script copies the tables. It needs one file."), [])

    def test_each_mechanical_rule(self):
        self.assertIn("contraction", categories("It doesn't work."))
        self.assertIn("hedging modal", categories("The cache should expire."))
        self.assertIn("present perfect", categories("The file has been removed."))
        self.assertIn("em-dash, semicolon or spaced hyphen", categories("It works — mostly."))
        self.assertIn("em-dash, semicolon or spaced hyphen", categories("It works; mostly."))
        self.assertIn("-ing verb after a comma", categories("It adds a flag, making it easy."))
        self.assertIn("bold label on a list item", categories("- **Cleanup:** removes files."))
        long_sentence = " ".join(["word"] * 30) + "."
        self.assertTrue(any(c.startswith("long sentence") for c in categories(long_sentence)))

    def test_filler_words_come_from_the_skill(self):
        self.assertIsNotNone(FILLER, "word-swaps.md not found next to the hook")
        self.assertIn("filler word", categories("We leverage the cache."))
        self.assertIn("filler word", categories("It is seamless."))

    def test_exempt_text(self):
        self.assertEqual(categories("Run `don't-stop --should` now."), [])
        self.assertEqual(categories('The error says "it couldn\'t connect".'), [])
        self.assertEqual(categories("The user's file stays."), [])
        self.assertEqual(categories("```\nit doesn't matter; really\n```"), [])
        self.assertEqual(categories("> Before: it doesn't work."), [])
        self.assertEqual(categories("# A heading that doesn't count"), [])
        self.assertEqual(categories("---\ndescription: it doesn't\n---\nThe body is clean."), [])
        self.assertEqual(categories("It reads a string, including the name."), [])

    def test_inline_code_counts_as_one_word(self):
        sentence = "Run " + " ".join(f"`a{i}`" for i in range(10)) + " " + " ".join(["word"] * 14) + "."
        self.assertEqual(categories(sentence), [])


class Markdown(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.dir.name)
        self.file = self.root / "README.md"

    def tearDown(self):
        self.dir.cleanup()

    def event(self, tool_name, tool_input):
        return {"tool_name": tool_name, "tool_input": {"file_path": str(self.file), **tool_input}, "cwd": str(self.root)}

    def test_edit_reports_only_the_new_paragraph(self):
        self.file.write_text("Old text that doesn't follow the rules.\n\nNew text that is clean.\n")
        self.assertIsNone(run_hook(self.event("Edit", {"old_string": "x", "new_string": "New text that is clean."})))
        self.file.write_text("Old text that doesn't follow the rules.\n\nNew text that shouldn't pass.\n")
        message = run_hook(self.event("Edit", {"old_string": "x", "new_string": "New text that shouldn't pass."}))
        self.assertIn("line 3, contraction", message)
        self.assertNotIn("line 1", message)

    def test_edit_that_repeats_an_old_line_does_not_select_the_old_paragraph(self):
        self.file.write_text("Old text that doesn't follow the rules.\nThis is shared.\n\nA clean paragraph.\nThis is shared.\n")
        self.assertIsNone(run_hook(self.event("Edit", {"old_string": "A clean paragraph.", "new_string": "A clean paragraph.\nThis is shared."})))

    def test_replace_all_reports_every_occurrence(self):
        self.file.write_text("It doesn't work.\n\nClean.\n\nIt doesn't work.\n")
        message = run_hook(self.event("Edit", {"old_string": "It works.", "new_string": "It doesn't work.", "replace_all": True}))
        self.assertIn("line 1,", message)
        self.assertIn("line 5,", message)

    def test_write_of_a_new_file_reports_every_paragraph(self):
        self.file.write_text("It doesn't work.\n")
        self.assertIn("contraction", run_hook(self.event("Write", {"content": "It doesn't work.\n"})))

    def test_write_over_a_tracked_file_reports_only_changed_lines(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.file.write_text("Old text that doesn't follow the rules.\n")
        git = ["git", "-C", str(self.root), "-c", "user.name=t", "-c", "user.email=t@t"]
        subprocess.run(git + ["add", "."], check=True)
        subprocess.run(git + ["commit", "-qm", "init"], check=True)
        self.file.write_text("Old text that doesn't follow the rules.\n\nA clean new line.\n")
        self.assertIsNone(run_hook(self.event("Write", {"content": ""})))

    def test_other_files_and_excluded_paths_are_skipped(self):
        code = self.root / "app.py"
        code.write_text("# it doesn't matter\n")
        self.assertIsNone(run_hook({"tool_name": "Write", "tool_input": {"file_path": str(code)}, "cwd": str(self.root)}))
        skill = self.root / "skills" / "plain-writing" / "SKILL.md"
        skill.parent.mkdir(parents=True)
        skill.write_text("Do not write don't.\n")
        self.assertIsNone(run_hook({"tool_name": "Write", "tool_input": {"file_path": str(skill)}, "cwd": str(self.root)}))
        self.file.write_text("It doesn't work.\n")
        with mock.patch.dict(os.environ, {"PLAIN_WRITING_LINT_EXCLUDE": str(self.root) + "/*"}):
            self.assertIsNone(run_hook(self.event("Write", {"content": ""})))


class Commands(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = self.dir.name

    def tearDown(self):
        self.dir.cleanup()

    def bash(self, command):
        return run_hook({"tool_name": "Bash", "tool_input": {"command": command}, "cwd": self.root})

    def commit(self, message, date=None):
        env = dict(os.environ, GIT_COMMITTER_DATE=date) if date else None
        git = ["git", "-C", self.root, "-c", "user.name=t", "-c", "user.email=t@t"]
        subprocess.run(git + ["commit", "-q", "--allow-empty", "-m", message], check=True, env=env)

    def test_fresh_commit_message_is_linted(self):
        subprocess.run(["git", "init", "-q", self.root], check=True)
        self.commit("fix: it crashes\n\nIt doesn't start.")
        self.assertIn("line 3, contraction", self.bash("git commit -F msg"))

    def test_commit_subject_is_not_linted(self):
        subprocess.run(["git", "init", "-q", self.root], check=True)
        self.commit("feat: add just post-merge, replacing the marker")
        self.assertIsNone(self.bash("git commit -F msg"))

    def test_old_commit_is_ignored(self):
        subprocess.run(["git", "init", "-q", self.root], check=True)
        self.commit("fix: it doesn't crash", date="2001-01-01T00:00:00")
        self.assertIsNone(self.bash("git commit --amend"))

    def test_pr_body_from_heredoc(self):
        command = "gh pr create --title t --body-file - <<'EOF'\nThe fix shouldn't change the API.\nEOF"
        self.assertIn("the PR body", self.bash(command))

    def test_issue_body_from_flag_and_file(self):
        self.assertIn("the issue body", self.bash("gh issue create --title t --body \"It doesn't start.\""))
        body = pathlib.Path(self.root, "body.md")
        body.write_text("A clean body.\n")
        self.assertIsNone(self.bash("gh issue edit 5 --body-file body.md"))

    def test_other_commands_and_bad_input_are_silent(self):
        self.assertIsNone(self.bash("ls -la"))
        with mock.patch("sys.stdin", io.StringIO("not json")), mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            self.assertEqual(lint.main(), 0)
        self.assertEqual(out.getvalue(), "")


if __name__ == "__main__":
    unittest.main(verbosity=1)
