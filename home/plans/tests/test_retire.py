"""`plans close` and `plans cancel`: what each deletes, what it refuses, and how a failed step stops cancel.

No test reaches GitHub or a real repo of the owner. `gh` is a fake script on PATH that logs each call, and `git` is a
wrapper that logs `worktree remove`, fails on demand and otherwise runs the real git on temp repos.
"""

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_cli  # noqa: E402

from plans import parse, retire, store  # noqa: E402

FAKE_GH = """#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("gh " + " ".join(args) + "\\n")
fail = os.environ.get("FAKE_GH_FAIL", "")
if fail and " ".join(args).startswith(fail):
    sys.exit("gh: boom")
if args[:2] == ["pr", "close"] and os.environ.get("FAKE_GH_WRITE_PATH"):
    with open(os.environ["FAKE_GH_WRITE_PATH"], "w") as sibling:
        sibling.write(os.environ["FAKE_GH_WRITE_TEXT"])
states = dict(item.split("=") for item in os.environ.get("FAKE_GH_STATES", "").split(",") if item)
if args[1] == "view":
    key = args[0] + ":" + args[2]
    if key not in states:
        sys.exit("not found")
    print('{"state": "%s"}' % states[key])
    sys.exit(0)
sys.exit(0 if args[1] == "close" else 2)
"""
FAKE_GIT = """#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
if args[:2] == ["worktree", "remove"]:
    with open(os.environ["FAKE_LOG"], "a") as log:
        log.write("git " + " ".join(args) + "\\n")
    if os.environ.get("FAKE_GIT_FAIL") == "worktree remove":
        sys.exit("fatal: boom")
os.execv(os.environ["REAL_GIT"], [os.environ["REAL_GIT"]] + args)
"""
GIT_IDENTITY = ["-c", "user.name=t", "-c", "user.email=t@t"]


class FakeTools:
    """A bin directory with the fake gh and git, and the environment that puts it first on PATH."""

    def __init__(self, directory):
        self.bin = os.path.join(directory, "fakebin")
        os.makedirs(self.bin)
        self.log = os.path.join(directory, "calls.log")
        open(self.log, "w").close()
        for name, text in (("gh", FAKE_GH), ("git", FAKE_GIT)):
            path = os.path.join(self.bin, name)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        self.real_git = shutil.which("git")

    def env(self, states="", gh_fail="", git_fail="", write=("", "")):
        return {"PATH": self.bin + os.pathsep + os.environ["PATH"], "FAKE_LOG": self.log, "REAL_GIT": self.real_git,
                "FAKE_GH_STATES": states, "FAKE_GH_FAIL": gh_fail, "FAKE_GIT_FAIL": git_fail,
                "FAKE_GH_WRITE_PATH": write[0], "FAKE_GH_WRITE_TEXT": write[1]}

    def calls(self):
        with open(self.log, encoding="utf-8") as handle:
            return handle.read().splitlines()

    def writes(self):
        """The calls that change something."""
        return [call for call in self.calls() if " view " not in call]


def add_worktree(repo, branch, path):
    """A commit on main, then a real worktree on a new branch, all in temp dirs."""
    subprocess.run(["git", "-C", repo, *GIT_IDENTITY, "commit", "-q", "--allow-empty", "-m", "start"], check=True)
    subprocess.run(["git", "-C", repo, "worktree", "add", "-q", "-b", branch, path], check=True)


class RetireTest(unittest.TestCase):
    # The helpers of CliTest without its tests, so they do not run twice.
    make_repo, write, add, add_owned, plans, read, tearDown = (
        test_cli.CliTest.make_repo, test_cli.CliTest.write, test_cli.CliTest.add, test_cli.CliTest.add_owned,
        test_cli.CliTest.plans, test_cli.CliTest.read, test_cli.CliTest.tearDown)

    def setUp(self):
        test_cli.CliTest.setUp(self)
        self.tools = FakeTools(self.temp.name)
        self.logs = os.path.join(self.repo, ".logs", "proj")

    def add_logs(self, doc_id):
        path = os.path.join(self.logs, doc_id)
        os.makedirs(path)
        with open(os.path.join(path, "report.md"), "w", encoding="utf-8") as handle:
            handle.write("log")
        return path

    def cancel(self, *args, code=0, **fake):
        env = self.tools.env(**fake)
        return self.plans("cancel", *args, code=code, env=env)

    def branches(self):
        out = subprocess.run(["git", "-C", self.repo, "branch", "--list"], capture_output=True, text=True, check=True)
        return out.stdout

    def depends_on(self, path):
        return parse.load(path).keys["depends_on"]


