"""Each command end to end: the entry point run as a process on temp git repos, with a stub gh for lint --gh."""

import datetime
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

sys.dont_write_bytecode = True
PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(PACKAGE, ".local", "lib", "plans"))
from plans import cli, liveness, parse, query  # noqa: E402
from test_liveness import fake_proc  # noqa: E402

# Git sets these in hooks, where the check can run. Inherited, they point every git call here at that other repo.
for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
             "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_PREFIX"):
    os.environ.pop(name, None)
ENTRY = os.path.join(PACKAGE, ".local", "bin", "plans")
LIBRARY = os.path.join(PACKAGE, ".local", "lib", "plans")
# Runs the entry point with liveness.PROC_ROOT on the test's fake /proc, so no test judges a real pid.
WITH_FAKE_PROC = ("import runpy, sys; library, proc, entry = sys.argv[1:4]; sys.path.insert(0, library); "
                  "from plans import liveness; liveness.PROC_ROOT = proc; sys.argv = [entry, *sys.argv[4:]]; "
                  "runpy.run_path(entry, run_name='__main__')")
TODAY = datetime.date.today().isoformat()
SECTIONS = "\n## Goal\n\n## Decisions\n\n## Plan\n\n## Open questions\n\n{questions}\n## Owner checks\n"
FAKE_GH = """#!/usr/bin/env python3
import sys
args = sys.argv[1:]
states = {("pr", "5"): "MERGED", ("pr", "6"): "OPEN", ("issue", "7"): "CLOSED", ("issue", "8"): "OPEN"}
if args[0] in ("pr", "issue"):
    state = states.get((args[0], args[2]))
    if state is None:
        sys.exit("GraphQL: Could not resolve to a PullRequest")
    print('{"state": "%s"}' % state)
elif args[0] == "api":
    if args[1].endswith("/heads/gone"):
        sys.exit("gh: Not Found (HTTP 404)")
else:
    sys.exit(2)
"""


def doc_text(doc_id, rank, project="proj", status="planned", owner="none", waiting_on='""', depends_on="[]",
             questions="", pr="none", issue="none", branch="none"):
    return (f"---\nid: {doc_id}\nproject: {project}\nkind: feature\nstatus: {status}\nowner_session: {owner}\n"
            f"rank: {rank}\ndepends_on: {depends_on}\nwaiting_on: {waiting_on}\nissue: {issue}\npr: {pr}\n"
            f"branch: {branch}\nupdated: \"2026-11-01\"\n---\n# {doc_id}\n" + SECTIONS.format(questions=questions))


# Two live sessions that Claude Code gave the same name.
SESSION_A = {"CLAUDE_CODE_SESSION_ID": "id-a", "CLAUDE_PID": "100"}
SESSION_B = {"CLAUDE_CODE_SESSION_ID": "id-b", "CLAUDE_PID": "200"}
# The fake /proc runs Claude at the session pids above and at the resumed pid 300. DEAD_PID runs another program.
LIVE_PIDS = (100, 200, 300)
DEAD_PID = 400


class CliTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = os.path.join(self.temp.name, "home")
        self.repo = self.make_repo(os.path.join(self.temp.name, "repo"))
        self.env = {**os.environ, "HOME": self.home, "XDG_CONFIG_HOME": os.path.join(self.home, ".config")}
        for name in ("PLANS_SESSION", "CLAUDE_CODE_SESSION_ID", "CLAUDE_PID"):
            self.env.pop(name, None)
        self.env.pop("GITHUB_DIR", None)
        self.proc = fake_proc(os.path.join(self.temp.name, "proc"), claude_pids=LIVE_PIDS, other_pids=[DEAD_PID])
        patcher = mock.patch.object(liveness, "PROC_ROOT", self.proc)
        patcher.start()
        self.addCleanup(patcher.stop)

    def tearDown(self):
        for dirpath, _, names in os.walk(self.temp.name):
            for name in names:
                if os.path.islink(os.path.join(dirpath, name)):
                    continue
                try:
                    os.chmod(os.path.join(dirpath, name), 0o600)
                except OSError:
                    pass
        self.temp.cleanup()

    def make_repo(self, path):
        os.makedirs(path)
        subprocess.run(["git", "init", "-q", "-b", "main", path], check=True)
        return path

    def write(self, rel, text, repo=None):
        path = os.path.join(repo or self.repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    def add(self, doc_id, rank, repo=None, **keys):
        project = keys.get("project", "proj")
        return self.write(f".plans/{project}/{doc_id}.md", doc_text(doc_id, rank, **keys), repo)

    def plans(self, *args, cwd=None, env=None, code=0):
        result = subprocess.run([sys.executable, "-B", "-c", WITH_FAKE_PROC, LIBRARY, self.proc, ENTRY, *args],
                                cwd=cwd or self.repo, env={**self.env, **(env or {})}, capture_output=True, text=True)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def read(self, path):
        with open(path, encoding="utf-8") as handle:
            return handle.read()

    def test_ls_lines_in_rank_order(self):
        self.add("second", 20, owner="dotfiles-56", waiting_on='"owner: pick"')
        self.add("first", 10, project="other")
        result = self.plans("ls")
        self.assertEqual(result.stdout, "first\tplanned\tnone\t10\t\nsecond\tplanned\tdotfiles-56\t20\towner: pick\n")
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.plans("ls", "--owner", "dotfiles-56").stdout.split("\t")[0], "second")
        self.assertEqual(self.plans("ls", "--project", "other").stdout.split("\t")[0], "first")
        self.assertEqual(self.plans("ls", "--status", "done").stdout, "")
        data = json.loads(self.plans("ls", "--json").stdout)
        self.assertEqual(data[0]["rank"], 10)
        self.assertEqual(data[0]["depends_on"], [])
        self.assertEqual(data[0]["fix_rounds"], 0)
        self.assertEqual(data[0]["path"], os.path.join(self.repo, ".plans/other/first.md"))

    def test_ls_from_a_worktree_reads_the_main_checkout(self):
        self.add("first", 10)
        self.write("README", "x\n")
        subprocess.run(["git", "-C", self.repo, "add", "README"], check=True)
        subprocess.run(["git", "-C", self.repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "x"], check=True)
        worktree = os.path.join(self.temp.name, "wt")
        subprocess.run(["git", "-C", self.repo, "worktree", "add", "-q", worktree], check=True)
        self.assertEqual(self.plans("ls", cwd=os.path.join(worktree)).stdout.split("\t")[0], "first")

    def test_ls_names_old_layouts_and_skips_their_docs(self):
        self.add("first", 10)
        self.write(".plans/roadmap.md", "# roadmap\n")
        self.write(".plans/topic/topic.md", "---\nkind: tracker\nstatus: active\n---\n")
        self.write(".plans/topic/broken.md", "no front matter\n")
        result = self.plans("ls")
        self.assertEqual(result.stdout, "first\tplanned\tnone\t10\t\n")
        self.assertIn("old layout .plans/roadmap.md; migrate this repo", result.stderr)
        self.assertIn("1 docs on the old kind plan/tracker/handoff scheme; migrate this repo", result.stderr)
        self.assertIn("broken.md: outside the front matter subset", result.stderr)
        self.assertIn(os.path.join(self.repo, ".plans/topic/broken.md") + ": line 1: no front matter", self.plans("show", "broken", code=2).stderr)

    def test_ls_all_scans_the_configured_roots(self):
        dev = os.path.join(self.temp.name, "dev")
        one = self.make_repo(os.path.join(dev, "group", "one"))
        too_deep = self.make_repo(os.path.join(dev, "a", "b", "c", "deep"))
        nested = self.make_repo(os.path.join(one, "vendor", "nested"))
        for name, repo in (("in-one", one), ("in-deep", too_deep), ("in-nested", nested), ("in-repo", self.repo)):
            self.add(name, 10, repo=repo)
        self.write(".config/plans/roots", f"# repos\n{dev}\n\n{self.repo}\n", repo=self.home)
        lines = self.plans("ls", "--all", cwd=self.temp.name).stdout.splitlines()
        self.assertEqual([line.split("\t")[:2] for line in lines], [["one", "in-one"], ["repo", "in-repo"]])

    def test_next(self):
        self.add("asks", 10, waiting_on='"owner: which colour"')
        self.add("blocked", 20, depends_on="[asks]")
        self.add("theirs", 25, owner="other-1")
        self.add("mine", 30, owner="me-1")
        self.add("free", 40)
        expected = "ask\tasks\towner: which colour\nblocked\tblocked\tblocked by asks\nwork\tmine\tplanned\n"
        self.assertEqual(self.plans("next", "--as", "me-1").stdout, expected)
        self.assertEqual(self.plans("next", env={"PLANS_SESSION": "me-1"}).stdout, expected)
        self.assertTrue(self.plans("next").stdout.endswith("work\tfree\tplanned\n"))
        self.assertEqual(json.loads(self.plans("next", "--as", "me-1", "--json").stdout)[2]["action"], "work")
        skipped = self.plans("next", "--as", "me-1", "--skip", "mine", "--skip", "asks").stdout
        self.assertEqual(skipped, "blocked\tblocked\tblocked by asks\nwork\tfree\tplanned\n")

    def test_next_all(self):
        self.add("first", 10)
        self.add("theirs", 15, owner="other-1")
        self.add("second", 20, status="approved")
        self.add("after", 25, depends_on="[second]")
        self.add("third", 30, owner="me-1")
        self.assertEqual(self.plans("next", "--as", "me-1").stdout, "work\tfirst\tplanned\n")
        expected = ("work\tfirst\tplanned\nwork\tsecond\tapproved\nblocked\tafter\tblocked by second\n"
                    "work\tthird\tplanned\n")
        self.assertEqual(self.plans("next", "--all", "--as", "me-1").stdout, expected)
        as_json = json.loads(self.plans("next", "--all", "--as", "me-1", "--json").stdout)
        self.assertEqual([step["id"] for step in as_json if step["action"] == "work"], ["first", "second", "third"])

    def test_waiting_and_questions(self):
        self.add("asks", 10, waiting_on='"owner: which colour"', questions="- [ ] Which colour?\n- [x] Old one\n")
        self.add("calm", 20)
        self.assertEqual(self.plans("waiting").stdout, "asks\tplanned\tnone\t10\towner: which colour\n")
        self.assertEqual(self.plans("questions").stdout, "asks\tWhich colour?\n")

    def test_show(self):
        path = self.add("demo", 10, questions="- [ ] One?\n")
        self.assertEqual(self.plans("show", "demo").stdout, self.read(path))
        self.assertEqual(self.plans("show", "demo", "--section", "open questions").stdout, "- [ ] One?\n")
        self.assertEqual(json.loads(self.plans("show", "demo", "--json").stdout)["id"], "demo")
        self.assertIn("no doc 'nope'", self.plans("show", "nope", code=2).stderr)

    def test_set_changes_only_its_lines(self):
        path = self.add("demo", 10)
        before = self.read(path)
        self.plans("set", "demo", "status=building", "depends_on=a, b", "waiting_on=owner: pick", "pr=12")
        after = self.read(path)
        doc = parse.load(path)
        self.assertEqual((doc.keys["status"], doc.keys["depends_on"], doc.keys["waiting_on"], doc.keys["pr"]),
                         ("building", ["a", "b"], "owner: pick", 12))
        self.assertEqual(doc.keys["updated"], TODAY)
        self.assertEqual(after.split("---\n", 2)[2], before.split("---\n", 2)[2])
        changed = [b for a, b in zip(before.splitlines(), after.splitlines()) if a != b]
        self.assertEqual([line.split(":")[0] for line in changed], ["status", "depends_on", "waiting_on", "pr", "updated"])

    def test_set_adds_fix_rounds_to_a_doc_without_it(self):
        path = self.add("demo", 10)
        self.plans("set", "demo", "fix_rounds=2")
        self.assertEqual(parse.load(path).keys["fix_rounds"], 2)
        self.assertEqual(self.plans("lint").stdout, "")

    def test_set_refuses_bad_values(self):
        path = self.add("demo", 10)
        before = self.read(path)
        for pair in ("project=other", "waiting_on=two\nlines", "branch=a\rb", "status=active", "kind=plan", "rank=high", "fix_rounds=-1", "owner_session=Bob", "id=x", "updated=x", "colour=x", "nopair"):
            with self.subTest(pair=pair):
                self.plans("set", "demo", pair, code=2)
        self.assertEqual(self.read(path), before)

    def test_set_after_a_stale_read_exits_3(self):
        path = self.add("demo", 10)
        real_load = cli.load_doc

        def load_then_race(root, doc_id):
            doc = real_load(root, doc_id)
            # Another writer lands between this read and the write.
            self.write(".plans/proj/demo.md", self.read(path).replace("status: planned", "status: review"))
            return doc

        with mock.patch.object(cli, "load_doc", load_then_race), mock.patch.object(cli.roots, "main_checkout", return_value=self.repo):
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = cli.main(["set", "demo", "status=building"])
        self.assertEqual(code, 3)
        self.assertIn("changed since it was read: status", stderr.getvalue())
        self.assertIn("status: review", self.read(path))

    def test_claim(self):
        free, theirs = self.add("free", 10), self.add("theirs", 20, owner="other-1")
        self.assertIn("--as <session>", self.plans("claim", "free", code=2).stderr)
        self.plans("claim", "free", env={"PLANS_SESSION": "me-1"})
        self.assertEqual(parse.load(free).keys["owner_session"], "me-1")
        self.plans("claim", "free", "--as", "me-1")
        self.assertIn("owned by other-1", self.plans("claim", "theirs", "--as", "me-1", code=1).stderr)
        self.assertEqual(parse.load(theirs).keys["owner_session"], "other-1")
        self.plans("claim", "theirs", "--as", "me-1", "--force")
        self.assertEqual(parse.load(theirs).keys["owner_session"], "me-1")

    def test_handoff(self):
        mine, free, theirs = self.add("mine", 10, owner="me-1"), self.add("free", 20), self.add("theirs", 30, owner="other-1")
        before = self.read(mine)
        self.plans("handoff", "--to", "next-2", "mine", "theirs", "--as", "me-1", code=1)
        self.assertEqual(self.read(mine), before)
        self.plans("handoff", "--to", "next-2", "mine", "free", "--as", "me-1")
        self.assertEqual([parse.load(p).keys["owner_session"] for p in (mine, free)], ["next-2", "next-2"])
        self.plans("handoff", "--to", "next-2", "theirs", "--as", "me-1", "--force")
        self.assertEqual(parse.load(theirs).keys["owner_session"], "next-2")

    def add_owned(self, doc_id, rank, owner, session_id, pid):
        path = self.add(doc_id, rank, owner=owner)
        self.write(path, self.read(path).replace("updated:", f"owner_session_id: {session_id}\nowner_session_pid: {pid}\nupdated:"))
        return path

    def proof(self, path):
        keys = parse.load(path).keys
        return keys.get("owner_session_id"), keys.get("owner_session_pid")

    def test_claim_writes_the_session_values(self):
        free, named = self.add("free", 10), self.add("named", 20, owner="me-1")
        self.plans("claim", "free", "--as", "me-1", env=SESSION_A)
        self.assertEqual(self.proof(free), ("id-a", 100))
        # A doc from before the values matches by name, and the claim adds them.
        self.plans("claim", "named", "--as", "me-1", env=SESSION_A)
        self.assertEqual(self.proof(named), ("id-a", 100))
        self.assertEqual(self.plans("lint").stdout, "")

    def test_another_session_of_the_same_name_is_refused(self):
        path = self.add_owned("demo", 10, "me-1", "id-a", 100)
        before = self.read(path)
        for args in (("claim", "demo"), ("handoff", "--to", "next-2", "demo")):
            with self.subTest(args=args):
                stderr = self.plans(*args, "--as", "me-1", env=SESSION_B, code=1).stderr
                self.assertIn("demo is owned by another session also named me-1", stderr)
                self.assertIn("with --force", stderr)
        self.assertEqual(self.read(path), before)
        self.plans("claim", "demo", "--as", "me-1", "--force", env=SESSION_B)
        self.assertEqual(self.proof(path), ("id-b", 200))

    def test_a_clear_or_a_resume_still_matches_and_refreshes_the_values(self):
        path = self.add_owned("demo", 10, "me-1", "id-a", 100)
        cleared = {"CLAUDE_CODE_SESSION_ID": "id-new", "CLAUDE_PID": "100"}
        self.plans("claim", "demo", "--as", "me-1", env=cleared)
        self.assertEqual(self.proof(path), ("id-new", 100))
        resumed = {"CLAUDE_CODE_SESSION_ID": "id-new", "CLAUDE_PID": "300"}
        self.plans("set", "demo", "status=building", env=resumed)
        self.assertEqual(self.proof(path), ("id-new", 300))
        self.assertEqual(self.plans("next", "--as", "me-1", env=resumed).stdout, "work\tdemo\tbuilding\n")

    def test_a_plain_set_keeps_the_values_current_across_a_clear_and_a_resume(self):
        path = self.add("demo", 10)
        self.plans("claim", "demo", "--as", "me-1", env=SESSION_A)
        cleared = {"CLAUDE_CODE_SESSION_ID": "id-new", "CLAUDE_PID": "100"}
        self.plans("set", "demo", "status=building", env=cleared)
        self.assertEqual(self.proof(path), ("id-new", 100))
        resumed = {"CLAUDE_CODE_SESSION_ID": "id-new", "CLAUDE_PID": "300"}
        self.assertEqual(self.plans("next", "--as", "me-1", env=resumed).stdout, "work\tdemo\tbuilding\n")
        self.plans("claim", "demo", "--as", "me-1", env=resumed)
        # A plain set from another session leaves the values alone, and so does one from a human shell.
        self.plans("set", "demo", "status=approved", env=SESSION_B)
        self.plans("set", "demo", "status=building")
        self.assertEqual(self.proof(path), ("id-new", 300))

    def test_a_claim_during_a_handoff_refuses_the_handoff(self):
        path = self.add("demo", 10, owner="me-1")
        real_load = cli.load_doc
        raced = []

        def load_then_claim(root, doc_id):
            doc = real_load(root, doc_id)
            # The owner re-claims between this read and the write, which adds its values under the same name.
            self.write(".plans/proj/demo.md", self.read(path).replace("updated:", "owner_session_id: id-a\nowner_session_pid: 100\nupdated:"))
            raced.append(self.read(path))
            return doc

        with mock.patch.object(cli, "load_doc", load_then_claim), mock.patch.object(cli.roots, "main_checkout", return_value=self.repo):
            with redirect_stderr(io.StringIO()):
                code = cli.main(["handoff", "--to", "next-2", "demo", "--as", "me-1"])
        self.assertEqual(code, 3)
        self.assertEqual(self.read(path), raced[0])

    def test_next_skips_a_doc_another_session_of_the_same_name_owns(self):
        self.add_owned("theirs", 10, "me-1", "id-a", 100)
        self.add("free", 20)
        self.assertEqual(self.plans("next", "--as", "me-1", env=SESSION_B).stdout, "work\tfree\tplanned\n")
        self.assertEqual(self.plans("next", "--as", "me-1", env=SESSION_A).stdout, "work\ttheirs\tplanned\n")

    def test_a_dead_owner_is_freed_on_read_and_a_live_one_kept(self):
        dead = self.add_owned("dead", 10, "gone-1", "id-x", DEAD_PID)
        live = self.add_owned("live", 20, "other-1", "id-a", 100)
        older = self.add("older", 30, owner="older-1")
        result = self.plans("ls")
        self.assertEqual(result.stdout.splitlines()[0], "dead\tplanned\tnone\t10\t")
        self.assertEqual(result.stderr, f"plans: {dead}: freed, owner gone-1 is dead (pid {DEAD_PID} runs no Claude)\n")
        self.assertEqual(self.proof(dead), ("", ""))
        self.assertEqual([parse.load(path).keys["owner_session"] for path in (live, older)], ["other-1", "older-1"])
        self.assertEqual(self.plans("ls").stderr, "")

    def test_next_offers_and_claim_takes_a_doc_whose_owner_died(self):
        self.add_owned("dead", 10, "gone-1", "id-x", DEAD_PID)
        self.assertEqual(self.plans("next", "--as", "me-1", env=SESSION_B).stdout, "work\tdead\tplanned\n")
        path = self.add_owned("dead2", 20, "gone-1", "id-x", DEAD_PID)
        self.plans("claim", "dead2", "--as", "me-1", env=SESSION_B)
        self.assertEqual(parse.load(path).keys["owner_session"], "me-1")
        self.assertEqual(self.proof(path), ("id-b", 200))

    def test_a_release_that_loses_a_race_stays_quiet(self):
        dead = self.add_owned("dead", 10, "gone-1", "id-x", DEAD_PID)
        gone = self.add_owned("gone", 20, "gone-1", "id-x", DEAD_PID)
        real_check = liveness.owner_is_alive

        def check_then_race(doc):
            alive = real_check(doc)
            if doc.path == dead and os.path.exists(gone):
                # The owner comes back under a new pid on one doc, and the other doc is deleted.
                self.write(dead, self.read(dead).replace(f"owner_session_pid: {DEAD_PID}", "owner_session_pid: 300"))
                os.unlink(gone)
            return alive

        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(liveness, "owner_is_alive", check_then_race), \
                mock.patch.object(cli.roots, "main_checkout", return_value=self.repo), redirect_stdout(stdout), redirect_stderr(stderr):
            code = cli.main(["ls"])
        self.assertEqual((code, stderr.getvalue()), (0, ""))
        self.assertEqual([line.split("\t")[2] for line in stdout.getvalue().splitlines()], ["gone-1", "gone-1"])
        self.assertEqual(self.proof(dead), ("id-x", 300))

    def test_a_human_shell_matches_by_name_and_keeps_the_values_unless_the_owner_changes(self):
        path = self.add_owned("demo", 10, "me-1", "id-a", 100)
        self.plans("claim", "demo", "--as", "me-1")
        self.plans("set", "demo", "status=building")
        self.assertEqual(self.plans("next", "--as", "me-1").stdout, "work\tdemo\tbuilding\n")
        self.assertEqual(self.proof(path), ("id-a", 100))
        # The values belong to the old owner, so a new name drops them.
        self.plans("set", "demo", "owner_session=other-2")
        self.assertEqual(self.proof(path), ("", ""))

    def test_handoff_clears_the_values_and_the_receiver_claim_writes_its_own(self):
        path = self.add_owned("demo", 10, "me-1", "id-a", 100)
        self.plans("handoff", "--to", "next-2", "demo", "--as", "me-1", env=SESSION_A)
        self.assertEqual(parse.load(path).keys["owner_session"], "next-2")
        self.assertEqual(self.proof(path), ("", ""))
        self.plans("claim", "demo", "--as", "next-2", env=SESSION_B)
        self.assertEqual(self.proof(path), ("id-b", 200))

    def test_the_session_values_are_not_settable(self):
        path = self.add("demo", 10)
        for pair in ("owner_session_id=x", "owner_session_pid=1"):
            with self.subTest(pair=pair):
                self.assertIn("cannot be set", self.plans("set", "demo", pair, code=2).stderr)
        self.assertNotIn("owner_session_id", self.read(path))

    def test_a_claim_after_a_stale_read_of_the_values_leaves_the_file(self):
        path = self.add_owned("demo", 10, "me-1", "id-a", 100)
        real_load = cli.load_doc
        raced = []

        def load_then_race(root, doc_id):
            doc = real_load(root, doc_id)
            # The owner refreshes its values between this read and the write.
            self.write(".plans/proj/demo.md", self.read(path).replace("owner_session_id: id-a", "owner_session_id: id-c"))
            raced.append(self.read(path))
            return doc

        with mock.patch.object(cli, "load_doc", load_then_race), mock.patch.object(cli.roots, "main_checkout", return_value=self.repo), \
                mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": "id-a", "CLAUDE_PID": "300"}):
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = cli.main(["claim", "demo", "--as", "me-1"])
        self.assertEqual(code, 3)
        self.assertIn("changed since it was read: owner_session_id", stderr.getvalue())
        self.assertEqual(self.read(path), raced[0])

    def test_new(self):
        self.add("old", 40)
        path = self.plans("new", "proj2", "fresh", "--kind", "bug").stdout.strip()
        self.assertEqual(path, os.path.join(self.repo, ".plans", "proj2", "fresh.md"))
        doc = parse.load(path)
        self.assertEqual({key: doc.keys[key] for key in ("id", "project", "kind", "status", "owner_session", "rank", "fix_rounds", "updated")},
                         {"id": "fresh", "project": "proj2", "kind": "bug", "status": "idea", "owner_session": "none",
                          "rank": 50, "fix_rounds": 0, "updated": TODAY})
        self.assertEqual(list(doc.keys), list(parse.KEY_ORDER))
        self.assertEqual(list(doc.sections()), list(parse.SECTIONS))
        self.assertEqual(self.plans("lint").stdout, "")
        before = self.read(path)
        self.plans("new", "proj2", "fresh", code=1)
        self.plans("new", "other", "fresh", code=1)
        self.assertEqual(self.read(path), before)
        self.plans("new", "Bad", "x", code=2)
        self.assertEqual(parse.load(self.plans("new", "proj2", "plain").stdout.strip()).keys["kind"], "feature")

    def test_new_in_an_empty_repo_starts_at_rank_10(self):
        path = self.plans("new", "proj", "first").stdout.strip()
        self.assertEqual(parse.load(path).keys["rank"], 10)

    def test_lint(self):
        self.add("good", 10)
        self.assertEqual(self.plans("lint").stdout, "")
        self.add("bad", 20, status="active", depends_on="[missing]")
        self.write(".planning/roadmap.md", "x\n")
        result = self.plans("lint", code=1)
        self.assertEqual(result.stdout.splitlines(), [
            ".: old-layout: .planning/roadmap.md; migrate this repo",
            ".plans/proj/bad.md:5: status: status 'active' is none of idea, planned, approved, building, review, blocked, parked, done",
            ".plans/proj/bad.md:8: depends-on: no doc 'missing'; drop it if that piece merged",
        ])

    def test_lint_gh(self):
        self.add("merged", 10, pr="5", issue="8", branch="here")
        self.add("open", 20, pr="\"#6\"", issue="7", branch="gone")
        self.add("unknown", 30, pr="9")
        bin_dir = os.path.join(self.temp.name, "bin")
        self.write("gh", FAKE_GH, repo=bin_dir)
        os.chmod(os.path.join(bin_dir, "gh"), 0o755)
        result = self.plans("lint", "--gh", env={"PATH": bin_dir + os.pathsep + os.environ["PATH"]}, code=1)
        self.assertEqual([line.split(": ", 2)[1] for line in result.stdout.splitlines()],
                         ["gh-pr", "gh-issue", "gh-branch", "gh-error"])
        self.assertIn("pr 5 is merged", result.stdout)
        self.assertEqual(self.plans("lint").stdout, "")

    def test_default_roots_without_a_roots_file(self):
        dev = os.path.join(self.temp.name, "dev")
        one = self.make_repo(os.path.join(dev, "group", "one"))
        self.add("in-one", 10, repo=one)
        self.add("in-dotfiles", 10)
        # The installer links ~/.local/share/dotfiles/repos to repos/ in the dotfiles checkout.
        os.makedirs(os.path.join(self.repo, "repos"))
        os.makedirs(os.path.join(self.home, ".local", "share", "dotfiles"))
        os.symlink(os.path.join(self.repo, "repos"), os.path.join(self.home, ".local", "share", "dotfiles", "repos"))
        lines = self.plans("ls", "--all", cwd=self.temp.name, env={"GITHUB_DIR": dev}).stdout.splitlines()
        self.assertEqual([line.split("\t")[:2] for line in lines], [["one", "in-one"], ["repo", "in-dotfiles"]])
        os.rename(dev, os.path.join(self.home, "Development"))
        lines = self.plans("ls", "--all", cwd=self.temp.name).stdout.splitlines()
        self.assertEqual([line.split("\t")[0] for line in lines], ["one", "repo"])
        self.write(".config/plans/roots", f"{self.repo}\n", repo=self.home)
        self.assertEqual([line.split("\t")[0] for line in self.plans("ls", "--all").stdout.splitlines()], ["repo"])

    def commit_all(self, repo):
        self.write("README", "x\n", repo=repo)
        subprocess.run(["git", "-C", repo, "add", "README"], check=True)
        subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "x"], check=True)

    def test_main_checkout_from_a_repo_a_worktree_and_a_submodule(self):
        self.commit_all(self.repo)
        worktree = os.path.join(self.temp.name, "wt")
        subprocess.run(["git", "-C", self.repo, "worktree", "add", "-q", worktree], check=True)
        library = self.make_repo(os.path.join(self.temp.name, "library"))
        self.commit_all(library)
        subprocess.run(["git", "-C", self.repo, "-c", "protocol.file.allow=always", "submodule", "add", "-q", library, "sub"],
                       check=True, capture_output=True)
        submodule = os.path.join(self.repo, "sub")
        self.assertEqual(cli.roots.main_checkout(self.repo), self.repo)
        self.assertEqual(cli.roots.main_checkout(worktree), self.repo)
        self.assertEqual(cli.roots.main_checkout(os.path.join(submodule)), submodule)
        self.add("in-sub", 10, repo=submodule)
        self.assertEqual(self.plans("ls", cwd=submodule).stdout.split("\t")[0], "in-sub")

    def test_questions_keep_continuation_lines(self):
        self.add("asks", 10, questions="- [ ] Which colour?\n  The bar or the frame.\n- [ ] Second?\n")
        self.assertEqual(self.plans("questions").stdout, "asks\tWhich colour? The bar or the frame.\nasks\tSecond?\n")
        data = json.loads(self.plans("questions", "--json").stdout)
        self.assertEqual(data[0]["question"], "Which colour? The bar or the frame.")

    def test_new_refuses_the_old_projects_folder(self):
        self.plans("new", "projects", "x", code=2)
        self.assertFalse(os.path.exists(os.path.join(self.repo, ".plans", "projects")))

    def test_an_empty_or_missing_owner_is_none(self):
        empty = self.add("empty", 10, owner='""')
        missing = self.write(".plans/proj/missing.md", doc_text("missing", 20).replace("owner_session: none\n", ""))
        self.assertEqual(self.plans("next", "--as", "me-1").stdout, "work\tempty\tplanned\n")
        self.plans("claim", "empty", "--as", "me-1")
        self.plans("claim", "missing", "--as", "me-1")
        self.assertEqual([parse.load(p).keys["owner_session"] for p in (empty, missing)], ["me-1", "me-1"])
        self.write(".plans/proj/empty.md", self.read(empty).replace("owner_session: me-1", 'owner_session: ""'))
        self.write(".plans/proj/missing.md", self.read(missing).replace("owner_session: me-1\n", ""))
        rules = [line.split(": ")[1] for line in self.plans("lint", code=1).stdout.splitlines()]
        self.assertEqual(rules, ["owner-session", "missing-key"])

    def test_a_doc_deleted_after_the_read_is_one_line(self):
        path = self.add("demo", 10)
        real_load = cli.load_doc

        def load_then_delete(root, doc_id):
            doc = real_load(root, doc_id)
            os.unlink(path)
            return doc

        with mock.patch.object(cli, "load_doc", load_then_delete), mock.patch.object(cli.roots, "main_checkout", return_value=self.repo):
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = cli.main(["set", "demo", "status=building"])
        self.assertEqual(code, 1)
        self.assertEqual(len(stderr.getvalue().splitlines()), 1, stderr.getvalue())
        self.assertIn("deleted since it was read", stderr.getvalue())

    def test_lint_flags_a_waiting_on_that_is_no_string(self):
        self.add("demo", 10, waiting_on="[]")
        self.assertEqual(self.plans("lint", code=1).stdout,
                         ".plans/proj/demo.md:9: waiting-on: waiting_on must be a string, \"\" when the doc waits on nothing\n")

    def test_an_unreadable_dependency_blocks(self):
        self.write(".plans/proj/broken.md", "no front matter\n")
        self.add("needs", 10, depends_on="[broken]")
        self.add("later", 20)
        self.assertEqual(self.plans("next").stdout, "blocked\tneeds\tblocked by broken (unreadable)\nwork\tlater\tplanned\n")

    def unreadable_docs(self, repo=None):
        """A mode 000 doc and a non-UTF-8 doc among good ones. Returns the ids that read as unreadable."""
        repo = repo or self.repo
        self.add("good-a", 10, repo=repo)
        self.add("good-b", 30, repo=repo)
        bad = self.write(".plans/proj/bad-utf.md", "", repo)
        with open(bad, "wb") as handle:
            handle.write(b"---\nid: bad-utf\n---\n\xff\xfe\n")
        if os.geteuid() == 0:
            return ["bad-utf"]
        locked = self.add("locked", 20, repo=repo)
        os.chmod(locked, 0)
        return ["bad-utf", "locked"]

    def test_ls_lists_the_good_docs_and_warns_about_unreadable_ones(self):
        bad = self.unreadable_docs()
        result = self.plans("ls")
        self.assertEqual([line.split("\t")[0] for line in result.stdout.splitlines()], ["good-a", "good-b"])
        self.assertIn("bad-utf.md: cannot be read: not UTF-8", result.stderr)
        if "locked" in bad:
            self.assertIn("locked.md: cannot be read: Permission denied", result.stderr)

    def test_ls_all_lists_every_other_doc_and_repo(self):
        self.unreadable_docs()
        other = self.make_repo(os.path.join(self.temp.name, "other"))
        self.add("elsewhere", 10, repo=other)
        self.write(".config/plans/roots", f"{self.repo}\n{other}\n", repo=self.home)
        result = self.plans("ls", "--all", cwd=self.temp.name)
        self.assertEqual([line.split("\t")[:2] for line in result.stdout.splitlines()],
                         [["repo", "good-a"], ["repo", "good-b"], ["other", "elsewhere"]])
        self.assertIn("cannot be read", result.stderr)

    def test_next_skips_the_unreadable_docs(self):
        self.unreadable_docs()
        result = self.plans("next")
        self.assertEqual(result.stdout, "work\tgood-a\tplanned\n")
        self.assertIn("bad-utf.md: cannot be read: not UTF-8", result.stderr)

    def test_a_dangling_symlink_doc_is_unreadable_and_the_rest_read(self):
        self.add("good-a", 10)
        link = os.path.join(self.repo, ".plans", "proj", "dangling.md")
        os.symlink(os.path.join(self.temp.name, "missing.md"), link)
        result = self.plans("next")
        self.assertEqual(result.stdout, "work\tgood-a\tplanned\n")
        self.assertIn("dangling.md: cannot be read", result.stderr)
        self.assertEqual(self.plans("ls").stdout.split("\t")[0], "good-a")

    def test_lint_reports_the_unreadable_docs(self):
        self.unreadable_docs()
        result = self.plans("lint", code=1)
        self.assertIn("bad-utf.md:1:", result.stdout)

    def test_new_checks_the_id_again_under_the_lock(self):
        self.add("taken", 10, project="first")
        real_find = cli.query.find
        calls = []

        def find_late(root, doc_id):
            # The early check runs before another `plans new` writes the same id.
            calls.append(doc_id)
            return [] if len(calls) == 1 else real_find(root, doc_id)

        with mock.patch.object(cli.query, "find", find_late), mock.patch.object(cli.roots, "main_checkout", return_value=self.repo):
            stderr = io.StringIO()
            with redirect_stderr(stderr), redirect_stdout(io.StringIO()):
                code = cli.main(["new", "second", "taken"])
        self.assertEqual(code, 1, stderr.getvalue())
        self.assertFalse(os.path.exists(os.path.join(self.repo, ".plans", "second", "taken.md")))

    def test_gh_timeout_is_a_gh_error(self):
        self.add("slow", 10, pr="5")
        bin_dir = os.path.join(self.temp.name, "bin")
        self.write("gh", "#!/bin/sh\nexec sleep 5\n", repo=bin_dir)
        os.chmod(os.path.join(bin_dir, "gh"), 0o755)
        doc = parse.load(os.path.join(self.repo, ".plans/proj/slow.md"))
        with mock.patch.dict(os.environ, {"PATH": bin_dir + os.pathsep + os.environ["PATH"]}), mock.patch.object(cli.gh, "TIMEOUT_SECONDS", 0.2):
            findings = cli.gh.check(self.repo, [doc])
        self.assertEqual([(f.rule, f.message) for f in findings], [("gh-error", "could not read pr 5: gh timed out after 0.2 s")])

    def test_find_by_glob(self):
        self.add("demo", 10, project="a")
        self.assertEqual(query.find(self.repo, "demo"), [os.path.join(self.repo, ".plans", "a", "demo.md")])


if __name__ == "__main__":
    unittest.main()
