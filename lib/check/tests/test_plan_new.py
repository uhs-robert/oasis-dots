"""Tests the .plans scaffold (lib/plan_new.py): each kind yields a doc the specs step's --file mode accepts."""

import os
import shutil
import subprocess
import sys
import unittest

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
        with self.assertRaisesRegex(ValueError, "plan only"):
            plan_new.scaffold(self.root, "foo", "tracker", "x")

    def test_a_bad_topic_is_refused(self):
        with self.assertRaisesRegex(ValueError, "topic"):
            plan_new.scaffold(self.root, "../foo", "tracker")


if __name__ == "__main__":
    unittest.main()
