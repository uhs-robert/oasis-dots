"""Tests the runtime path check (lib/check/steps/qml_paths.py) on tiny git repositories, plus one run on the real tree."""

import os
import shutil
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_DIR = os.path.dirname(os.path.dirname(CHECK_DIR))
sys.path.insert(0, os.path.join(CHECK_DIR, "steps"))
import qml_paths  # noqa: E402
from test_qml import TreeCase, write_tree  # noqa: E402


class PathsCase(TreeCase):
    """A repository with the Quickshell tree in qs/ and the greeter's own files in greeter/."""

    def check(self, files, tables=(), outside=(), greeter_entries=()):
        for name in os.listdir(self.root):
            shutil.rmtree(os.path.join(self.root, name))
        write_tree(self.root, files)
        subprocess.run(("git", "init", "-q"), cwd=self.root, check=True)
        layout = qml_paths.Layout("qs", "greeter", list(tables), list(outside), list(greeter_entries))
        return [f"{f.path}:{f.line}: {f.message}" for f in qml_paths.run_checks(self.root, layout)]


class LiteralTest(PathsCase):
    def test_literal_found_and_renamed(self):
        files = {"qs/a/A.qml": 'Item { source: Qt.resolvedUrl("../b/B.qml") }\n', "qs/b/B.qml": ""}
        self.assertEqual(self.check(files), [])
        renamed = {"qs/a/A.qml": files["qs/a/A.qml"], "qs/b/C.qml": ""}
        self.assertEqual(self.check(renamed), ["qs/a/A.qml:1: b/B.qml does not exist"])

    def test_shell_dir_and_shell_path_resolve_from_the_root(self):
        files = {"qs/a/A.qml": 'x: Quickshell.shellDir + "/scripts/go"\ny: Quickshell.shellPath("scripts/no")\n', "qs/scripts/go": ""}
        self.assertEqual(self.check(files), ["qs/a/A.qml:2: scripts/no does not exist"])

    def test_bare_relative_source_is_a_path_but_urls_are_not(self):
        files = {"qs/A.qml": 'a: 1\nImage { source: "gone.png" }\nImage { source: "image://x/y" }\nPathSvg { path: "M3 2.5" }\n'}
        self.assertEqual(self.check(files), ["qs/A.qml:2: gone.png does not exist"])

    def test_a_ternary_branch_on_source_is_a_path_but_empty_and_call_strings_are_not(self):
        files = {
            "qs/a/A.qml": (
                'Item { source: active ? "../b/B.qml" : "" }\n'
                'Item { source: active ? "../b/gone.qml" : "" }\n'
                'Item { source: active ? "" : "../b/gone2.qml" }\n'
                'Item { source: audio.file("x.wav") }\n'
                'Item { source: active ? Quickshell.iconPath("a", "b") : "" }\n'
                'Item { source: mode === "cmp" ? "" : "" }\n'
                'Item { fragmentShader: a || "../b/gone3.qsb" }\n'
            ),
            "qs/b/B.qml": "",
        }
        self.assertEqual(self.check(files), [
            "qs/a/A.qml:2: b/gone.qml does not exist",
            "qs/a/A.qml:3: b/gone2.qml does not exist",
            "qs/a/A.qml:7: b/gone3.qsb does not exist",
        ])

    def test_single_quoted_forms_are_read_like_double_quoted_ones(self):
        files = {
            "qs/A.qml": "import 'gone'\nImage { source: 'gone.png' }\nx: Qt.resolvedUrl('gone2')\ny: Quickshell.shellDir + '/gone3'\n",
            "qs/b.js": ".import 'gone.js' as G\n",
        }
        self.assertEqual(self.check(files), [
            "qs/A.qml:1: import \"gone\" does not resolve",
            "qs/A.qml:2: gone.png does not exist",
            "qs/A.qml:3: gone2 does not exist",
            "qs/A.qml:4: gone3 does not exist",
            "qs/b.js:1: import \"gone.js\" does not resolve",
        ])

    def test_a_name_inside_a_string_literal_is_not_a_use(self):
        files = {"qs/A.qml": "Text { text: \"Quickshell.shellDir\" }\nText { text: 'Qt.resolvedUrl(x)' }\nText { text: \"source: 'gone.png'\" }\n"}
        self.assertEqual(self.check(files), [])

    def test_commented_use_is_ignored(self):
        self.assertEqual(self.check({"qs/A.qml": '// Qt.resolvedUrl("gone")\n/* Qt.resolvedUrl("gone")\n*/\n'}), [])


