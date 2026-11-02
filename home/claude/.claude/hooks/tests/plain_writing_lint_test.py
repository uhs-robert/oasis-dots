"""Tests for plain_writing_lint.py: each rule, the exemptions, and the three triggers (commit, gh body, Markdown edit)."""
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

# The test must not leave a __pycache__ beside the hook, inside a tracked directory.
sys.dont_write_bytecode = True
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
        self.assertEqual(categories("The body is clean.\n\n    print(\"retry\"); retry()\n\tdon't(); x"), [])
        self.assertIn("contraction", categories("- An item\n    that doesn't end here."))
        self.assertEqual(categories("<!--\nIt shouldn't be linted; this is hidden.\n-->\nThe body is clean."), [])
        self.assertEqual([h[0] for h in lint.lint_text("<!--\na\n-->\nIt doesn't work.", FILLER)], [4])
        self.assertEqual(categories("````\n```\nit doesn't; really\n```\nstill code; it isn't prose\n````\nThe body is clean."), [])
        self.assertEqual(categories("```\n```not a close\nit doesn't\n```\nThe body is clean."), [])
        self.assertEqual(categories("# A heading that doesn't count"), [])
        self.assertEqual(categories("---\ndescription: it doesn't\n---\nThe body is clean."), [])
        self.assertEqual(categories("It reads a string, including the name."), [])

    def test_exempt_markdown_forms_hide_a_hit_and_a_real_hit_beside_them_stays(self):
        hit = "It doesn't work."
        cases = {
            "multi-backtick span": ("Use `` a ` it couldn't `` here.", 1),
            "div block": ("<div>\nit couldn't work\n</div>", 1),
            "details block": ("<details>\n<summary>Why</summary>\nit couldn't work\n</details>", 1),
            "raw pre block": ("<pre>\nit couldn't work\n\nstill couldn't\n</pre>", 1),
            "setext heading": ("It couldn't work\n================", 1),
            "setext dash heading": ("It couldn't work\n----", 1),
            "link definition": ("[ref]: http://a.example \"it couldn't work\"", 1),
        }
        for name, (text, _) in cases.items():
            with self.subTest(name):
                self.assertEqual(categories(text), [])
                self.assertEqual(categories(f"{text}\n\n{hit}"), ["contraction"])

    def test_html_block_ends_at_a_blank_line(self):
        self.assertEqual(categories("<div>\nhidden\n\nThe fix couldn't wait."), ["contraction"])

    def test_footnote_and_list_item_before_a_rule_stay_linted(self):
        self.assertIn("contraction", categories("[^1]: It doesn't work."))
        self.assertIn("contraction", categories("- It doesn't work.\n---"))

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

    def test_pr_body_from_command_substitution(self):
        command = "gh pr create --title t --body \"$(cat <<'EOF'\nThe fix shouldn't change the API.\nEOF\n)\""
        self.assertIn("the PR body", self.bash(command))

    def test_issue_body_from_flag_and_file(self):
        self.assertIn("the issue body", self.bash("gh issue create --title t --body \"It doesn't start.\""))
        body = pathlib.Path(self.root, "body.md")
        body.write_text("A clean body.\n")
        self.assertIsNone(self.bash("gh issue edit 5 --body-file body.md"))

    def test_pr_body_after_line_continuations(self):
        heredoc = "gh pr create \\\n  --title t \\\n  --body-file - <<'EOF'\nThe fix shouldn't change the API.\nEOF"
        self.assertIn("the PR body", self.bash(heredoc))
        substitution = "gh pr create \\\n  --title t \\\n  --body \"$(cat <<'EOF'\nThe fix shouldn't change the API.\nEOF\n)\""
        self.assertIn("the PR body", self.bash(substitution))
        self.assertIn("the PR body", self.bash("gh pr create \\\n  --title t \\\n  --body \"It doesn't start.\""))
        pathlib.Path(self.root, "bad.md").write_text("It doesn't start.\n")
        self.assertIn("the PR body", self.bash("gh pr create \\\n  --body-file bad.md"))

    def test_clean_pr_body_after_line_continuations_is_silent(self):
        heredoc = "gh pr create \\\n  --title t \\\n  --body-file - <<'EOF'\nThe fix keeps the API.\nEOF"
        self.assertIsNone(self.bash(heredoc))
        substitution = "gh pr create \\\n  --body \"$(cat <<'EOF'\nThe fix keeps the API.\nEOF\n)\""
        self.assertIsNone(self.bash(substitution))

    def test_every_gh_command_in_a_chain_is_checked(self):
        clean = 'gh pr create --body "A clean body."'
        bad = 'gh pr edit 5 --body "It doesn\'t start."'
        for chain in (f"{clean} && {bad}", f"{clean}; {bad}", f"{clean} || {bad}", f"{bad} && {clean}"):
            with self.subTest(chain):
                self.assertIn("the PR body", self.bash(chain))
        self.assertIsNone(self.bash(f"{clean} && {clean}"))

    def test_a_gh_word_inside_an_argument_does_not_split_the_command(self):
        self.assertIn("the PR body", self.bash('gh pr create --title "gh" --body "It doesn\'t work."'))
        self.assertIn("the PR body", self.bash('gh pr create --title gh --body "It doesn\'t work."'))

    def test_newline_separated_gh_commands_are_each_checked(self):
        self.assertIn("the issue body", self.bash('gh pr create --body "Clean."\ngh issue create --body "It doesn\'t work."'))
        self.assertIsNone(self.bash('gh pr create --body "Clean.\nStill clean."'))

    def test_commands_after_a_heredoc_are_checked_and_each_keeps_its_own_body(self):
        clean = "gh pr create --body-file - <<'EOF'\nA clean body.\nEOF"
        bad_issue = "gh issue create --body \"It doesn't work.\""
        self.assertIn("the issue body", self.bash(f"{clean}\n{bad_issue}"))
        self.assertIn("the issue body", self.bash(f"{clean} && {bad_issue}"))
        bad_pr = "gh pr create --body-file - <<'EOF'\nIt doesn't work.\nEOF"
        message = self.bash(f"{bad_pr}\n{clean.replace('pr create', 'issue create')}")
        self.assertIn("the PR body", message)
        self.assertNotIn("the issue body", message)
        substitution = "gh pr create --body \"$(cat <<'EOF'\nA clean body.\nEOF\n)\" && " + bad_issue
        self.assertIn("the issue body", self.bash(substitution))

    def test_substitution_without_a_closing_paren_still_yields_the_body(self):
        # main() swallows exceptions, so a crash here would only show as a silent miss.
        command = "gh pr create --body \"$(cat <<'EOF'\nIt doesn't work.\nEOF\n"
        self.assertEqual(lint.gh_bodies(command, self.root), [("pr", "It doesn't work.")])

    def test_gh_command_inside_a_command_substitution(self):
        self.assertIn("the PR body", self.bash('pr_url=$(gh pr create --body "It doesn\'t work.")'))
        self.assertIn("the PR body", self.bash('echo "$(gh pr create --body "It doesn\'t work.")"'))

    def test_heredoc_belongs_to_the_command_that_opens_it(self):
        command = "gh pr create --body-file - <<'EOF' && echo done\nIt doesn't work.\nEOF"
        self.assertIn("the PR body", self.bash(command))

    def test_gh_command_after_another_commands_heredoc_substitution(self):
        command = "git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n)\" && gh pr create --body \"It doesn't work.\""
        self.assertIn("the PR body", self.bash(command))

    def test_gh_text_inside_an_argument_or_heredoc_body_is_not_a_command(self):
        self.assertIsNone(self.bash('gh pr create --title "gh issue create --body should" --body "Clean."'))
        self.assertIsNone(self.bash("gh pr create --body-file - <<'EOF'\nRun `gh issue create --body should`.\nEOF"))
        self.assertIsNone(self.bash("cat > notes.md <<'EOF'\ngh issue create --body should\nEOF"))

    def test_odd_and_long_commands_neither_crash_nor_stall(self):
        # main() swallows exceptions, so call gh_bodies() directly to see a crash.
        import random
        pieces = ["gh pr create ", "--body ", "-b ", "--body-file - ", "<<'EOF'", "<<-E", "<<<", "EOF", "\n", "\\\n",
                  "\"", "'", "$(", "(", ")", "`", "&&", "|", ";", "&", "=", "x", " "]
        generator = random.Random(1420)
        for _ in range(2000):
            lint.gh_bodies("".join(generator.choice(pieces) for _ in range(30)), self.root)
        started = time.monotonic()
        for command in ("gh pr create " * 20000, "<<a " * 20000, "gh pr create --body \"" + "(" * 50000,
                        "gh pr create --body-file - " + "<<a " * 20000 + "\n", "$(" * 50000, "\\\n" * 50000):
            lint.gh_bodies(command, self.root)
        self.assertLess(time.monotonic() - started, 5)

    def test_other_commands_and_bad_input_are_silent(self):
        self.assertIsNone(self.bash("ls -la"))
        with mock.patch("sys.stdin", io.StringIO("not json")), mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            self.assertEqual(lint.main(), 0)
        self.assertEqual(out.getvalue(), "")


if __name__ == "__main__":
    unittest.main(verbosity=1)