class CloseTest(RetireTest):
    def test_close_deletes_the_doc_and_its_logs_and_drops_the_dependency_and_nothing_else(self):
        target = self.add("done-piece", 10, status="done")
        waiting = self.add("next-piece", 20, depends_on="[done-piece, other-piece]")
        sibling = self.add("sibling", 30)
        own_logs = self.add_logs("done-piece")
        sibling_logs = self.add_logs("sibling")
        result = self.plans("close", "done-piece", env=self.tools.env())
        self.assertFalse(os.path.exists(target))
        self.assertFalse(os.path.exists(own_logs))
        self.assertTrue(os.path.exists(os.path.join(sibling_logs, "report.md")))
        self.assertTrue(os.path.exists(sibling))
        self.assertEqual(self.depends_on(waiting), ["other-piece"])
        self.assertIn("done: delete .plans/proj/done-piece.md", result.stdout)
        self.assertEqual(self.tools.calls(), [], "close makes no GitHub or git change")

    def test_close_leaves_the_depends_on_of_a_doc_owned_on_another_host(self):
        self.add("done-piece", 10, status="done")
        far = self.add("far", 20, depends_on="[done-piece]")
        store.update(parse.load(far), {"owner_session": "far-1", "owner_host": "nightshift.invalid"})
        near = self.add("near", 30, depends_on="[done-piece]")
        later = self.add("later", 40)
        doc = parse.load(os.path.join(self.repo, ".plans", "proj", "done-piece.md"))
        plan = retire.plan(self.repo, doc, cancel=False)
        self.assertIn("depends_on of far: owned on another host, drop done-piece there", plan.notes)
        self.assertIn("drop done-piece from depends_on of near", plan.steps[0].text)
        # A claim synced in after the plan: the step skips that doc too.
        store.update(parse.load(later), {"depends_on": ["done-piece"], "owner_session": "far-2", "owner_host": "nightshift.invalid"})
        outcome = retire.apply(doc, plan.steps)
        self.assertFalse(outcome.failed)
        self.assertEqual([self.depends_on(path) for path in (far, near, later)], [["done-piece"], [], ["done-piece"]])

    def test_dry_run_prints_the_changes_and_makes_none(self):
        target = self.add("done-piece", 10, pr="6", issue="8", branch="feat/x")
        waiting = self.add("next-piece", 20, depends_on="[done-piece]")
        logs = self.add_logs("done-piece")
        for command in ("close", "cancel"):
            result = self.plans(command, "done-piece", "--dry-run", env=self.tools.env(states="pr:6=OPEN,issue:8=OPEN"))
            self.assertIn("would: delete .plans/proj/done-piece.md", result.stdout)
            self.assertIn("would: drop done-piece from depends_on of next-piece", result.stdout)
        self.assertIn("would: close PR 6", result.stdout)
        self.assertIn("would: close issue 8 as not planned", result.stdout)
        self.assertIn("keep: keep branch feat/x", result.stdout)
        self.assertTrue(os.path.exists(target) and os.path.exists(logs))
        self.assertEqual(self.depends_on(waiting), ["done-piece"])
        self.assertEqual(self.tools.calls(), [])

    def test_a_crafted_id_cannot_reach_outside_plans_and_logs(self):
        outside = os.path.join(self.temp.name, "outside")
        os.makedirs(outside)
        victim = os.path.join(outside, "victim.md")
        open(victim, "w").close()
        self.add("real", 10)
        for crafted in ("../../outside/victim", "../victim", "/etc/passwd", "real/../../x"):
            self.plans("close", crafted, code=2, env=self.tools.env())
        self.assertTrue(os.path.exists(victim))
        # A doc object with a bad id or project, as the board or a future caller could build one.
        for path, doc_id in ((os.path.join(self.repo, ".plans", "proj", "..", "..", "..", "x.md"), "x"),
                             (os.path.join(self.repo, ".plans", "pro j", "x.md"), "x"),
                             (os.path.join(self.repo, ".plans", "proj", "Bad.md"), "Bad"),
                             (os.path.join(outside, "victim.md"), "victim")):
            doc = parse.Doc(path, test_cli.doc_text(doc_id, 10))
            with self.assertRaises(retire.Refused, msg=path):
                retire.plan(self.repo, doc, cancel=False)

    def test_a_symlinked_log_folder_loses_the_link_and_the_target_stays(self):
        self.add("done-piece", 10)
        target = os.path.join(self.temp.name, "precious")
        os.makedirs(target)
        open(os.path.join(target, "keep.txt"), "w").close()
        os.makedirs(self.logs)
        os.symlink(target, os.path.join(self.logs, "done-piece"))
        self.plans("close", "done-piece", env=self.tools.env())
        self.assertFalse(os.path.lexists(os.path.join(self.logs, "done-piece")))
        self.assertTrue(os.path.exists(os.path.join(target, "keep.txt")))

    def test_a_symlinked_project_folder_is_refused_and_nothing_outside_is_deleted(self):
        outside = os.path.join(self.temp.name, "outside")
        os.makedirs(outside)
        victim = os.path.join(outside, "evil-doc.md")
        with open(victim, "w", encoding="utf-8") as handle:
            handle.write(test_cli.doc_text("evil-doc", 10, project="evil"))
        os.makedirs(os.path.join(self.repo, ".plans"), exist_ok=True)
        os.symlink(outside, os.path.join(self.repo, ".plans", "evil"))
        self.plans("close", "evil-doc", code=1, env=self.tools.env())
        self.assertTrue(os.path.exists(victim))

    def test_a_symlinked_log_project_folder_is_refused_and_nothing_outside_is_deleted(self):
        path = self.add("piece", 10)
        outside = os.path.join(self.temp.name, "outside-logs")
        os.makedirs(os.path.join(outside, "piece"))
        report = os.path.join(outside, "piece", "report.md")
        open(report, "w").close()
        os.makedirs(os.path.join(self.repo, ".logs"))
        os.symlink(outside, os.path.join(self.repo, ".logs", "proj"))
        self.plans("close", "piece", code=1, env=self.tools.env())
        self.assertTrue(os.path.exists(report))
        self.assertTrue(os.path.exists(path))

    def test_another_sessions_doc_is_refused_until_forced(self):
        path = self.add("owned", 10, owner="dotfiles-1")
        for args in (["--as", "dotfiles-2"], []):
            result = self.plans("close", "owned", *args, code=1, env=self.tools.env())
            self.assertIn("owned by dotfiles-1", result.stderr)
        self.assertTrue(os.path.exists(path))
        self.plans("close", "owned", "--as", "dotfiles-2", "--force", env=self.tools.env())
        self.assertFalse(os.path.exists(path))

    def test_a_dead_owners_doc_is_freed_and_closed_without_force(self):
        path = self.add_owned("orphan", 10, "gone-1", "id-x", test_cli.DEAD_PID)
        result = self.plans("close", "orphan", "--as", "dotfiles-2", env=self.tools.env())
        self.assertIn("freed, owner gone-1 is dead", result.stderr)
        self.assertFalse(os.path.exists(path))

    def test_the_owner_and_a_same_name_session_check(self):
        path = self.add("mine", 10, owner="dotfiles-1")
        self.plans("close", "mine", "--as", "dotfiles-1", env=self.tools.env())
        self.assertFalse(os.path.exists(path))
        clash = self.add("clash", 10, owner="dotfiles-1")
        parse_doc = parse.load(clash)
        store.update(parse_doc, {"owner_session_id": "id-b", "owner_session_pid": 200})
        result = self.plans("close", "clash", "--as", "dotfiles-1", code=1, env={**self.tools.env(), **test_cli.SESSION_A})
        self.assertIn("also named dotfiles-1", result.stderr)
        self.assertTrue(os.path.exists(clash))


