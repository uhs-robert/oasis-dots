"""Tests the specs step (lib/check/steps/specs.py) on temp-dir checkouts that carry the real schemas, plus one run on the real tree."""

import os
import re
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
GOOD_BODY = "# Bar\n\n## What it is for\nx\n\n## Requirements\n- **BAR-01** [gap: untested] One.\n\n## Not covered\nx\n"
GOOD_PLAN = "kind: plan\nstatus: active\nowner_session: s1\nupdated: 2026-10-25\nspecs: [bar]\nbranch: none\npr: none\n"


def spec_text(front=GOOD_FRONT, body=GOOD_BODY):
    return f"---\n{front}---\n{body}"


class SpecsCase(TreeCase):
    def check(self, files):
        write_tree(self.root, files)
        if specs.GAPS_FILE not in files:
            # Written from the same specs, so only the tests about the gaps file see it drift.
            write_tree(self.root, {specs.GAPS_FILE: specs.render_gaps(specs.read_requirements(self.root))})
        for schema in (specs.SPEC_SCHEMA, specs.PLAN_SCHEMA):
            os.makedirs(os.path.dirname(os.path.join(self.root, schema)), exist_ok=True)
            shutil.copy(os.path.join(REPO_DIR, schema), os.path.join(self.root, schema))
        self.info = []
        return specs.run_checks(self.root, self.info)

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
        specs.write_gaps(self.root)
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


TAG_STYLES = {
    "lib/check/tests/test_bar.py": "    def test_one(self):\n        # req: BAR-01\n        pass\n",
    "home/quickshell/tests/input_settings/vectors.tsv": "repeat_rate\t1\taccept\treq: BAR-01\n",
    "home/voxcmd/tests/run-bar.sh": "#!/bin/bash\n# req: BAR-01\n",
    ".claude/skills/shadow/bar.sh": "# req: BAR-01\n",
    "home/hypr/tests/bar.lua": "-- req: BAR-01\n",
}
TWO_REQUIREMENTS = GOOD_BODY.replace("- **BAR-01** [gap: untested] One.\n", "- **BAR-01** One.\n- **BAR-02** Two.\n")


class LinkTest(SpecsCase):
    def linked(self, tests, body=TWO_REQUIREMENTS, extra=None):
        return self.check({"specs/core/bar.md": spec_text(body=body), **tests, **(extra or {})})

    def test_every_tag_style_satisfies_its_requirement(self):
        body = GOOD_BODY.replace(" [gap: untested]", "")
        for path, text in TAG_STYLES.items():
            self.assertEqual(self.linked({path: text}, body=body), [], path)

    def test_comma_separated_ids_tag_each(self):
        self.assertEqual(self.linked({"home/hypr/tests/z.lua": "-- req: BAR-01, BAR-02\n"}), [])

    def test_the_vectors_row_with_a_tag_still_parses_in_both_validators(self):
        row = TAG_STYLES["home/quickshell/tests/input_settings/vectors.tsv"].rstrip("\n")
        lua_shape = re.match(r"^([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$", row)
        self.assertEqual(lua_shape.groups(), ("repeat_rate", "1", "accept", "req: BAR-01"))
        self.assertEqual(row.split("\t")[:3], ["repeat_rate", "1", "accept"])

    def test_a_missing_tag_fails(self):
        self.assertEqual(len(self.linked({})), 2)

    def test_gap_untested_passes_without_a_tag(self):
        self.assertEqual(self.linked({}, body=GOOD_BODY), [])

    def test_gap_unmet_needs_no_tag(self):
        self.assertEqual(self.linked({}, body=GOOD_BODY.replace("[gap: untested]", "[gap: unmet]")), [])

    def test_an_orphan_tag_fails(self):
        found = self.linked({"lib/check/tests/test_x.py": "# req: BAR-09\n"}, body=GOOD_BODY)
        self.assertEqual(found, ["lib/check/tests/test_x.py:1: tag BAR-09 names no requirement in specs/core"])

    def test_a_tag_outside_the_scan_roots_is_not_read(self):
        self.assertEqual(self.linked({"docs/x.md": "req: BAR-09\n"}, body=GOOD_BODY), [])

    def test_a_tag_inside_a_string_literal_is_not_coverage(self):
        body = GOOD_BODY.replace(" [gap: untested]", "")
        for text in ('fixture = "# req: BAR-01"\n', "x = 'req: BAR-01'\n", 'echo "-- req: BAR-01"\n', "call(1)  # ok\nsend(\"req: BAR-01\")\n"):
            found = self.linked({"lib/check/tests/test_x.py": text}, body=body)
            self.assert_one_mentions(found, "BAR-01 has no test tagged")

    def test_a_trailing_comment_tag_counts(self):
        body = GOOD_BODY.replace(" [gap: untested]", "")
        for text in ("run()  # req: BAR-01\n", 'assert value == "x"  # req: BAR-01\n', "a = 'it\\'s'  // req: BAR-01\n"):
            self.assertEqual(self.linked({"lib/check/tests/test_x.py": text}, body=body), [], text)

    def test_a_marker_inside_a_string_then_a_real_comment_tags_once(self):
        self.assertEqual(specs.tags_in_line('x = "a # b"  # req: BAR-01', False), ["BAR-01"])

    def test_only_the_tsv_note_column_and_comment_lines_carry_a_tag(self):
        body = GOOD_BODY.replace(" [gap: untested]", "")
        tsv = "home/quickshell/tests/input_settings/vectors.tsv"
        self.assert_one_mentions(self.linked({tsv: "req: BAR-01\t1\taccept\tnote\n"}, body=body), "BAR-01 has no test tagged")
        self.assert_one_mentions(self.linked({tsv: "k\t1\taccept\n"}, body=body), "BAR-01 has no test tagged")
        self.assertEqual(self.linked({tsv: "# req: BAR-01\nk\t1\taccept\tnote\n"}, body=body), [])

    def test_a_one_letter_prefix_id_is_not_a_requirement(self):
        self.assertEqual(self.linked({}, body=GOOD_BODY + "- **B-01** x\n- **B-01** x\n"), [])

    def test_a_word_ending_in_req_is_not_a_tag(self):
        self.assertEqual(self.linked({"lib/check/tests/test_x.py": "# freq: BAR-09\n"}, body=GOOD_BODY), [])

    def test_a_duplicate_id_fails(self):
        found = self.linked({}, body=GOOD_BODY.replace("## Not covered", "- **BAR-01** [gap: unmet] Again.\n\n## Not covered"))
        self.assert_one_mentions(found, "BAR-01 repeats specs/core/bar.md:12")

    def test_the_template_requirements_are_not_read(self):
        with open(os.path.join(REPO_DIR, "specs/core/TEMPLATE.md")) as handle:
            self.assertEqual(self.check({"specs/core/TEMPLATE.md": handle.read()}), [])

    def test_untagged_tests_are_info_only(self):
        found = self.linked({"lib/check/tests/test_y.py": "pass\n", "home/hypr/tests/z.lua": "-- req: BAR-01\n"}, body=GOOD_BODY)
        self.assertEqual(found, [])
        self.assertEqual(self.info, ["info: 1 test files carry no requirement tag (allowed):", "  lib/check/tests/test_y.py"])

    def test_no_specs_means_no_info(self):
        self.assertEqual(self.check({"lib/check/tests/test_y.py": "pass\n"}), [])
        self.assertEqual(self.info, [])