class TableTest(PathsCase):
    TABLE = [qml_paths.Table("bar/Bar.qml", "modules/", "services/Modules.js", qml_paths.key_values("file"))]
    FILES = {
        "qs/bar/Bar.qml": 'url: Qt.resolvedUrl("modules/" + spec.file)\n',
        "qs/services/Modules.js": '    { name: "a", file: "A.qml" },\n    { name: "clock", file: "Clock.qml" },\n',
        "qs/bar/modules/A.qml": "",
        "qs/bar/modules/Clock.qml": "",
    }

    def without(self, path):
        return {name: text for name, text in self.FILES.items() if name != path}

    def test_every_table_entry_is_checked_and_the_table_line_named(self):
        self.assertEqual(self.check(self.FILES, self.TABLE), [])
        self.assertEqual(self.check(self.without("qs/bar/modules/Clock.qml"), self.TABLE), ["qs/bar/Bar.qml:1: bar/modules/Clock.qml (from qs/services/Modules.js:2) does not exist"])

    def test_a_rule_that_finds_no_values_fails(self):
        files = {**self.FILES, "qs/services/Modules.js": ""}
        self.assertEqual(self.check(files, self.TABLE), ["qs/bar/Bar.qml:1: no values found in qs/services/Modules.js for its TABLES rule"])

    def test_expression_head_rule(self):
        table = [qml_paths.Table("S.qml", "section.source", "Sections.js", qml_paths.key_values("source"))]
        files = {"qs/S.qml": "x: Qt.resolvedUrl(section.source)\n", "qs/Sections.js": 'source: "a/One.qml"\n', "qs/a/One.qml": ""}
        self.assertEqual(self.check(files, table), [])


class WidgetTokenTest(PathsCase):
    """Meter and ControllerBadge load a style's "<style>/File.qml" token from styles/<style>/widgets/."""

    TABLES = [r for r in qml_paths.TABLES if r.consumer in ("ui/gauges/Meter.qml", "ui/keys/ControllerBadge.qml")]
    FILES = {
        "qs/ui/gauges/Meter.qml": 'source: art === "" ? "" : Qt.resolvedUrl("../../styles/" + art.replace("/", "/widgets/"))\n',
        "qs/ui/keys/ControllerBadge.qml": 'u: Qt.resolvedUrl("../../styles/" + KeyHints.button_path(c).replace("/", "/widgets/"))\n',
        "qs/theme/styles/nes.js": 'meter_art: ({ volume: "nes/HeartMeter.qml", media: "nes/PianoRoll.qml" })\n',
        "qs/ui/keys/KeyHints.js": 'nes: { button: "nes/NesButton.qml", keys: {} },\n',
        "qs/styles/nes/widgets/HeartMeter.qml": "",
        "qs/styles/nes/widgets/PianoRoll.qml": "",
        "qs/styles/nes/widgets/NesButton.qml": "",
    }

    def test_every_token_resolves_under_the_style_widgets_folder(self):
        self.assertEqual(self.check(self.FILES, self.TABLES), [])

    def test_a_renamed_meter_art_or_button_target_fails(self):
        for target, message in (
            ("qs/styles/nes/widgets/PianoRoll.qml", "qs/ui/gauges/Meter.qml:1: styles/nes/widgets/PianoRoll.qml (from qs/theme/styles/nes.js:1) does not exist"),
            ("qs/styles/nes/widgets/NesButton.qml", "qs/ui/keys/ControllerBadge.qml:1: styles/nes/widgets/NesButton.qml (from qs/ui/keys/KeyHints.js:1) does not exist"),
        ):
            files = {name: text for name, text in self.FILES.items() if name != target}
            self.assertEqual(self.check(files, self.TABLES), [message])

    def test_meter_art_in_any_style_file_is_checked(self):
        files = dict(self.FILES, **{"qs/theme/styles/ps2.js": 'meter_art: ({ osd: "ps2/Missing.qml" })\n'})
        self.assertEqual(self.check(files, self.TABLES), [
            "qs/ui/gauges/Meter.qml:1: styles/ps2/widgets/Missing.qml (from qs/theme/styles/ps2.js:1) does not exist",
        ])


