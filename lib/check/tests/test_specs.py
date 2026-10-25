"""Tests the specs step (lib/check/steps/specs.py) on temp-dir checkouts that carry the real schemas, plus one run on the real tree."""

import os
import shutil
import subprocess
import sys
import unittest
from unittest import mock

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_DIR = os.path.dirname(os.path.dirname(CHECK_DIR))
sys.path.insert(0, os.path.join(CHECK_DIR, "steps"))
import specs  # noqa: E402
from test_qml import TreeCase, write_tree  # noqa: E402

GOOD_FRONT = "id: bar\ntitle: Bar\nstatus: draft\n"
GOOD_BODY = "# Bar\n\n## What it is for\nx\n\n## Requirements\n- **BAR-01** One.\n\n## Not covered\nx\n"
GOOD_PLAN = "kind: plan\nstatus: active\nowner_session: s1\nupdated: 2026-10-25\nspecs: [bar]\nbranch: none\npr: none\n"


def spec_text(front=GOOD_FRONT, body=GOOD_BODY):
    return f"---\n{front}---\n{body}"


class SpecsCase(TreeCase):
    def check(self, files):
        write_tree(self.root, files)
        for schema in (specs.SPEC_SCHEMA, specs.PLAN_SCHEMA):
            os.makedirs(os.path.dirname(os.path.join(self.root, schema)), exist_ok=True)
            shutil.copy(os.path.join(REPO_DIR, schema), os.path.join(self.root, schema))
        return specs.run_checks(self.root)

    def spec(self, text, name="bar"):
        return self.check({f"specs/core/{name}.md": text})

    def assert_one_mentions(self, found, *needles):
        self.assertEqual(len(found), 1, found)
        for needle in needles:
            self.assertIn(needle, found[0])


class SpecFrontMatterTest(SpecsCase):
    def test_a_valid_spec_passes(self):
        full = "id: bar\ntitle: Bar\nstatus: approved\napproved: 2026-10-25\nprs: [1234]\nimplements: [home/quickshell]\ndepends_on: [actions]\nactions: [zoom.toggle]\nkeys: [mod+b]\n"
        self.assertEqual(self.spec(spec_text(full)), [])

    def test_no_specs_passes(self):
        self.assertEqual(self.check({"specs/roadmap.md": "# Roadmap\n"}), [])

    def test_a_bad_status_fails(self):
        self.assert_one_mentions(self.spec(spec_text("id: bar\ntitle: Bar\nstatus: done\n")), "bar.md", "status")

    def test_approved_status_needs_a_date(self):
        self.assert_one_mentions(self.spec(spec_text("id: bar\ntitle: Bar\nstatus: approved\n")), "bar.md", "approved")

    def test_an_unknown_key_fails(self):
        self.assert_one_mentions(self.spec(spec_text(GOOD_FRONT + "reqs: [BAR-01]\n")), "bar.md", "reqs")

    def test_a_badly_typed_field_fails(self):
        self.assert_one_mentions(self.spec(spec_text(GOOD_FRONT + "prs: [abc]\n")), "bar.md", "prs")

    def test_quoted_ids_compare_by_value(self):
        for quoted in ('"bar"', "'bar'"):
            self.assertEqual(self.spec(spec_text(GOOD_FRONT.replace("id: bar", f"id: {quoted}"))), [], quoted)
        found = self.spec(spec_text(GOOD_FRONT.replace("id: bar", 'id: "baz"')))
        self.assertIn("specs/core/bar.md:1: id baz is not the file name bar", found)

    def test_an_impossible_date_fails(self):
        self.assert_one_mentions(self.spec(spec_text("id: bar\ntitle: Bar\nstatus: approved\napproved: 2026-99-99\n")), "bar.md", "approved")

    def test_crlf_line_endings_pass(self):
        text = spec_text().replace("\n", "\r\n")
        self.check({"specs/core/.keep": ""})
        with open(os.path.join(self.root, "specs/core/bar.md"), "w", newline="") as handle:
            handle.write(text)
        self.assertEqual(specs.run_checks(self.root), [])

    def test_a_rule_inside_the_body_does_not_end_the_front_matter_early(self):
        self.assertEqual(self.spec(spec_text(body=GOOD_BODY + "\n---\n\nmore\n")), [])

    def test_empty_front_matter_fails(self):
        found = self.spec(spec_text("", GOOD_BODY))
        self.assertTrue(found and all("bar.md" in line or line.startswith("  ") for line in found), found)

    def test_an_id_that_is_not_the_file_name_fails(self):
        self.assertEqual(self.spec(spec_text(), name="baz"), ["specs/core/baz.md:1: id bar is not the file name baz"])

    def test_missing_front_matter_fails(self):
        self.assertEqual(self.spec(GOOD_BODY), ["specs/core/bar.md:1: no front matter (a spec starts with a `---` block)"])