class VanishedTest(RetireTest):
    def test_a_doc_deleted_after_it_was_read_is_reported_not_a_crash(self):
        path = self.add("gone", 10)
        doc = parse.load(path)
        plan = retire.plan(self.repo, doc, cancel=False)
        os.unlink(path)
        with self.assertRaises(store.Vanished):
            retire.apply(doc, plan.steps)

    def test_a_doc_deleted_between_the_check_and_the_delete_is_a_skipped_step(self):
        path = self.add("gone", 10)
        doc = parse.load(path)
        plan = retire.plan(self.repo, doc, cancel=False)
        with mock.patch.object(retire.store, "check_unchanged", lambda *_: os.path.exists(path) and os.unlink(path)):
            outcome = retire.apply(doc, plan.steps)
        self.assertFalse(outcome.failed)
        self.assertEqual(outcome.lines[-1], ("skipped", "delete .plans/proj/gone.md: the doc was already deleted"))

    def test_a_dependent_deleted_meanwhile_is_skipped_and_the_rest_goes_on(self):
        path = self.add("gone", 10)
        dependent = self.add("dependent", 20, depends_on="[gone]")
        doc = parse.load(path)
        plan = retire.plan(self.repo, doc, cancel=False)
        os.unlink(dependent)
        outcome = retire.apply(doc, plan.steps)
        self.assertFalse(outcome.failed)
        self.assertEqual(outcome.lines[0][0], "skipped")
        self.assertFalse(os.path.exists(path))

    def test_a_doc_changed_since_it_was_read_is_refused_before_any_step(self):
        path = self.add("moved", 10, pr="6")
        doc = parse.load(path)
        plan = retire.plan(self.repo, doc, cancel=True)
        store.update(parse.load(path), {"owner_session": "dotfiles-9"})
        with self.assertRaises(store.Conflict):
            retire.apply(doc, plan.steps)
        self.assertTrue(os.path.exists(path))
        self.assertEqual(self.tools.calls(), [])


