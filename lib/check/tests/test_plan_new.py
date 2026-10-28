"""Tests the .plans scaffold (lib/plan_new.py): each kind yields a doc the specs step's --file mode accepts."""

import contextlib
import io
import os
import shutil
import subprocess
import sys
import unittest
from unittest import mock

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_DIR = os.path.dirname(os.path.dirname(CHECK_DIR))
sys.path.insert(0, os.path.join(REPO_DIR, "lib"))
sys.path.insert(0, os.path.join(CHECK_DIR, "tests"))
import plan_new  # noqa: E402
from test_qml import TreeCase  # noqa: E402


def accepted(path):
    return subprocess.run([sys.executable, "-B", os.path.join(REPO_DIR, "lib/check/steps/specs.py"), "--file", path],
                          capture_output=True, text=True)


@unittest.skipUnless(shutil.which("check-jsonschema"), "needs check-jsonschema")
class ScaffoldTest(TreeCase):
    def test_each_kind_passes_the_file_check_at_its_path(self):
        for kind, item, name in (("tracker", None, "foo/foo.md"), ("plan", "bar", "foo/foo-bar-plan-draft.md"), ("handoff", None, "foo/foo-handoff.md")):
            path = plan_new.scaffold(self.root, "foo", kind, item, today="2026-10-27")
            self.assertEqual(path, os.path.join(self.root, ".plans", name))
            done = accepted(path)
            self.assertEqual((done.returncode, done.stderr), (0, ""), kind)

    def read(self, path):
        with open(path) as handle:
            return handle.read()

    def test_a_tracker_has_no_branch_and_a_plan_does(self):
        tracker = self.read(plan_new.scaffold(self.root, "foo", "tracker"))
        plan = self.read(plan_new.scaffold(self.root, "foo", "plan", "x"))
        self.assertNotIn("branch:", tracker)
        self.assertIn("branch: none", plan)

    def test_it_refuses_to_overwrite(self):
        path = plan_new.scaffold(self.root, "foo", "tracker")
        with self.assertRaisesRegex(ValueError, "exists"):
            plan_new.scaffold(self.root, "foo", "tracker")
        self.assertTrue(os.path.isfile(path))

    def test_a_bad_kind_lists_the_kinds(self):
        with self.assertRaisesRegex(ValueError, "tracker, plan, handoff"):
            plan_new.scaffold(self.root, "foo", "note")

    def test_a_plan_needs_an_item_and_others_refuse_one(self):
        with self.assertRaisesRegex(ValueError, "item"):
            plan_new.scaffold(self.root, "foo", "plan")
        with self.assertRaisesRegex(ValueError, "no item"):
            plan_new.scaffold(self.root, "foo", "tracker", "x")

    def test_a_handoff_with_an_item_gets_the_draft_name_and_validates(self):
        path = plan_new.scaffold(self.root, "foo", "handoff", "bar")
        self.assertEqual(path, os.path.join(self.root, ".plans/foo/foo-bar-handoff-draft.md"))
        self.assertEqual(accepted(path).returncode, 0)

    def test_the_script_without_the_tool_prints_the_path_and_a_hint_and_exits_zero(self):
        with mock.patch.object(plan_new.shutil, "which", return_value=None), \
                mock.patch.object(plan_new, "main_checkout", return_value=self.root), \
                contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(plan_new.main(["foo", "tracker"]), 0)
        self.assertIn("foo.md", out.getvalue())
        self.assertIn("check-jsonschema", err.getvalue())

    def test_just_does_not_run_a_topic_as_shell(self):
        marker = os.path.join(self.root, "pwned")
        done = subprocess.run(["just", "--justfile", os.path.join(REPO_DIR, "justfile"), "--working-directory", REPO_DIR,
                               "plan-new", f"x;touch {marker}", "tracker"], capture_output=True, text=True)
        self.assertNotEqual(done.returncode, 0)
        self.assertFalse(os.path.exists(marker))
        self.assertIn("topic", done.stderr)

    def test_a_bad_topic_is_refused(self):
        with self.assertRaisesRegex(ValueError, "topic"):
            plan_new.scaffold(self.root, "../foo", "tracker")


if __name__ == "__main__":
    unittest.main()