class SoundPackTest(PathsCase):
    """ThemeAudio.pack_dir finds a style's pack in styles/<style>/sounds, which may be missing, and an extra pack in sounds/, which may not."""

    TABLES = [r for r in qml_paths.TABLES if r.consumer == "services/ThemeAudio.qml" and r.head == "../sounds/"]
    FILES = {
        "qs/services/ThemeAudio.qml": (
            'readonly property var extra_packs: ({ mgs2: { label: "MGS2" } })\n'
            'function pack_dir(name) {\n'
            '    if (name in extra_packs) return Qt.resolvedUrl("../sounds/" + name);\n'
            '    return Qt.resolvedUrl("../styles/" + name + "/sounds"); // qs-path: optional a style without a pack plays silence\n'
            '}\n'
        ),
        "qs/styles/oasis/sounds/cursor.ogg": "",
        "qs/styles/nes/sounds/cursor.ogg": "",
        "qs/sounds/mgs2/cursor.ogg": "",
    }

    def test_every_pack_resolves(self):
        self.assertEqual(self.check(self.FILES, self.TABLES), [])

    def test_a_style_without_a_pack_folder_passes(self):
        files = {name: text for name, text in self.FILES.items() if name != "qs/styles/nes/sounds/cursor.ogg"}
        self.assertEqual(self.check(files, self.TABLES), [])

    def test_a_missing_extra_pack_folder_fails(self):
        files = {name: text for name, text in self.FILES.items() if name != "qs/sounds/mgs2/cursor.ogg"}
        self.assertEqual(self.check(files, self.TABLES), ["qs/services/ThemeAudio.qml:3: sounds/mgs2 (from qs/services/ThemeAudio.qml:1) does not exist"])


class PrefixTest(PathsCase):
    FILES = {"qs/A.qml": 'u: Qt.resolvedUrl("skins/" + file)\nv: Qt.resolvedUrl("fire" + i + ".png")\n', "qs/skins/S.qml": "", "qs/fire0.png": ""}

    def test_prefix_needs_the_folder_and_a_matching_entry(self):
        self.assertEqual(self.check(self.FILES), [])
        found = self.check({"qs/A.qml": self.FILES["qs/A.qml"], "qs/other.txt": ""})
        self.assertEqual(found, ["qs/A.qml:1: skins does not exist", 'qs/A.qml:2: nothing in ./ starts with "fire" and ends with ".png"'])


class OptionalTargetTest(PathsCase):
    FILES = {
        "qs/.gitignore": "theme.json\nlock/skins/x/audio/\n",
        "qs/A.qml": 'a: Quickshell.shellDir + "/theme.json"\nb: Qt.resolvedUrl("lock/skins/x/audio")\n',
        "qs/lock/skins/x/X.qml": "",
    }

    def test_ignored_target_below_a_folder_with_files_passes(self):
        self.assertEqual(self.check(self.FILES), [])

    def test_ignored_pattern_does_not_excuse_a_moved_parent(self):
        files = {**self.FILES}
        del files["qs/lock/skins/x/X.qml"]
        files["qs/lock/skins/y/X.qml"] = ""
        self.assertEqual(self.check(files), ["qs/A.qml:2: lock/skins/x/audio does not exist"])

    def test_unignored_missing_target_fails_unless_marked_optional(self):
        files = {"qs/A.qml": 'a: Qt.resolvedUrl("none")\nb: Qt.resolvedUrl("none") // qs-path: optional is a sentinel\n'}
        self.assertEqual(self.check(files), ["qs/A.qml:1: none does not exist"])