class GapsFileTest(SpecsCase):
    def test_a_stale_gaps_file_fails(self):
        found = self.check({"specs/core/bar.md": spec_text(), specs.GAPS_FILE: specs.GAPS_HEADER + "None.\n"})
        self.assert_one_mentions(found, "specs/gaps.md", "out of date")

    def test_a_missing_gaps_file_fails_even_with_no_specs(self):
        write_tree(self.root, {"specs/roadmap.md": "x\n"})
        self.assert_one_mentions(self.check_without_gaps(), "specs/gaps.md", "missing")

    def check_without_gaps(self):
        for schema in (specs.SPEC_SCHEMA, specs.PLAN_SCHEMA):
            os.makedirs(os.path.dirname(os.path.join(self.root, schema)), exist_ok=True)
            shutil.copy(os.path.join(REPO_DIR, schema), os.path.join(self.root, schema))
        return specs.run_checks(self.root)

    def test_the_empty_form_is_present_and_says_none(self):
        self.assertTrue(specs.render_gaps([]).endswith("# Gaps\n\nNone.\n"))

    def test_the_gaps_list_each_marker_by_id(self):
        body = GOOD_BODY.replace("## Not covered", "- **BAR-02** [gap: unmet] Two.\n\n## Not covered")
        text = specs.render_gaps(specs.read_requirements(self._tree({"specs/core/bar.md": spec_text(body=body)})))
        self.assertIn("- **BAR-01** (untested; [bar.md](core/bar.md)) One.\n- **BAR-02** (unmet; [bar.md](core/bar.md)) Two.\n", text)

    def _tree(self, files):
        write_tree(self.root, files)
        return self.root

    def test_write_regenerates_the_file(self):
        self._tree({"specs/core/bar.md": spec_text(), specs.GAPS_FILE: "stale\n"})
        specs.write_gaps(self.root)
        self.assertEqual(specs.check_gaps_file(self.root), [])
        with open(os.path.join(self.root, specs.GAPS_FILE)) as handle:
            self.assertIn("BAR-01", handle.read())

    def test_the_script_write_flag_regenerates_in_a_checkout(self):
        self._tree({"specs/core/bar.md": spec_text(), specs.GAPS_FILE: "stale\n"})
        step_dir = os.path.join(self.root, "lib", "check", "steps")
        os.makedirs(step_dir)
        shutil.copy(os.path.join(CHECK_DIR, "steps", "specs.py"), step_dir)
        for schema in (specs.SPEC_SCHEMA, specs.PLAN_SCHEMA):
            os.makedirs(os.path.dirname(os.path.join(self.root, schema)), exist_ok=True)
            shutil.copy(os.path.join(REPO_DIR, schema), os.path.join(self.root, schema))
        done = subprocess.run([sys.executable, "-B", os.path.join(step_dir, "specs.py"), "--write"], capture_output=True, text=True, cwd=self.root)
        self.assertEqual(done.returncode, 0, done.stderr)


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

    def test_the_tracked_links_and_gaps_file_pass(self):
        self.assertEqual(specs.check_links(REPO_DIR)[0], [])
        self.assertEqual(specs.check_gaps_file(REPO_DIR), [])


if __name__ == "__main__":
    unittest.main()
