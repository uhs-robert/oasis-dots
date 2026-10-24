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

    def check(self, files, allow="", sibling_allow=()):
        for name in os.listdir(self.root):
            shutil.rmtree(os.path.join(self.root, name))
        write_tree(self.root, {**files, ALLOW: allow})
        subprocess.run(("git", "init", "-q"), cwd=self.root, check=True)
        return [f"{f.path}:{f.line}: {f.message}" for f in qml_layers.run_checks(self.root, "qs", ALLOW, set(sibling_allow))]

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


class SiblingTest(LayersCase):
    def run_siblings(self, files, allow=()):
        return self.check(files, sibling_allow=allow)

    def test_a_cross_feature_relative_import_fails(self):
        found = self.run_siblings({"qs/features/a/A.qml": 'import "../b/G.js" as G\n', "qs/features/b/G.js": ""})
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith('qs/features/a/A.qml:1: import "../b/G.js" reaches into another feature (features/b/G.js).'), found)

    def test_a_nested_file_reaching_a_sibling_feature_fails(self):
        found = self.run_siblings({"qs/features/a/sub/A.qml": 'import "../../b/G.js" as G\n', "qs/features/b/G.js": ""})
        self.assertEqual(len(found), 1)
        self.assertIn('import "../../b/G.js" reaches into another feature (features/b/G.js)', found[0])

    def test_a_js_import_across_features_fails(self):
        found = self.run_siblings({"qs/features/a/x.js": '.import "../b/G.js" as G\n', "qs/features/b/G.js": ""})
        self.assertEqual(len(found), 1)
        self.assertIn('qs/features/a/x.js:1: import "../b/G.js" reaches into another feature', found[0])

    def test_a_same_feature_import_passes(self):
        files = {"qs/features/a/A.qml": 'import "sub"\nimport "sub/G.js" as G\n', "qs/features/a/sub/G.js": "", "qs/features/a/sub/B.qml": 'import "../H.js" as H\n', "qs/features/a/H.js": ""}
        self.assertEqual(self.run_siblings(files), [])

    def test_a_cross_style_import_fails(self):
        found = self.run_siblings({"qs/styles/x/A.qml": 'import "../y/widgets"\n', "qs/styles/y/widgets/W.qml": ""})
        self.assertEqual(len(found), 1)
        self.assertIn("reaches into another style (styles/y/widgets)", found[0])

    def test_a_file_directly_under_styles_may_import_each_style(self):
        self.assertEqual(self.run_siblings({"qs/styles/index.js": '.import "x/t.js" as X\n', "qs/styles/x/t.js": ""}), [])

    def test_a_qs_import_across_features_is_not_checked(self):
        self.assertEqual(self.run_siblings({"qs/features/a/A.qml": "import qs.features.b\n"}), [])

    def test_an_allowlisted_edge_passes(self):
        files = {"qs/features/a/A.qml": 'import "../b/G.js" as G\n'}
        self.assertEqual(self.run_siblings(files, {("features/a/A.qml", "features/b/G.js")}), [])

    def test_a_stale_allowlist_entry_fails(self):
        found = self.run_siblings({"qs/features/a/A.qml": "Item {}\n"}, {("features/a/A.qml", "features/b/G.js")})
        self.assertEqual(len(found), 1)
        self.assertIn("SIBLING_ALLOW entry features/a/A.qml -> features/b/G.js is stale", found[0])


class ScriptFolderTest(LayersCase):
    def test_own_folder_subfolder_and_lower_layer_imports_pass(self):
        files = {
            "qs/features/a/A.qml": 'import "G.js" as G\nimport "sub/H.js" as H\nimport "../../ui/frames/F.js" as F\nimport "../../core/C.js" as C\n',
            "qs/features/a/x.js": '.import "sub/H.js" as H\n.import "../../core/C.js" as C\n',
            "qs/ui/Box.qml": 'import "../core/C.js" as C\n',
        }
        self.assertEqual(self.check(files), [])

    def test_a_child_may_import_a_helper_from_an_ancestor_in_its_layer(self):
        files = {"qs/features/a/sub/deep/A.qml": 'import "../../G.js" as G\nimport "../H.js" as H\n', "qs/styles/s/widgets/W.qml": 'import "../T.js" as T\n'}
        self.assertEqual(self.check(files), [])

    def test_a_sibling_folder_script_fails_with_the_fix(self):
        found = self.check({"qs/features/a/sub/A.qml": 'import "../other/G.js" as G\n'})
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith('qs/features/a/sub/A.qml:1: import "../other/G.js" reaches a sibling folder (features/a/other/G.js).'), found)

    def test_a_script_import_inside_ui_passes_between_any_folders(self):
        files = {"qs/ui/menu/R.qml": 'import "../keys/K.js" as K\nimport "../Search.js" as S\n', "qs/ui/Box.qml": 'import "menu/M.js" as M\n'}
        self.assertEqual(self.check(files), [])

    def test_a_theme_script_import_from_styles_is_upward(self):
        found = self.check({"qs/theme/Style.qml": 'import "../styles/goldeneye/Watch.js" as W\n'})
        self.assertEqual(len(found), 1)
        self.assertIn("runs upward", found[0])

    def test_styles_may_import_script_from_theme(self):
        self.assertEqual(self.check({"qs/styles/goldeneye/widgets/W.qml": 'import "../../../theme/Tokens.js" as T\n'}), [])

    def test_a_target_outside_the_ranked_layers_is_not_judged(self):
        files = {"qs/features/a/A.qml": 'import "../../scripts/x.js" as X\nimport "../../assets/y.js" as Y\n'}
        self.assertEqual(self.check(files), [])

    def test_a_cross_feature_script_is_reported_once(self):
        found = self.check({"qs/features/a/A.qml": 'import "../b/G.js" as G\n'})
        self.assertEqual(len(found), 1)
        self.assertIn("reaches into another feature", found[0])

    def test_an_upward_script_is_the_layer_rules_alone(self):
        found = self.check({"qs/ui/Box.qml": 'import "../styles/Data.js" as D\n'})
        self.assertEqual(len(found), 1)
        self.assertIn("runs upward", found[0])

    def test_an_allowlisted_upward_script_passes(self):
        files = {"qs/theme/Style.qml": 'import "../styles/goldeneye/Watch.js" as W\n'}
        allow = "theme/Style.qml -> styles/goldeneye/Watch.js  # style data (permanent)\n"
        self.assertEqual(self.check(files, allow), [])

    def test_a_folder_import_is_not_a_script_import(self):
        self.assertEqual(self.check({"qs/features/a/sub/A.qml": 'import ".."\n'}), [])

    def test_an_allowlisted_script_passes(self):
        files = {"qs/features/a/sub/A.qml": 'import "../other/G.js" as G\n'}
        entry = {("features/a/sub/A.qml", "features/a/other/G.js")}
        self.assertEqual(self.check(files, sibling_allow=entry), [])

    def test_a_stale_script_entry_fails(self):
        entry = {("features/a/sub/A.qml", "features/a/other/G.js")}
        found = self.check({"qs/features/a/sub/A.qml": "Item {}\n"}, sibling_allow=entry)
        self.assertIn("SIBLING_ALLOW entry features/a/sub/A.qml -> features/a/other/G.js is stale", found[0])


class LiveTreeTest(unittest.TestCase):
    def test_the_repository_passes(self):
        self.assertEqual(qml_layers.run_checks(REPO_DIR), [])


if __name__ == "__main__":
    unittest.main()
