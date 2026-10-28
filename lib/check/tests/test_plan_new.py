"""Tests the .plans scaffold (lib/plan_new.py): each kind yields a doc with valid front matter."""

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


def front_matter(path):
    """The doc's leading --- block as a key/value dict."""
    with open(path) as handle:
        block = handle.read().split("---\n")[1]
    return dict(line.split(": ", 1) for line in block.splitlines() if ": " in line)


def assert_valid_front_matter(test, path, kind):
    front = front_matter(path)
    expected_keys = {"kind", "status", "owner_session", "updated", "pr"} | ({"branch"} if kind != "tracker" else set())
    test.assertEqual(set(front), expected_keys)
    test.assertEqual(front["kind"], kind)
    test.assertIn(front["status"], ("active", "parked", "done"))
    test.assertRegex(front["updated"].strip('"'), r"^\d{4}-\d{2}-\d{2}$")
    test.assertEqual(front["pr"], "none")


class ScaffoldTest(TreeCase):
    def test_each_kind_has_valid_front_matter_at_its_path(self):
        for kind, item, name in (("tracker", None, "foo/foo.md"), ("plan", "bar", "foo/foo-bar-plan-draft.md"), ("handoff", None, "foo/foo-handoff.md")):
            path = plan_new.scaffold(self.root, "foo", kind, item, today="2026-10-27")
            self.assertEqual(path, os.path.join(self.root, ".plans", name))
            assert_valid_front_matter(self, path, kind)

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

    def test_a_handoff_with_an_item_gets_the_draft_name(self):
        path = plan_new.scaffold(self.root, "foo", "handoff", "bar")
        self.assertEqual(path, os.path.join(self.root, ".plans/foo/foo-bar-handoff-draft.md"))
        assert_valid_front_matter(self, path, "handoff")

    def test_an_item_cannot_leave_the_topic_folder(self):
        for kind in ("plan", "handoff"):
            with self.assertRaisesRegex(ValueError, "item"):
                plan_new.scaffold(self.root, "foo", kind, "../../evil")
        self.assertFalse(os.path.exists(os.path.join(self.root, ".plans", "evil-handoff-draft.md")))

    @unittest.skipUnless(shutil.which("just"), "needs just")
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
