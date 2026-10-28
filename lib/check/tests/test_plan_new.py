"""Tests the .plans scaffold (lib/plan_new.py): each kind yields a doc whose front matter passes the plan schema."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_DIR = os.path.dirname(os.path.dirname(CHECK_DIR))
sys.path.insert(0, os.path.join(REPO_DIR, "lib"))
sys.path.insert(0, os.path.join(CHECK_DIR, "tests"))
import plan_new  # noqa: E402
from test_qml import TreeCase  # noqa: E402


def accepted(path):
    """check-jsonschema's verdict on the doc's leading --- block."""
    with open(path) as handle:
        block = handle.read().split("---\n")[1]
    with tempfile.NamedTemporaryFile("w", suffix=".yaml") as front:
        front.write(block)
        front.flush()
        return subprocess.run(["check-jsonschema", "--schemafile", os.path.join(REPO_DIR, "lib/plan-frontmatter.yaml"), front.name],
                              capture_output=True, text=True)


@unittest.skipUnless(shutil.which("check-jsonschema"), "needs check-jsonschema")
class ScaffoldTest(TreeCase):
    def test_each_kind_passes_the_schema_at_its_path(self):
        for kind, item, name in (("tracker", None, "foo/foo.md"), ("plan", "bar", "foo/foo-bar-plan-draft.md"), ("handoff", None, "foo/foo-handoff.md")):
            path = plan_new.scaffold(self.root, "foo", kind, item, today="2026-10-27")
            self.assertEqual(path, os.path.join(self.root, ".plans", name))
            done = accepted(path)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

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
