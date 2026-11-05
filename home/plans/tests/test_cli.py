"""Each command end to end: the entry point run as a process on temp git repos, with a stub gh for lint --gh."""

import datetime
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

from contextlib import redirect_stderr
from unittest import mock

sys.dont_write_bytecode = True
PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(PACKAGE, ".local", "lib", "plans"))
from plans import cli, parse, query  # noqa: E402

ENTRY = os.path.join(PACKAGE, ".local", "bin", "plans")
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


class CliTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = os.path.join(self.temp.name, "home")
        self.repo = self.make_repo(os.path.join(self.temp.name, "repo"))
        self.env = {**os.environ, "HOME": self.home, "XDG_CONFIG_HOME": os.path.join(self.home, ".config")}
        self.env.pop("PLANS_SESSION", None)

    def tearDown(self):
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
        result = subprocess.run([sys.executable, ENTRY, *args], cwd=cwd or self.repo, env={**self.env, **(env or {})},
                                capture_output=True, text=True)
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

    def test_set_refuses_bad_values(self):
        path = self.add("demo", 10)
        before = self.read(path)
        for pair in ("status=active", "kind=plan", "rank=high", "owner_session=Bob", "id=x", "updated=x", "colour=x", "nopair"):
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

    def test_new(self):
        self.add("old", 40)
        path = self.plans("new", "proj2", "fresh", "--kind", "bug").stdout.strip()
        self.assertEqual(path, os.path.join(self.repo, ".plans", "proj2", "fresh.md"))
        doc = parse.load(path)
        self.assertEqual({key: doc.keys[key] for key in ("id", "project", "kind", "status", "owner_session", "rank", "updated")},
                         {"id": "fresh", "project": "proj2", "kind": "bug", "status": "idea", "owner_session": "none",
                          "rank": 50, "updated": TODAY})
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

    def test_find_by_glob(self):
        self.add("demo", 10, project="a")
        self.assertEqual(query.find(self.repo, "demo"), [os.path.join(self.repo, ".plans", "a", "demo.md")])


if __name__ == "__main__":
    unittest.main()
