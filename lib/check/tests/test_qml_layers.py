"""Tests the layer check (lib/check/steps/qml_layers.py) on tiny git repositories, plus one run on the real tree."""

import os
import shutil
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_DIR = os.path.dirname(os.path.dirname(CHECK_DIR))
sys.path.insert(0, os.path.join(CHECK_DIR, "steps"))
import qml_layers  # noqa: E402
from test_qml import TreeCase, write_tree  # noqa: E402

ALLOW = "allow"
FEATURE_USER = "import qs.features.clock\nItem {}\n"


class LayersCase(TreeCase):
    """A repository with the Quickshell tree in qs/ and the allowlist in allow."""

    def check(self, files, allow=""):
        for name in os.listdir(self.root):
            shutil.rmtree(os.path.join(self.root, name))
        write_tree(self.root, {**files, ALLOW: allow})
        subprocess.run(("git", "init", "-q"), cwd=self.root, check=True)
        return [f"{f.path}:{f.line}: {f.message}" for f in qml_layers.run_checks(self.root, "qs", ALLOW)]

    def messages(self, files, allow=""):
        return [line.split(": ", 1)[1] for line in self.check(files, allow)]


class DirectionTest(LayersCase):
    def test_downward_and_same_rank_imports_pass(self):
        files = {
            "qs/features/clock/Clock.qml": "import qs.ui\nimport qs.theme\nimport qs.core\nimport qs.features.power\n",
            "qs/ui/Box.qml": "import qs.theme\n",
            "qs/core/Core.qml": "import QtQuick\n",
            "qs/theme/Style.qml": "import qs.core\n",
            "qs/ui/x.js": '.import "../theme/y.js" as Y\n',
        }
        self.assertEqual(self.check(files), [])

    def test_ui_importing_a_feature_fails_with_the_fix(self):
        found = self.check({"qs/ui/Box.qml": FEATURE_USER, "qs/features/clock/Clock.qml": ""})
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith("qs/ui/Box.qml:1: import qs.features.clock runs upward (ui rank 2 -> features rank 5)."), found)
        self.assertIn('add "ui/Box.qml -> qs.features.clock  # <reason> (<item>)" to allow', found[0])

    def test_relative_folder_and_script_imports_fail(self):
        files = {
            "qs/ui/Box.qml": 'import "../styles/neon"\nimport "../styles/Data.js" as Data\n',
            "qs/theme/t.js": '.import "../features/f.js" as F\n',
        }
        found = [message.split(" runs upward", 1)[0] for message in self.messages(files)]
        self.assertEqual(found, ['import "../features/f.js"', 'import "../styles/neon"', 'import "../styles/Data.js"'])

    def test_a_url_load_with_a_literal_head_fails_and_a_dynamic_head_does_not(self):
        files = {
            "qs/ui/Box.qml": 'a: Qt.resolvedUrl("../styles/" + name)\nb: Qt.resolvedUrl(base + "/styles/x")\nc: Qt.resolvedUrl("Local.qml")\n',
        }
        found = self.messages(files)
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith('load of "../styles/" runs upward (ui rank 2 -> styles rank 4).'))
        self.assertIn('"ui/Box.qml -> url:styles  #', found[0])

    def test_commented_out_imports_are_ignored(self):
        self.assertEqual(self.check({"qs/ui/Box.qml": "// import qs.features.clock\n/* import qs.styles.x */\n"}), [])

    def test_unknown_top_folder_fails_and_unranked_and_root_files_pass(self):
        files = {"qs/shell.qml": "import qs.features.clock\n", "qs/scripts/a.js": "x\n", "qs/misc/A.qml": "import qs.features.clock\n", "qs/misc/B.qml": ""}
        self.assertEqual(self.messages(files), ['top folder "misc" has no rank; add it to LAYERS (or UNRANKED) in lib/check/steps/qml_layers.py'])


class AllowlistTest(LayersCase):
    FILES = {"qs/ui/Box.qml": FEATURE_USER}
    ENTRY = "ui/Box.qml -> qs.features.clock  # shared clock moves (5.9 step 3)\n"

    def test_an_allowlisted_edge_passes(self):
        self.assertEqual(self.check(self.FILES, "# header\n\n" + self.ENTRY), [])

    def test_a_stale_entry_fails(self):
        found = self.check({"qs/ui/Box.qml": "import qs.theme\n"}, self.ENTRY)
        self.assertEqual(found, [f"{ALLOW}:1: ui/Box.qml -> qs.features.clock is stale: the file no longer reaches it. Delete the line."])

    def test_an_entry_for_a_downward_edge_fails(self):
        found = self.check({"qs/ui/Box.qml": "import qs.theme\n"}, "ui/Box.qml -> qs.theme  # why (never)\n")
        self.assertEqual(found, [f"{ALLOW}:1: ui/Box.qml -> qs.theme is not an upward edge. Delete the line."])

    def test_missing_reason_malformed_and_duplicate_lines_fail(self):
        allow = "ui/Box.qml -> qs.features.clock\nnonsense\nui/Box.qml -> qs.features.power  # reason without an item\n" + self.ENTRY + self.ENTRY
        found = self.check(self.FILES, allow)
        self.assertEqual(found, [
            f'{ALLOW}:1: malformed; expected "<file> -> <target>  # <reason> (<item>)"',
            f'{ALLOW}:2: malformed; expected "<file> -> <target>  # <reason> (<item>)"',
            f'{ALLOW}:3: malformed; expected "<file> -> <target>  # <reason> (<item>)"',
            f"{ALLOW}:5: duplicate entry for ui/Box.qml -> qs.features.clock",
        ])

    def test_an_entry_covers_the_file_target_pair_not_the_line(self):
        files = {"qs/ui/Box.qml": FEATURE_USER + "import qs.features.clock\n"}
        self.assertEqual(self.check(files, self.ENTRY), [])

    def test_a_new_edge_from_an_allowlisted_file_still_fails(self):
        files = {"qs/ui/Box.qml": FEATURE_USER + "import qs.features.power\n"}
        found = self.check(files, self.ENTRY)
        self.assertEqual(len(found), 1)
        self.assertIn("import qs.features.power runs upward", found[0])


class LiveTreeTest(unittest.TestCase):
    def test_the_repository_passes(self):
        self.assertEqual(qml_layers.run_checks(REPO_DIR), [])


if __name__ == "__main__":
    unittest.main()
