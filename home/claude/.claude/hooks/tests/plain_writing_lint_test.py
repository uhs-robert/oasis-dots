"""Tests for plain_writing_lint.py: each rule, the exemptions, the three triggers (commit, gh body, Markdown
edit), and the deny-once rule before a Bash call."""
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


def hook_output(event):
    with mock.patch("sys.stdin", io.StringIO(json.dumps(event))), mock.patch("sys.stdout", new_callable=io.StringIO) as out:
        assert lint.main() == 0
    text = out.getvalue()
    return json.loads(text)["hookSpecificOutput"] if text else None


def run_hook(event):
    """The PostToolUse added context, or None."""
    output = hook_output(event)
    return output["additionalContext"] if output else None


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


class StateDirectory(unittest.TestCase):
    """Each test gets its own cwd and denied-text state."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = self.dir.name
        state = mock.patch.dict(os.environ, {"XDG_STATE_HOME": os.path.join(self.root, "state")})
        state.start()
        self.addCleanup(state.stop)

    def tearDown(self):
        self.dir.cleanup()

    def pre(self, command, session="s1"):
        """The PreToolUse output, or None when the call is allowed."""
        return hook_output({"hook_event_name": "PreToolUse", "session_id": session, "tool_name": "Bash",
                            "tool_input": {"command": command}, "cwd": self.root})

    def post(self, command):
        return run_hook({"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": {"command": command}, "cwd": self.root})


class Commands(StateDirectory):
    """The parser, through PreToolUse. Each call uses a new session, so no earlier deny lets a text through."""

    calls = 0

    def bash(self, command):
        Commands.calls += 1
        output = self.pre(command, session=f"parser-{Commands.calls}")
        if output is None:
            return None
        self.assertEqual(output["permissionDecision"], "deny")
        return output["permissionDecisionReason"]

    def test_commit_message_from_m_flags(self):
        self.assertIn("line 3, contraction", self.bash('git commit -m "fix: x" -m "It doesn\'t start."'))
        self.assertIn("contraction", self.bash('git commit -qam "fix: x" --message="It doesn\'t start."'))
        self.assertIn("contraction", self.bash("git -C sub commit -m 'fix: x\n\nIt doesn'\"'\"'t start.'"))
        self.assertIsNone(self.bash('git commit -m "fix: x" -m "It starts."'))

    def test_attached_values_of_s_and_u_are_not_option_letters(self):
        # The F and C inside the key id must not read as -F or -C.
        self.assertIn("contraction", self.bash('git commit -S1F2C3D4E -m "fix: x" -m "It doesn\'t start."'))
        self.assertIsNone(self.bash('git commit -unormal -m "fix: x" -m "It starts."'))

    def test_commit_subject_is_not_linted(self):
        self.assertIsNone(self.bash('git commit -m "feat: add just post-merge, replacing the marker"'))

    def test_commit_message_from_heredoc(self):
        self.assertIn("the commit message", self.bash("git commit -F - <<'EOF'\nfix: x\n\nIt doesn't start.\nEOF"))
        self.assertIn("the commit message", self.bash("git commit --file=- <<'EOF'\nfix: x\n\nIt doesn't start.\nEOF"))
        substitution = "git commit -m \"$(cat <<'EOF'\nfix: x\n\nIt doesn't start.\nEOF\n)\""
        self.assertIn("the commit message", self.bash(substitution))

    def test_commit_message_from_a_file(self):
        pathlib.Path(self.root, "msg").write_text("fix: x\n\nIt doesn't start.\n")
        self.assertIn("the commit message", self.bash("git commit -F msg"))

    def test_commit_without_a_new_message_is_allowed(self):
        for command in ("git commit --amend --no-edit", "git commit", "git commit -C HEAD", 'git commit -m "$(gen)"'):
            with self.subTest(command):
                self.assertIsNone(self.bash(command))

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
        self.assertEqual(lint.command_texts(command, self.root), [("pr", "It doesn't work.")])

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

    def test_shift_operator_in_quotes_or_arithmetic_is_not_a_heredoc(self):
        bad = 'gh pr create --body "It doesn\'t work."'
        for before in ('git commit -m "fix: shift x << 2"', "echo $((1 << n))", "echo 'cout << x'", "((x << 2))"):
            with self.subTest(before):
                self.assertIn("the PR body", self.bash(f"{before}\n{bad}"))

    def test_real_heredoc_without_a_closing_line_still_hides_the_rest(self):
        self.assertIsNone(self.bash("cat <<EOF\ngh issue create --body should"))

    def test_gh_command_in_a_comment_is_not_a_command(self):
        self.assertIsNone(self.bash("true # gh issue create --body should"))
        self.assertIsNone(self.bash("gh pr create --body Clean # don't"))

    def test_heredoc_piped_into_gh_is_its_body(self):
        self.assertIn("the PR body", self.bash("cat <<'EOF' | gh pr create --body-file -\nIt doesn't work.\nEOF"))

    BAD_BODY = 'gh pr create --body "It doesn\'t start."'

    def test_backtick_substitution_does_not_end_the_command(self):
        self.assertIn("the PR body", self.bash('gh pr create --title `date | tr a b` --body "It doesn\'t start."'))
        self.assertIn("the PR body", self.bash('x=`gh pr create --body "It doesn\'t start."`'))
        self.assertIsNone(self.bash('echo `date` "It doesn\'t start."'))
        self.assertIsNone(self.bash('echo `date` "gh pr create --body \'It doesn\'t\'"'))

    def test_heredoc_of_an_earlier_command_is_not_the_body_of_a_later_pipe(self):
        command = "cat <<'EOF' > f; echo hi | gh pr create --body-file -\nIt doesn't start.\nEOF"
        self.assertIsNone(self.bash(command))
        self.assertIsNone(self.bash(command.replace("; ", " && ")))
        self.assertIn("the PR body", self.bash("cat <<'A' > f; cat <<'B' | gh pr create --body-file -\nx\nA\nIt doesn't start.\nB"))

    def test_ansi_c_quote_with_an_escaped_quote_is_one_word(self):
        self.assertIn("the PR body", self.bash(f"echo $'it\\'s'; {self.BAD_BODY}"))
        self.assertIn("the PR body", self.bash("gh pr create --body $'It doesn\\'t start.'"))
        self.assertIsNone(self.bash("echo $'say \\'" + self.BAD_BODY + "\\''"))

    def test_case_pattern_paren_inside_a_substitution_does_not_close_it(self):
        title = '"$(case $x in a) echo "a;b";; esac)"'
        self.assertIn("the PR body", self.bash(f'gh pr create --title {title} --body "It doesn\'t start."'))
        outer = 'echo "$(case $x in a) echo "x # y";; esac)"'
        self.assertIn("the PR body", self.bash(f"{outer}; {self.BAD_BODY}"))
        self.assertIsNone(self.bash(f'echo "$(case $x in a) echo "{self.BAD_BODY[:-1]}";; esac)"'))

    def test_quotes_inside_arithmetic_hide_their_parentheses(self):
        self.assertIn("the PR body", self.bash(f'echo $(( "))" + 1 )); {self.BAD_BODY}'))
        self.assertIn("the PR body", self.bash(f"echo $(( ')' + 1 )); {self.BAD_BODY}"))
        self.assertIsNone(self.bash('echo $(( "gh pr create --body x(" + 1 )) "It doesn\'t start."'))

    def test_case_as_an_argument_is_not_a_case_block(self):
        self.assertIn("the PR body", self.bash(f'x="$(echo case x in a)"; {self.BAD_BODY}'))
        self.assertIn("the PR body", self.bash(f'gh pr create --title "$(echo case x in)" --body "It doesn\'t start."'))

    def test_quoted_case_subject_may_hold_the_word_in(self):
        for subject in ("'foo in bar'", '"foo in bar"', "$'foo in bar'", "$'it\\'s in bar'"):
            with self.subTest(subject):
                command = f'x=$(case {subject} in *) echo ok;; esac); {self.BAD_BODY}'
                self.assertIn("the PR body", self.bash(command))
                inside = f'gh pr create --title "$(case {subject} in *) echo t;; esac)" --body "It doesn\'t start."'
                self.assertIn("the PR body", self.bash(inside))

    def test_separator_inside_a_group_keeps_the_pipe_after_the_group(self):
        command = "(cat <<'EOF'; true) | gh pr create --body-file -\nIt doesn't start.\nEOF"
        self.assertIn("the PR body", self.bash(command))
        self.assertIsNone(self.bash(command.replace(") |", "); echo |")))

    def test_gh_inside_a_case_subject_substitution_is_checked(self):
        self.assertIn("the PR body", self.bash('(case "$(gh pr create --body should)" in *) echo ok;; esac)'))
        self.assertIn("the PR body", self.bash('(case `gh pr create --body should` in *) echo ok;; esac)'))
        self.assertIsNone(self.bash('(case "gh pr create --body should" in *) echo ok;; esac)'))

    def test_many_case_words_do_not_stall_the_parser(self):
        started = time.monotonic()
        lint.message_sources("echo $(" + "case a " * 20000 + ")")
        self.assertLess(time.monotonic() - started, 5)

    def test_backtick_inside_double_quotes_is_a_substitution(self):
        self.assertIn("the PR body", self.bash('result="`gh pr create --body should`"'))
        self.assertIn("the PR body", self.bash(f'echo "`date`"; {self.BAD_BODY}'))
        self.assertIsNone(self.bash('echo "`date`" \'gh pr create --body should\''))

    def test_separator_inside_a_substitution_keeps_the_heredoc_pipe(self):
        command = "sed <<'EOF' -e \"$(printf %s s/x/x/; true)\" | gh pr create --body-file -\nIt doesn't start.\nEOF"
        self.assertIn("the PR body", self.bash(command))

    def test_commit_keeps_plain_messages_beside_a_substituted_one(self):
        self.assertIn("contraction", self.bash("git commit -m \"fix: x\" -m \"It doesn't start.\" -m `date`"))
        self.assertIsNone(self.bash('git commit -m "fix: x" -m "It starts." -m `date`'))

    def test_ansi_c_escapes_are_decoded(self):
        command = "gh pr create --body $'a\\x41\\u00e9\\101\\r\\e\\\\\\'\\q'"
        self.assertEqual(lint.command_texts(command, self.root), [("pr", "aA\u00e9A\r\x1b\\'\\q")])
        self.assertIn("the PR body", self.bash("gh pr create --body $'It doesn\\x27t start.'"))

    def test_body_file_path_with_a_nul_byte_does_not_hide_later_bodies(self):
        command = 'gh pr create --body-file "a\x00b"; gh issue create --body should'
        self.assertEqual(lint.command_texts(command, self.root), [("issue", "should")])

    def test_odd_and_long_commands_neither_crash_nor_stall(self):
        # main() swallows exceptions, so call command_texts() directly to see a crash.
        import random
        pieces = ["gh pr create ", "--body ", "-b ", "--body-file - ", "<<'EOF'", "<<-E", "<<<", "EOF", "\n", "\\\n",
                  "\"", "'", "$(", "(", ")", "`", "&&", "|", ";", "&", "=", "x", " "]
        generator = random.Random(1420)
        for _ in range(2000):
            lint.command_texts("".join(generator.choice(pieces) for _ in range(30)), self.root)
        started = time.monotonic()
        for command in ("gh pr create " * 20000, "<<a " * 20000, "gh pr create --body \"" + "(" * 50000,
                        "gh pr create --body-file - " + "<<a " * 20000 + "\n", "$(" * 50000, "\\\n" * 50000):
            lint.command_texts(command, self.root)
        self.assertLess(time.monotonic() - started, 5)

    def test_other_commands_and_bad_input_are_silent(self):
        self.assertIsNone(self.bash("ls -la"))
        with mock.patch("sys.stdin", io.StringIO("not json")), mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            self.assertEqual(lint.main(), 0)
        self.assertEqual(out.getvalue(), "")


class DenyOnce(StateDirectory):
    BAD_COMMIT = 'git commit -m "fix: x" -m "It doesn\'t start."'
    BAD_PR = "gh pr create --title t --body-file - <<'EOF'\nThe fix shouldn't change the API.\nEOF"

    def test_first_attempt_is_denied_with_the_retry_note(self):
        output = self.pre(self.BAD_COMMIT)
        self.assertEqual(output["hookEventName"], "PreToolUse")
        self.assertEqual(output["permissionDecision"], "deny")
        self.assertIn("line 3, contraction", output["permissionDecisionReason"])
        self.assertIn("resubmit the identical text unchanged", output["permissionDecisionReason"])

    def test_identical_resubmit_is_allowed(self):
        self.assertIsNotNone(self.pre(self.BAD_COMMIT))
        self.assertIsNone(self.pre(self.BAD_COMMIT))
        # The text counts, not the command around it.
        self.assertIsNone(self.pre(f"cd {self.root} && {self.BAD_COMMIT} && git push"))

    def test_changed_text_with_a_hit_is_denied_again(self):
        self.assertIsNotNone(self.pre(self.BAD_COMMIT))
        self.assertIsNotNone(self.pre('git commit -m "fix: x" -m "It won\'t start."'))

    def test_a_deny_in_one_session_does_not_allow_another(self):
        self.assertIsNotNone(self.pre(self.BAD_COMMIT, session="a"))
        self.assertIsNotNone(self.pre(self.BAD_COMMIT, session="b"))

    def test_expired_deny_no_longer_allows(self):
        self.assertIsNotNone(self.pre(self.BAD_COMMIT))
        with mock.patch("time.time", return_value=time.time() + lint.DENIED_TEXT_SECONDS + 60):
            self.assertIsNotNone(self.pre(self.BAD_COMMIT))

    def test_clean_text_is_allowed_silently(self):
        self.assertIsNone(self.pre('git commit -m "fix: x" -m "It starts."'))
        self.assertIsNone(self.pre("gh pr create --body-file - <<'EOF'\nThe fix keeps the API.\nEOF"))
        self.assertFalse(lint.denied_texts_path().exists())

    def test_pr_body_heredoc_is_denied_then_allowed(self):
        output = self.pre(self.BAD_PR)
        self.assertIn("the PR body", output["permissionDecisionReason"])
        self.assertIsNone(self.pre(self.BAD_PR))
        self.assertIsNotNone(self.pre(self.BAD_PR.replace("shouldn't", "couldn't")))

    def test_an_unsaved_deny_allows_the_call(self):
        # A deny the hook cannot record would block every retry.
        with mock.patch.object(lint, "save_denied_texts", side_effect=OSError("read-only")):
            self.assertIsNone(self.pre(self.BAD_COMMIT))

    def test_corrupt_state_is_treated_as_empty(self):
        path = lint.denied_texts_path()
        path.parent.mkdir(parents=True)
        path.write_text("{not json")
        self.assertIsNotNone(self.pre(self.BAD_COMMIT))
        self.assertIsNone(self.pre(self.BAD_COMMIT))

    def test_malformed_input_allows(self):
        for stdin in ("not json", "[]", '{"tool_name": "Bash", "tool_input": "x"}', ""):
            with self.subTest(stdin), mock.patch("sys.stdin", io.StringIO(stdin)), \
                    mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                self.assertEqual(lint.main(), 0)
                self.assertEqual(out.getvalue(), "")

    def test_file_written_by_the_same_call_is_linted_after_it(self):
        command = "cat > msg <<'EOF'\nfix: x\n\nIt doesn't start.\nEOF\ngit commit -F msg"
        pathlib.Path(self.root, "msg").write_text("fix: old\n\nAn old clean message.\n")
        self.assertIsNone(self.pre(command))
        pathlib.Path(self.root, "msg").write_text("fix: x\n\nIt doesn't start.\n")
        self.assertIn("Amend the commit", self.post(command))

    def test_text_checked_before_the_call_is_not_reported_after_it(self):
        self.assertIsNone(self.post(self.BAD_COMMIT))
        self.assertIsNone(self.post(self.BAD_PR))


if __name__ == "__main__":
    unittest.main(verbosity=1)
