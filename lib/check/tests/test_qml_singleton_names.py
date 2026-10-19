"""Tests the singleton-name check (lib/check/steps/qml_singleton_names.py) on tiny git repositories, plus one run on the real tree."""

import os
import shutil
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_DIR = os.path.dirname(os.path.dirname(CHECK_DIR))
sys.path.insert(0, os.path.join(CHECK_DIR, "steps"))
import qml_singleton_names  # noqa: E402
from test_qml import TreeCase, write_tree  # noqa: E402

ALLOW = "allow"
SINGLETON = "pragma Singleton\nimport QtQuick\nQtObject {}\n"


class NamesCase(TreeCase):
    """A repository with the Quickshell tree in qs/ and the allowlist in allow."""

    def check(self, files, allow=""):
        for name in os.listdir(self.root):
            shutil.rmtree(os.path.join(self.root, name))
        write_tree(self.root, {**files, ALLOW: allow})
        subprocess.run(("git", "init", "-q"), cwd=self.root, check=True)
        return [f"{f.path}:{f.line}: {f.message}" for f in qml_singleton_names.run_checks(self.root, "qs", ALLOW)]


class NameTest(NamesCase):
    def test_plain_nouns_settings_and_state_pass(self):
        files = {f"qs/core/{name}.qml": SINGLETON for name in ("Sessions", "Settings", "State", "BarSettings", "NetworkState")}
        self.assertEqual(self.check(files), [])

    def test_a_new_store_singleton_fails_with_the_rule(self):
        found = self.check({"qs/features/foo/FooStore.qml": SINGLETON})
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith("qs/features/foo/FooStore.qml:1: singleton FooStore ends in Store. Name it Settings"), found)
        self.assertIn('add "features/foo/FooStore.qml  # <reason> (<item>)" to allow', found[0])

    def test_each_banned_suffix_fails(self):
        files = {f"qs/core/A{suffix}.qml": SINGLETON for suffix in ("Config", "Store", "Manager")}
        self.assertEqual(len(self.check(files)), 3)

    def test_a_non_singleton_with_a_banned_name_passes(self):
        self.assertEqual(self.check({"qs/ui/RowConfig.qml": "import QtQuick\nItem {}\n"}), [])

    def test_a_commented_out_pragma_does_not_make_a_singleton(self):
        self.assertEqual(self.check({"qs/ui/RowConfig.qml": "// pragma Singleton\n/*\npragma Singleton\n*/\nItem {}\n"}), [])

    def test_a_banned_word_in_the_middle_of_a_name_passes(self):
        self.assertEqual(self.check({"qs/core/ConfigPaths.qml": SINGLETON, "qs/core/StoreFront.qml": SINGLETON}), [])


class AllowlistTest(NamesCase):
    FILES = {"qs/features/foo/FooStore.qml": SINGLETON}
    ENTRY = "features/foo/FooStore.qml  # renamed to Foos (5.8 PR 2)\n"

    def test_an_allowlisted_singleton_passes(self):
        self.assertEqual(self.check(self.FILES, "# header\n\n" + self.ENTRY), [])

    def test_a_stale_entry_fails_after_the_rename(self):
        found = self.check({"qs/features/foo/Foos.qml": SINGLETON}, self.ENTRY)
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith(f"{ALLOW}:1: features/foo/FooStore.qml is stale"), found)

    def test_an_entry_for_a_file_that_is_no_longer_a_singleton_fails(self):
        found = self.check({"qs/features/foo/FooStore.qml": "Item {}\n"}, self.ENTRY)
        self.assertEqual(len(found), 1)
        self.assertIn("is stale", found[0])

    def test_malformed_and_duplicate_lines_fail(self):
        allow = "features/foo/FooStore.qml\nnonsense\nfeatures/foo/FooStore.qml  # reason without an item\n" + self.ENTRY + self.ENTRY
        found = self.check(self.FILES, allow)
        self.assertEqual(found, [
            f'{ALLOW}:1: malformed; expected "<file>.qml  # <reason> (<item>)"',
            f'{ALLOW}:2: malformed; expected "<file>.qml  # <reason> (<item>)"',
            f'{ALLOW}:3: malformed; expected "<file>.qml  # <reason> (<item>)"',
            f"{ALLOW}:5: duplicate entry for features/foo/FooStore.qml",
        ])

    def test_a_second_offender_beside_an_allowlisted_one_still_fails(self):
        files = {**self.FILES, "qs/features/foo/BarManager.qml": SINGLETON}
        found = self.check(files, self.ENTRY)
        self.assertEqual(len(found), 1)
        self.assertIn("BarManager", found[0])


class LiveTreeTest(unittest.TestCase):
    def test_the_repository_passes(self):
        self.assertEqual(qml_singleton_names.run_checks(REPO_DIR), [])


if __name__ == "__main__":
    unittest.main()
