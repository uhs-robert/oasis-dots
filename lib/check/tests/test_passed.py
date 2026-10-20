"""Tests lib/check/passed.py in scratch repositories that have their own common dir, so the real records are never
touched, and its byte compatibility with the shell version it replaces (passed.sh.frozen, a copy of lib/check/passed.sh
as of the port: extracting it from origin/main would break once the shim lands there)."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, CHECK_DIR)
import passed  # noqa: E402

NEW_CLI = os.path.join(CHECK_DIR, "passed.sh")
OLD_CLI = os.path.join(CHECK_DIR, "tests", "passed.sh.frozen")
GIT_ENV = {
    **{k: v for k, v in os.environ.items() if not k.startswith("GIT_")},
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.invalid",
    "PYTHONDONTWRITEBYTECODE": "1",
}
USAGE = (
    "usage: lib/check/passed.sh record | record-changed <base> | is-passed [rev] | passed-somewhere [rev] | "
    "passed-since <base> [rev] | step-record <step> <key> | step-is-passed <step> <key>\n"
)
DIRTY = "check-passed: uncommitted tracked changes, so the pass is not HEAD's tree\n"
QUERIES = (
    ("is-passed",),
    ("is-passed", "HEAD~1"),
    ("passed-somewhere",),
    ("passed-somewhere", "HEAD~1"),
    ("passed-since", "HEAD~1"),
    ("passed-since", "HEAD~2", "HEAD"),
    ("passed-since", "HEAD~1", "HEAD~1"),
    ("step-is-passed", "lint", "k1"),
    ("step-is-passed", "lint", "k2"),
)


def run_git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, env=GIT_ENV, check=True, capture_output=True, text=True).stdout.strip()


class ScratchRepo(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, True)
        self.repo = os.path.join(self.root, "repo")
        os.mkdir(self.repo)
        run_git(self.repo, "init", "-q")
        for number in range(3):
            self.commit_file(f"f{number}")
        self.common = os.path.join(self.repo, ".git")
        self.trees = os.path.join(self.common, "claude-check-passed-trees")
        self.steps = os.path.join(self.common, "claude-check-passed-steps")

    def commit_file(self, name):
        with open(os.path.join(self.repo, name), "w") as handle:
            handle.write(name)
        run_git(self.repo, "add", name)
        run_git(self.repo, "commit", "-q", "-m", name)

    def tree(self, rev="HEAD"):
        return run_git(self.repo, "rev-parse", rev + "^{tree}")

    def cli(self, script, *args, cwd=None):
        return subprocess.run(
            ["sh", script, *args], cwd=cwd or self.repo, env=GIT_ENV, capture_output=True, text=True, check=False
        )

    def read(self, path):
        with open(path) as handle:
            return handle.read()

    def make_repos_dir(self):
        os.makedirs(os.path.join(self.repo, "repos", "clone"))


class CliTests(ScratchRepo):
    def test_record_then_is_passed(self):
        self.assertEqual(self.cli(NEW_CLI, "is-passed").returncode, 1)
        self.assertEqual(self.cli(NEW_CLI, "record").returncode, 0)
        self.assertEqual(self.read(self.trees), f"{self.tree()} no-repos\n")
        self.assertEqual(self.cli(NEW_CLI, "is-passed").returncode, 0)
        self.assertEqual(self.cli(NEW_CLI, "is-passed", "HEAD~1").returncode, 1)

    def test_record_dedupes_and_last_wins(self):
        self.cli(NEW_CLI, "record")
        self.cli(NEW_CLI, "record-changed", "HEAD~1")
        self.cli(NEW_CLI, "record")
        lines = self.read(self.trees).splitlines()
        self.assertEqual(lines, [f"{self.tree()} changed-since {self.tree('HEAD~1')}", f"{self.tree()} no-repos"])

    def test_entry_cap(self):
        with open(self.trees, "w") as handle:
            handle.writelines(f"{number:040x} no-repos\n" for number in range(250))
        self.cli(NEW_CLI, "record")
        lines = self.read(self.trees).splitlines()
        self.assertEqual(len(lines), 200)
        self.assertEqual(lines[-1], f"{self.tree()} no-repos")
        self.assertEqual(lines[0], f"{51:040x} no-repos")

    def test_step_trim(self):
        with open(self.steps, "w") as handle:
            handle.writelines(f"s k{number}\n" for number in range(2000))
        self.cli(NEW_CLI, "step-record", "s", "k2000")
        lines = self.read(self.steps).splitlines()
        self.assertEqual(len(lines), 1000)
        self.assertEqual(lines[0], "s k1001")
        self.assertEqual(lines[-1], "s k2000")

    def test_step_no_trim_at_limit(self):
        with open(self.steps, "w") as handle:
            handle.writelines(f"s k{number}\n" for number in range(1999))
        self.cli(NEW_CLI, "step-record", "s", "last")
        self.assertEqual(len(self.read(self.steps).splitlines()), 2000)

    def test_step_is_passed(self):
        self.assertEqual(self.cli(NEW_CLI, "step-is-passed", "lint", "k1").returncode, 1)
        self.cli(NEW_CLI, "step-record", "lint", "k1")
        self.assertEqual(self.cli(NEW_CLI, "step-is-passed", "lint", "k1").returncode, 0)
        self.assertEqual(self.cli(NEW_CLI, "step-is-passed", "lint", "k").returncode, 1)
        self.assertEqual(self.cli(NEW_CLI, "step-is-passed", "lin", "tk1").returncode, 1)

    def test_coverage_rules(self):
        with open(self.trees, "w") as handle:
            handle.write(f"{self.tree()} no-repos\n")
        self.assertEqual(self.cli(NEW_CLI, "is-passed").returncode, 0)
        self.make_repos_dir()
        self.assertEqual(self.cli(NEW_CLI, "is-passed").returncode, 1)
        self.assertEqual(self.cli(NEW_CLI, "passed-somewhere").returncode, 0)
        with open(self.trees, "w") as handle:
            handle.write(f"{self.tree()} with-repos\n")
        self.assertEqual(self.cli(NEW_CLI, "is-passed").returncode, 0)
        shutil.rmtree(os.path.join(self.repo, "repos"))
        self.assertEqual(self.cli(NEW_CLI, "is-passed").returncode, 0)

    def test_record_uses_repos_coverage(self):
        self.make_repos_dir()
        self.cli(NEW_CLI, "record")
        self.assertEqual(self.read(self.trees), f"{self.tree()} with-repos\n")

    def test_empty_repos_dir_is_no_repos(self):
        os.mkdir(os.path.join(self.repo, "repos"))
        self.cli(NEW_CLI, "record")
        self.assertEqual(self.read(self.trees), f"{self.tree()} no-repos\n")

    def test_passed_since(self):
        self.assertEqual(self.cli(NEW_CLI, "passed-since", "HEAD~1").returncode, 1)
        self.cli(NEW_CLI, "record-changed", "HEAD~1")
        self.assertEqual(self.cli(NEW_CLI, "passed-since", "HEAD~1").returncode, 0)
        self.assertEqual(self.cli(NEW_CLI, "passed-since", "HEAD~2").returncode, 1)
        self.assertEqual(self.cli(NEW_CLI, "passed-somewhere").returncode, 1)

    def test_dirty_tree_refusals(self):
        with open(os.path.join(self.repo, "f0"), "w") as handle:
            handle.write("changed")
        for args in (("record",), ("record-changed", "HEAD~1")):
            result = self.cli(NEW_CLI, *args)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (1, "", DIRTY))
        self.assertFalse(os.path.exists(self.trees))
        with open(self.trees, "w") as handle:
            handle.write(f"{self.tree()} no-repos\n")
        self.assertEqual(self.cli(NEW_CLI, "is-passed").returncode, 1)
        self.assertEqual(self.cli(NEW_CLI, "is-passed", "HEAD").returncode, 1)
        self.assertEqual(self.cli(NEW_CLI, "is-passed", "HEAD~0").returncode, 0)

    def test_untracked_files_do_not_dirty(self):
        with open(os.path.join(self.repo, "new"), "w") as handle:
            handle.write("x")
        self.assertEqual(self.cli(NEW_CLI, "record").returncode, 0)

    def test_usage(self):
        for args in ((), ("bogus",), ("passed-since",), ("record-changed",), ("step-record", "a"), ("step-is-passed", "a")):
            result = self.cli(NEW_CLI, *args)
            self.assertEqual(result.returncode, 2, args)
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, USAGE if args in ((), ("bogus",)) else "", args)

    def test_unknown_rev_fails(self):
        self.assertEqual(self.cli(NEW_CLI, "passed-somewhere", "nope").returncode, 1)

    def test_runs_from_subdirectory(self):
        os.mkdir(os.path.join(self.repo, "sub"))
        self.assertEqual(self.cli(NEW_CLI, "record", cwd=os.path.join(self.repo, "sub")).returncode, 0)
        self.assertTrue(os.path.exists(self.trees))

    def test_worktree_shares_common_dir(self):
        other = os.path.join(self.root, "wt")
        run_git(self.repo, "worktree", "add", "-q", "--detach", other)
        self.assertEqual(self.cli(NEW_CLI, "record", cwd=other).returncode, 0)
        self.assertEqual(self.cli(NEW_CLI, "is-passed").returncode, 0)
        self.assertTrue(os.path.exists(self.trees))

    def test_no_bytecode_left_behind(self):
        # Compares against a snapshot because a stray .pyc from an unrelated import must not fail this test.
        cache = os.path.join(CHECK_DIR, "__pycache__")

        def cache_entries():
            return set(os.listdir(cache)) if os.path.isdir(cache) else set()

        before = cache_entries()
        self.cli(NEW_CLI, "record")
        self.assertEqual(cache_entries() - before, set())

    def test_concurrent_step_records_keep_every_line(self):
        os.chdir(self.repo)
        self.addCleanup(os.chdir, CHECK_DIR)
        writers = [
            subprocess.Popen([sys.executable, "-B", os.path.join(CHECK_DIR, "passed.py"), "step-record", "s", f"k{n}"], env=GIT_ENV)
            for n in range(20)
        ]
        for writer in writers:
            writer.wait()
        self.assertEqual(sorted(self.read(self.steps).splitlines()), sorted(f"s k{n}" for n in range(20)))


class ImportTests(ScratchRepo):
    def test_functions_work_on_cwd_repo(self):
        os.chdir(self.repo)
        self.addCleanup(os.chdir, CHECK_DIR)
        self.assertFalse(passed.step_is_passed("lint", "k1"))
        passed.step_record("lint", "k1")
        self.assertTrue(passed.step_is_passed("lint", "k1"))
        passed.record()
        self.assertTrue(passed.is_passed())
        self.assertTrue(passed.passed_somewhere("HEAD"))

    def test_main_returns_status(self):
        os.chdir(self.repo)
        self.addCleanup(os.chdir, CHECK_DIR)
        self.assertEqual(passed.main(["is-passed"]), 1)
        self.assertEqual(passed.main(["record"]), 0)
        self.assertEqual(passed.main(["is-passed"]), 0)


class CrossCompatibility(ScratchRepo):
    """Old and new code share the record files on old branches, so each must accept what the other wrote."""

    def populate(self, script, extra_coverage=False):
        if extra_coverage:
            self.make_repos_dir()
        for args in (
            ("record",),
            ("record-changed", "HEAD~1"),
            ("step-record", "lint", "k1"),
            ("step-record", "lint", "k1"),
            ("step-record", "other", "k2"),
            ("record",),
        ):
            self.assertEqual(self.cli(script, *args).returncode, 0, args)

    def query_results(self):
        return [(args, self.cli(script, *args).returncode) for args in QUERIES for script in (OLD_CLI, NEW_CLI)]

    def assert_both_agree(self):
        results = self.query_results()
        for index in range(0, len(results), 2):
            self.assertEqual(results[index][1], results[index + 1][1], results[index][0])
        return [code for _, code in results[::2]]

    def test_new_records_old_queries(self):
        self.populate(NEW_CLI)
        codes = self.assert_both_agree()
        self.assertIn(0, codes)
        self.assertEqual(self.cli(OLD_CLI, "is-passed").returncode, 0)
        self.assertEqual(self.cli(OLD_CLI, "step-is-passed", "lint", "k1").returncode, 0)

    def test_old_records_new_queries(self):
        self.populate(OLD_CLI)
        codes = self.assert_both_agree()
        self.assertIn(0, codes)
        self.assertEqual(self.cli(NEW_CLI, "is-passed").returncode, 0)
        self.assertEqual(self.cli(NEW_CLI, "step-is-passed", "other", "k2").returncode, 0)

    def test_queries_agree_with_repos_dir(self):
        self.populate(OLD_CLI, extra_coverage=True)
        self.assert_both_agree()

    def test_interleaved_writers(self):
        for index, script in enumerate((OLD_CLI, NEW_CLI, OLD_CLI, NEW_CLI)):
            self.cli(script, "step-record", "s", f"k{index}")
            self.cli(script, "record-changed", f"HEAD~{index % 3}")
        self.assert_both_agree()

    def test_record_files_are_byte_identical(self):
        outputs = {}
        for name, script in (("old", OLD_CLI), ("new", NEW_CLI)):
            for path in (self.trees, self.steps):
                if os.path.exists(path):
                    os.remove(path)
            with open(self.trees, "w") as handle:
                handle.writelines(f"{number:040x} no-repos\n" for number in range(198))
            with open(self.steps, "w") as handle:
                handle.writelines(f"s k{number}\n" for number in range(1999))
            self.populate(script)
            for number in range(3):
                self.cli(script, "step-record", "s", f"extra{number}")
            self.cli(script, "record-changed", "HEAD~2")
            self.cli(script, "record-changed", "HEAD~1")
            with open(self.trees, "rb") as trees, open(self.steps, "rb") as steps:
                outputs[name] = (trees.read(), steps.read())
        self.assertEqual(outputs["old"], outputs["new"])
        self.assertEqual(len(outputs["new"][0].splitlines()), 200)

    def test_error_outputs_are_identical(self):
        with open(os.path.join(self.repo, "f0"), "w") as handle:
            handle.write("changed")
        for args in (("record",), ("record-changed", "HEAD~1"), ("bogus",), (), ("passed-since",), ("is-passed",)):
            old, new = (self.cli(script, *args) for script in (OLD_CLI, NEW_CLI))
            self.assertEqual((old.returncode, old.stdout, old.stderr), (new.returncode, new.stdout, new.stderr), args)


if __name__ == "__main__":
    unittest.main()