class MidRunChangeTest(RetireTest):
    def test_a_claim_by_a_same_named_session_during_the_run_refuses_the_delete(self):
        path = self.add("mine", 10, owner="dotfiles-1")
        doc = parse.load(path)
        plan = retire.plan(self.repo, doc, cancel=False)
        store.update(parse.load(path), {"owner_session_id": "id-b", "owner_session_pid": 200})
        with self.assertRaises(store.Conflict):
            retire.apply(doc, plan.steps)
        self.assertTrue(os.path.exists(path))

    def test_a_dependency_added_after_the_plan_is_dropped_too(self):
        path = self.add("done-piece", 10)
        later = self.add("later", 20)
        doc = parse.load(path)
        plan = retire.plan(self.repo, doc, cancel=False)
        store.update(parse.load(later), {"depends_on": ["done-piece", "x"]})
        outcome = retire.apply(doc, plan.steps)
        self.assertFalse(outcome.failed)
        self.assertEqual(self.depends_on(later), ["x"])
        self.assertFalse(os.path.exists(path))


    def test_a_claim_during_the_dependency_step_stops_before_the_logs_are_deleted(self):
        path = self.add("mine", 10, owner="dotfiles-1")
        logs = self.add_logs("mine")
        doc = parse.load(path)
        plan = retire.plan(self.repo, doc, cancel=False)

        def claim_meanwhile(*_):
            store.update(parse.load(path), {"owner_session_id": "id-b", "owner_session_pid": 200})

        with mock.patch.object(retire, "drop_dependencies", claim_meanwhile):
            outcome = retire.apply(doc, plan.steps)
        self.assertTrue(outcome.failed)
        self.assertTrue(os.path.exists(os.path.join(logs, "report.md")))
        self.assertTrue(os.path.exists(path))


class GitEnvironmentTest(RetireTest):
    def test_git_variables_from_a_hook_do_not_redirect_the_git_calls(self):
        subprocess.run(["git", "-C", self.repo, "remote", "add", "origin", "git@github.com:o/r.git"], check=True)
        elsewhere = os.path.join(self.temp.name, "elsewhere")
        os.makedirs(elsewhere)
        with mock.patch.dict(os.environ, {"GIT_DIR": elsewhere, "GIT_WORK_TREE": elsewhere}):
            self.assertEqual(retire.current_repo_slug(self.repo), "o/r")
            self.assertEqual(retire.git(self.repo, "worktree", "list", "--porcelain").returncode, 0)