class SpecBodyTest(SpecsCase):
    def test_a_missing_heading_fails(self):
        found = self.spec(spec_text(body=GOOD_BODY.replace("## Not covered\nx\n", "")))
        self.assertEqual(found, ["specs/core/bar.md:6: missing the `## Not covered` heading"])

    def test_a_missing_title_fails(self):
        found = self.spec(spec_text(body=GOOD_BODY.replace("# Bar\n", "")))
        self.assertEqual(found, ["specs/core/bar.md:6: no `# <title>` heading after the front matter"])

    def test_look_is_optional(self):
        self.assertEqual(self.spec(spec_text(body=GOOD_BODY + "\n## Look\nx\n")), [])

    def test_a_requirement_with_another_prefix_fails(self):
        found = self.spec(spec_text(body=GOOD_BODY.replace("BAR-01", "LOCK-01")))
        self.assertEqual(found, ["specs/core/bar.md:12: requirement LOCK-.. does not start with BAR, the prefix of spec bar"])

    def test_a_one_digit_number_is_not_a_requirement_id(self):
        self.assertEqual(self.spec(spec_text(body=GOOD_BODY + "- **LOCK-1** not an id\n")), [])

    def test_a_requirement_in_a_code_fence_is_not_read(self):
        self.assertEqual(self.spec(spec_text(body=GOOD_BODY + "\n```\n- **LOCK-01** shown\n```\n")), [])


class TemplateTest(SpecsCase):
    def test_the_real_template_validates_and_skips_the_id_rules(self):
        with open(os.path.join(REPO_DIR, "specs/core/TEMPLATE.md")) as handle:
            self.assertEqual(self.check({"specs/core/TEMPLATE.md": handle.read()}), [])

    def test_the_template_front_matter_is_still_validated(self):
        found = self.check({"specs/core/TEMPLATE.md": spec_text("id: example\ntitle: Example\nstatus: wrong\n")})
        self.assert_one_mentions(found, "TEMPLATE.md", "status")

    def test_the_template_headings_are_still_required(self):
        found = self.check({"specs/core/TEMPLATE.md": spec_text("id: example\ntitle: Example\nstatus: draft\n", "# Example\n")})
        self.assertEqual(len(found), 3, found)


class PlanTest(SpecsCase):
    def plan(self, front):
        return self.check({".plans/p/tracker.md": f"---\n{front}---\n# Plan\n"})

    def test_a_valid_plan_passes(self):
        self.assertEqual(self.plan(GOOD_PLAN), [])
        self.assertEqual(self.plan(GOOD_PLAN.replace("pr: none", "pr: 1234")), [])

    def test_no_plans_folder_passes(self):
        self.assertEqual(self.check({}), [])

    def test_plans_and_handoffs_need_a_branch_but_trackers_do_not(self):
        no_branch = GOOD_PLAN.replace("branch: none\n", "")
        self.assert_one_mentions(self.plan(no_branch), "tracker.md", "branch")
        self.assert_one_mentions(self.plan(no_branch.replace("kind: plan", "kind: handoff")), "tracker.md", "branch")
        self.assertEqual(self.plan(no_branch.replace("kind: plan", "kind: tracker")), [])

    def test_an_impossible_date_fails(self):
        self.assert_one_mentions(self.plan(GOOD_PLAN.replace("2026-10-25", "2026-02-30")), "tracker.md", "updated")

    def test_a_bad_kind_fails(self):
        self.assert_one_mentions(self.plan(GOOD_PLAN.replace("kind: plan", "kind: note")), "tracker.md", "kind")

    def test_a_missing_field_fails(self):
        self.assert_one_mentions(self.plan(GOOD_PLAN.replace("pr: none\n", "")), "tracker.md", "pr")

    def test_a_plan_without_front_matter_fails(self):
        self.assertEqual(self.check({".plans/x.md": "# Plan\n"}), [".plans/x.md:1: no front matter (a plan starts with a `---` block)"])


class MissingToolTest(SpecsCase):
    def test_a_missing_check_jsonschema_fails_even_with_no_specs(self):
        with mock.patch.object(specs.shutil, "which", return_value=None):
            self.assertEqual(self.check({}), [specs.MISSING_TOOL])


class RunnerInvocationTest(SpecsCase):
    """The runner runs the script with no root argument, so it finds the checkout from its own location."""

    def test_repo_dir_is_the_checkout_root(self):
        self.assertTrue(os.path.isfile(os.path.join(specs.REPO_DIR, specs.SPEC_SCHEMA)))
        self.assertTrue(os.path.isfile(os.path.join(specs.REPO_DIR, "specs/core/TEMPLATE.md")))

    def test_the_script_run_in_a_checkout_fails_that_checkouts_bad_spec(self):
        self.check({"specs/core/bar.md": spec_text("id: bar\ntitle: Bar\nstatus: done\n")})
        step_dir = os.path.join(self.root, "lib", "check", "steps")
        os.makedirs(step_dir)
        shutil.copy(os.path.join(CHECK_DIR, "steps", "specs.py"), step_dir)
        done = subprocess.run([sys.executable, "-B", os.path.join(step_dir, "specs.py")], capture_output=True, text=True, cwd=self.root)
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("specs/core/bar.md", done.stderr)


class RealTreeTest(unittest.TestCase):
    def test_the_tracked_specs_pass(self):
        # Not run_checks: a local .plans/ on the machine is not part of the tracked tree.
        self.assertEqual(specs.check_specs(REPO_DIR), [])


if __name__ == "__main__":
    unittest.main()
