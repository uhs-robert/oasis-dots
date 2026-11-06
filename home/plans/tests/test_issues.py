"""The issue check of `next`: the ranking rule, the closed-rank lines, the cache and every gh failure."""

import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(PACKAGE, ".local", "lib", "plans"))
from plans import issues, parse  # noqa: E402

ENTRY = os.path.join(PACKAGE, ".local", "bin", "plans")
SLUG = "own/repo"
# Answers from $FAKE_GH_DATA, one line per call appended to $FAKE_GH_LOG. $FAKE_GH_MODE fails or hangs it.
FAKE_GH = """#!/usr/bin/env python3
import json, os, re, sys, time
args = sys.argv[1:]
with open(os.environ["FAKE_GH_LOG"], "a") as log:
    log.write(" ".join(args[:2]) + "\\n")
mode = os.environ.get("FAKE_GH_MODE", "")
if mode == "fail":
    sys.exit("gh: network down")
if mode == "hang":
    time.sleep(30)
data = json.load(open(os.environ["FAKE_GH_DATA"]))
if args[:2] == ["issue", "list"]:
    print(json.dumps([{"number": int(n), "title": t} for n, t in data["open"].items()]))
elif args[:2] == ["api", "graphql"]:
    query = next(a for a in args if a.startswith("query="))
    numbers = [int(n) for n in re.findall(r"n(\\d+): issueOrPullRequest", query)]
    nodes, missing = {}, False
    for n in numbers:
        kind = data["others"].get(str(n))
        if kind is None:
            nodes[f"n{n}"], missing = None, True
        else:
            nodes[f"n{n}"] = {"__typename": "PullRequest"} if kind == "PR" else {"__typename": "Issue", "state": kind}
    print(json.dumps({"data": {"repository": nodes}}))
    if missing:
        sys.exit("gh: Could not resolve to an issue or pull request")
"""


def doc_text(doc_id, rank, issue="none", plan="", decisions=""):
    return (f"---\nid: {doc_id}\nproject: proj\nkind: feature\nstatus: planned\nowner_session: none\nrank: {rank}\n"
            f"depends_on: []\nwaiting_on: \"\"\nissue: {issue}\npr: none\nbranch: none\nupdated: \"2026-11-01\"\n---\n"
            f"# {doc_id}\n\n## Goal\n\n## Decisions\n\n{decisions}\n## Plan\n\n{plan}\n## Open questions\n\n"
            "## Owner checks\n")


def doc(doc_id, rank=10, **keys):
    return parse.Doc(f"/r/.plans/proj/{doc_id}.md", doc_text(doc_id, rank, **keys))


class RankingRuleTest(unittest.TestCase):
    def numbers(self, *docs):
        return {number: found.id for number, found in issues.ranked_numbers(docs, SLUG).items()}

    def test_the_issue_key_ranks_in_every_form(self):
        self.assertEqual(self.numbers(doc("a", issue="12"), doc("b", issue='"#13"'),
                                      doc("c", issue="https://github.com/own/repo/issues/14")), {12: "a", 13: "b", 14: "c"})

    def test_an_issue_url_of_another_repo_does_not_rank(self):
        self.assertEqual(self.numbers(doc("a", issue="https://github.com/other/repo/issues/14")), {})

    def test_the_plan_section_ranks_and_history_does_not(self):
        found = doc("a", plan="- #20 First\n- #21 Second, after #22 lands\n", decisions="- #30 merged as PR #31\n")
        self.assertEqual(self.numbers(found), {20: "a", 21: "a", 22: "a"})

    def test_cross_repo_and_glued_numbers_do_not_rank(self):
        self.assertEqual(self.numbers(doc("a", plan="See other/repo#40, PR#41, x#42 and #43.\n")), {43: "a"})

    def test_the_lowest_ranked_doc_holds_the_number(self):
        self.assertEqual(self.numbers(doc("late", 50, plan="#7\n"), doc("early", 10, issue="7")), {7: "early"})


class SlugTest(unittest.TestCase):
    def test_remote_forms(self):
        for url in ("git@github.com:own/repo.git", "https://github.com/own/repo", "ssh://git@github.com/own/repo.git"):
            self.assertEqual(issues.REMOTE_URL.fullmatch(url).group(1), SLUG, url)
        self.assertIsNone(issues.REMOTE_URL.fullmatch("git@gitlab.com:own/repo.git"))


class NextTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.temp = temp.name
        self.repo = os.path.join(self.temp, "repo")
        subprocess.run(["git", "init", "-q", "-b", "main", self.repo], check=True)
        subprocess.run(["git", "-C", self.repo, "remote", "add", "origin", f"git@github.com:{SLUG}.git"], check=True)
        bin_dir = os.path.join(self.temp, "bin")
        os.makedirs(bin_dir)
        self.write(os.path.join(bin_dir, "gh"), FAKE_GH)
        os.chmod(os.path.join(bin_dir, "gh"), 0o755)
        self.log = os.path.join(self.temp, "gh.log")
        self.data = os.path.join(self.temp, "gh.json")
        self.cache = os.path.join(self.temp, "cache")
        self.env = {**os.environ, "PATH": bin_dir + os.pathsep + os.environ["PATH"], "HOME": self.temp,
                    "XDG_CACHE_HOME": self.cache, "FAKE_GH_LOG": self.log, "FAKE_GH_DATA": self.data}
        for name in ("PLANS_SESSION", "CLAUDE_CODE_SESSION_ID", "CLAUDE_PID", "FAKE_GH_MODE"):
            self.env.pop(name, None)
        self.github(open_issues={"5": "Open and ranked", "6": "Open and unranked", "9": "Open and unranked too"},
                    others={"7": "CLOSED", "8": "PR"})
        self.add("work", 10, issue="5", plan="- #7 closed one\n- #8 a PR\n- #99 not there\n")

    def write(self, path, text):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def add(self, doc_id, rank, **keys):
        self.write(os.path.join(self.repo, ".plans", "proj", f"{doc_id}.md"), doc_text(doc_id, rank, **keys))

    def github(self, open_issues, others):
        self.write(self.data, json.dumps({"open": open_issues, "others": others}))

    def plans(self, *args, mode=None):
        env = {**self.env, **({"FAKE_GH_MODE": mode} if mode else {})}
        result = subprocess.run([sys.executable, ENTRY, "next", *args], cwd=self.repo, env=env, capture_output=True,
                                text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def gh_calls(self):
        if not os.path.exists(self.log):
            return 0
        with open(self.log) as handle:
            return len(handle.read().splitlines())

    def age_cache(self):
        path = os.path.join(self.cache, "plans", "own", "repo.json")
        with open(path) as handle:
            data = json.load(handle)
        data["fetched_at"] -= issues.CACHE_SECONDS + 1
        self.write(path, json.dumps(data))

    EXPECTED = ("ask\t#6\trank: Open and unranked\nask\t#9\trank: Open and unranked too\n"
                "ask\t#7\tclosed: drop it from work\nwork\twork\tplanned\n")

    def test_unranked_and_closed_lines_come_before_the_doc_lines(self):
        self.assertEqual(self.plans(), self.EXPECTED)

    def test_json(self):
        rows = json.loads(self.plans("--json"))
        self.assertEqual([(row["id"], row.get("issue")) for row in rows], [("#6", 6), ("#9", 9), ("#7", 7), ("work", None)])
        self.assertIsNone(rows[0]["path"])
        self.assertTrue(rows[2]["path"].endswith("work.md"))

    def test_a_fresh_cache_skips_gh(self):
        self.plans()
        calls = self.gh_calls()
        self.assertEqual(self.plans(), self.EXPECTED)
        self.assertEqual(self.gh_calls(), calls)

    def test_a_new_ranked_number_refreshes_a_fresh_cache(self):
        self.plans()
        calls = self.gh_calls()
        self.add("later", 20, plan="- #6 now ranked\n- #50 new\n")
        self.github(open_issues={"5": "a", "6": "b", "9": "c"}, others={"7": "CLOSED", "8": "PR", "50": "CLOSED"})
        self.assertIn("ask\t#50\tclosed: drop it from later\n", self.plans())
        self.assertGreater(self.gh_calls(), calls)

    def test_an_old_cache_is_fetched_again(self):
        self.plans()
        self.age_cache()
        self.github(open_issues={"5": "a"}, others={"7": "OPEN", "8": "PR"})
        self.assertEqual(self.plans(), "work\twork\tplanned\n")

    def test_gh_failing_uses_the_old_cache(self):
        self.plans()
        self.age_cache()
        self.assertEqual(self.plans(mode="fail"), self.EXPECTED)

    def test_gh_failing_without_a_cache_prints_only_the_doc_lines(self):
        self.assertEqual(self.plans(mode="fail"), "work\twork\tplanned\n")

    def test_a_failure_waits_before_the_next_try(self):
        self.plans(mode="fail")
        calls = self.gh_calls()
        self.assertEqual(self.plans(), "work\twork\tplanned\n")
        self.assertEqual(self.gh_calls(), calls)
        path = os.path.join(self.cache, "plans", "own", "repo.json")
        with open(path) as handle:
            data = json.load(handle)
        data["failed_at"] -= issues.RETRY_SECONDS + 1
        self.write(path, json.dumps(data))
        self.assertEqual(self.plans(), self.EXPECTED)

    def test_a_bad_cache_is_a_miss(self):
        path = os.path.join(self.cache, "plans", "own", "repo.json")
        for bad in ({"version": 1, "failed_at": "bad"}, {"version": 1, "fetched_at": 1e12, "open": [], "states": {}},
                    {"version": 1, "fetched_at": 1e12, "open": {"x": "t"}, "states": {}}, ["not a dict"]):
            self.write(path, json.dumps(bad))
            self.assertEqual(self.plans(), self.EXPECTED, bad)

    def test_the_cache_is_owner_only_and_keyed_by_owner_and_repo(self):
        self.plans()
        path = os.path.join(self.cache, "plans", "own", "repo.json")
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(os.path.dirname(path)).st_mode & 0o777, 0o700)
        self.assertNotEqual(issues.cache_path("a-b/c"), issues.cache_path("a/b-c"))

    def test_gh_hanging_times_out(self):
        self.assertEqual(self.plans(mode="hang"), "work\twork\tplanned\n")

    def test_gh_missing(self):
        # Only git on PATH: the system gh sits beside git in /usr/bin.
        only_git = os.path.join(self.temp, "only-git")
        os.makedirs(only_git)
        os.symlink(subprocess.run(["which", "git"], capture_output=True, text=True).stdout.strip(), os.path.join(only_git, "git"))
        self.env["PATH"] = only_git
        self.assertEqual(self.plans(), "work\twork\tplanned\n")

    def test_no_github_origin_makes_no_call(self):
        subprocess.run(["git", "-C", self.repo, "remote", "set-url", "origin", "git@gitlab.com:own/repo.git"], check=True)
        self.assertEqual(self.plans(), "work\twork\tplanned\n")
        self.assertEqual(self.gh_calls(), 0)


if __name__ == "__main__":
    unittest.main()