class CancelTest(RetireTest):
    def piece(self, **keys):
        """A doc with a PR, an issue and a branch that has a real worktree."""
        self.worktree = os.path.join(self.temp.name, "wt")
        add_worktree(self.repo, "feat/x", self.worktree)
        path = self.add("piece", 10, pr="6", issue="8", branch="feat/x", **keys)
        self.add_logs("piece")
        return path

    STATES = "pr:6=OPEN,issue:8=OPEN"

    def test_cancel_closes_the_pr_and_issue_removes_the_clean_worktree_keeps_the_branch_and_deletes_the_files(self):
        path = self.piece()
        waiting = self.add("later", 20, depends_on="[piece]")
        result = self.cancel("piece", states=self.STATES)
        self.assertEqual(self.tools.writes(), [
            "gh pr close 6 --comment " + retire.PR_COMMENT,
            "gh issue close 8 --reason not planned",
            f"git worktree remove {os.path.realpath(self.worktree)}",
        ])
        self.assertFalse(os.path.exists(self.worktree))
        self.assertIn("feat/x", self.branches())
        self.assertFalse(os.path.exists(path))
        self.assertFalse(os.path.exists(os.path.join(self.logs, "piece")))
        self.assertEqual(self.depends_on(waiting), [])
        self.assertIn("done: close PR 6", result.stdout)

    def test_a_failed_step_stops_cancel_keeps_the_doc_and_says_what_ran_and_what_did_not(self):
        path = self.piece()
        result = self.cancel("piece", code=1, states=self.STATES, gh_fail="issue close")
        self.assertEqual(self.tools.writes(), ["gh pr close 6 --comment " + retire.PR_COMMENT, "gh issue close 8 --reason not planned"])
        self.assertTrue(os.path.exists(self.worktree))
        self.assertTrue(os.path.exists(path))
        self.assertTrue(os.path.exists(os.path.join(self.logs, "piece")))
        lines = result.stdout.splitlines()
        self.assertTrue(lines[0].startswith("done: close PR 6"), lines)
        self.assertTrue(lines[1].startswith("failed: close issue 8"), lines)
        self.assertTrue(lines[2].startswith("not run: remove the worktree"), lines)
        self.assertTrue(any(line.startswith("not run: delete .plans/proj/piece.md") for line in lines))
        self.assertIn("the doc is kept", result.stderr)

    def test_a_failed_worktree_removal_keeps_the_files(self):
        path = self.piece()
        result = self.cancel("piece", code=1, states=self.STATES, git_fail="worktree remove")
        self.assertTrue(os.path.exists(path) and os.path.exists(self.worktree))
        self.assertTrue(os.path.exists(os.path.join(self.logs, "piece")))
        self.assertIn("failed: remove the worktree", result.stdout)
        self.assertIn("done: close PR 6", result.stdout)
        # The retry after the cause is fixed finds the PR closed and finishes.
        retry = self.cancel("piece", states="pr:6=CLOSED,issue:8=CLOSED")
        self.assertFalse(os.path.exists(path) or os.path.exists(self.worktree))
        self.assertIn("skipped: close PR 6", retry.stdout)

    def test_a_missing_gh_stops_before_anything_else(self):
        path = self.piece()
        # A PATH with the real git and no gh.
        bare = os.path.join(self.temp.name, "bare")
        os.makedirs(bare)
        os.symlink(self.tools.real_git, os.path.join(bare, "git"))
        result = self.plans("cancel", "piece", code=1, env={"PATH": bare})
        self.assertIn("needs the gh CLI", result.stdout)
        self.assertTrue(os.path.exists(path) and os.path.exists(self.worktree))

    def test_an_issue_that_another_doc_names_stays_open(self):
        self.piece()
        self.add("sibling", 20, issue="8")
        result = self.cancel("piece", states=self.STATES)
        self.assertEqual(self.tools.writes()[:2], ["gh pr close 6 --comment " + retire.PR_COMMENT,
                                                   f"git worktree remove {os.path.realpath(self.worktree)}"])
        self.assertNotIn("issue close", " ".join(self.tools.calls()))
        self.assertIn("keep: keep issue 8 open: sibling also names it", result.stdout)

    def test_an_issue_in_another_repo_with_the_same_number_does_not_count_as_shared(self):
        self.piece()
        subprocess.run(["git", "-C", self.repo, "remote", "add", "origin", "git@github.com:o/r.git"], check=True)
        self.add("sibling", 20, issue="https://github.com/other/repo/issues/8")
        self.cancel("piece", states=self.STATES)
        self.assertIn("gh issue close 8 --reason not planned", self.tools.calls())

    def test_the_same_issue_by_url_in_this_repo_counts_as_shared(self):
        self.piece()
        subprocess.run(["git", "-C", self.repo, "remote", "add", "origin", "https://github.com/o/r.git"], check=True)
        self.add("sibling", 20, issue="https://github.com/o/r/issues/8")
        result = self.cancel("piece", states=self.STATES)
        self.assertNotIn("issue close", " ".join(self.tools.calls()))
        self.assertIn("sibling also names it", result.stdout)

    def test_a_sibling_that_names_the_issue_during_the_pr_close_keeps_the_issue_open(self):
        self.piece()
        sibling = os.path.join(self.repo, ".plans", "proj", "late.md")
        text = test_cli.doc_text("late", 20, issue="8")
        result = self.cancel("piece", states=self.STATES, write=(sibling, text))
        self.assertNotIn("issue close", " ".join(self.tools.calls()))
        self.assertIn("skipped: close issue 8", result.stdout)
        self.assertIn("late now also names it", result.stdout)

    def test_a_dirty_worktree_stays_and_the_rest_of_the_cancel_goes_on(self):
        path = self.piece()
        with open(os.path.join(self.worktree, "wip.txt"), "w", encoding="utf-8") as handle:
            handle.write("unsaved")
        result = self.cancel("piece", states=self.STATES)
        self.assertTrue(os.path.exists(os.path.join(self.worktree, "wip.txt")))
        self.assertNotIn("worktree remove", " ".join(self.tools.calls()))
        self.assertIn("skipped: remove the worktree", result.stdout)
        self.assertIn("uncommitted changes", result.stdout)
        self.assertFalse(os.path.exists(path))

    def test_a_pr_that_is_not_open_is_left_alone(self):
        self.piece()
        result = self.cancel("piece", states="pr:6=MERGED,issue:8=CLOSED")
        self.assertNotIn("close", " ".join(call for call in self.tools.calls() if " view " not in call and "worktree" not in call))
        self.assertIn("skipped: close PR 6", result.stdout)

    def test_the_main_checkout_is_never_removed(self):
        subprocess.run(["git", "-C", self.repo, *GIT_IDENTITY, "commit", "-q", "--allow-empty", "-m", "start"], check=True)
        path = self.add("piece", 10, branch="main")
        result = self.cancel("piece")
        self.assertTrue(os.path.isdir(self.repo))
        self.assertNotIn("worktree remove", " ".join(self.tools.calls()))
        self.assertIn("main checkout", result.stdout)
        self.assertFalse(os.path.exists(path))

    def test_a_value_that_looks_like_a_flag_is_refused_and_nothing_changes(self):
        path = self.add("piece", 10, pr='"--web"', issue="8")
        result = self.cancel("piece", code=1, states=self.STATES)
        self.assertIn("is no number or GitHub URL", result.stderr)
        self.assertTrue(os.path.exists(path))
        self.assertEqual(self.tools.calls(), [])
        path = self.add("other", 20, branch='"-bad"')
        self.cancel("other", code=1)
        self.assertTrue(os.path.exists(path))

    def test_a_doc_with_no_pr_issue_or_branch_is_just_closed(self):
        path = self.add("plain", 10)
        self.cancel("plain")
        self.assertFalse(os.path.exists(path))
        self.assertEqual(self.tools.calls(), [])


if __name__ == "__main__":
    unittest.main()