class UnrecognisedTest(PathsCase):
    def test_unclassifiable_fails_until_marked_skip(self):
        files = {"qs/A.qml": "a: Qt.resolvedUrl(name)\nb: Quickshell.shellDir\nc: Qt.resolvedUrl(flag ? x : y)\n"}
        message = 'unrecognised path expression; add a TABLES rule or a "// qs-path: skip <reason>" marker'
        self.assertEqual(self.check(files), [f"qs/A.qml:{n}: {message}" for n in (1, 2, 3)])
        marked = {"qs/A.qml": "a: Qt.resolvedUrl(name) // qs-path: skip chosen by the user\n"}
        self.assertEqual(self.check(marked), [])


class ImportTest(PathsCase):
    def test_quoted_script_import_script_import_and_commented_import(self):
        files = {
            "qs/a/A.qml": 'import "../lib.js" as Lib\nimport "../gone.js" as Gone\n// import "../ghost.js" as Ghost\nimport qs.b\nimport qs.nope\n',
            "qs/a/B.js": '.pragma library\n.import "../lib.js" as Lib\n.import "gone2.js" as Gone2\n',
            "qs/lib.js": "",
            "qs/b/B.qml": "",
        }
        self.assertEqual(self.check(files), [
            'qs/a/A.qml:2: import "../gone.js" does not resolve',
            "qs/a/A.qml:5: import qs.nope does not resolve",
            'qs/a/B.js:3: import "gone2.js" does not resolve',
        ])


class GreeterTreeTest(PathsCase):
    ENTRIES = ("lock/", "theme/Style.qml")

    def files(self, **extra):
        return {
            "greeter/shell.qml": 'import "lock/skins"\n',
            "qs/lock/skins/S.qml": "",
            "qs/theme/Style.qml": 'import "Watch.js" as Watch\n',
            "qs/theme/Watch.js": "",
            **extra,
        }

    def test_a_js_file_missing_from_the_list_fails_in_the_greeter_tree_only(self):
        found = self.check(self.files(), greeter_entries=self.ENTRIES)
        self.assertEqual(found, ['qs/theme/Style.qml:1: import "Watch.js" does not resolve (greeter tree; see lib/common/greeter-files.sh)'])

    def test_listing_it_fixes_it(self):
        self.assertEqual(self.check(self.files(), greeter_entries=self.ENTRIES + ("theme/Watch.js",)), [])

    def test_skin_importing_a_folder_the_greeter_does_not_stage_fails(self):
        files = self.files(**{"qs/lock/skins/Bad.qml": "import qs.services\n", "qs/services/Svc.qml": ""})
        found = self.check(files, greeter_entries=self.ENTRIES + ("theme/Watch.js",))
        self.assertEqual(found, ["qs/lock/skins/Bad.qml:1: import qs.services does not resolve (greeter tree; see lib/common/greeter-files.sh)"])

    def test_an_entry_matching_nothing_fails(self):
        found = self.check(self.files(), greeter_entries=self.ENTRIES + ("theme/Watch.js", "gone/", "fonts/*.ttf", "VERSION?"))
        self.assertEqual(found, ["lib/common/greeter-files.sh:1: fonts/*.ttf matches nothing in qs", "lib/common/greeter-files.sh:1: gone/ matches nothing in qs"])


class OutsideRefTest(PathsCase):
    FILES = {"qs/scripts/lock-flag": "", "hypr/lock.sh": 'flag="$HOME/.config/quickshell/scripts/lock-flag"\n'}
    ROWS = [("hypr/lock.sh", "scripts/lock-flag")]

    def test_renamed_target_and_dropped_mention_both_fail(self):
        self.assertEqual(self.check(self.FILES, outside=self.ROWS), [])
        renamed = {"qs/scripts/lock": "", "hypr/lock.sh": self.FILES["hypr/lock.sh"]}
        self.assertEqual(self.check(renamed, outside=self.ROWS), ["hypr/lock.sh:1: names scripts/lock-flag, which is not in qs"])
        dropped = {**self.FILES, "hypr/lock.sh": "flag=x\n"}
        self.assertEqual(self.check(dropped, outside=self.ROWS), ["hypr/lock.sh:1: no longer mentions scripts/lock-flag; update OUTSIDE_REFS in lib/check/steps/qml_paths.py"])


class LiveTreeTest(unittest.TestCase):
    def test_the_repository_passes(self):
        self.assertEqual(qml_paths.run_checks(REPO_DIR), [])


if __name__ == "__main__":
    unittest.main()
