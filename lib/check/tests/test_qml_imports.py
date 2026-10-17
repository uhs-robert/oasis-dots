"""Tests the import reader (lib/check/qml_imports.py) on tiny trees."""

import os
import sys
import unittest

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, CHECK_DIR)
import qml_imports  # noqa: E402
from test_qml import TreeCase, write_tree  # noqa: E402


class FolderImportsTest(TreeCase):
    def imports(self, text):
        write_tree(self.root, {"a/File.qml": text})
        return list(qml_imports.folder_imports(self.path("a/File.qml"), self.root))

    def test_qs_root_and_nested(self):
        self.assertEqual(self.imports("import qs\nimport qs.b.c\n"), [(None, self.root), (None, self.path("b/c"))])

    def test_quoted_is_relative_to_the_file(self):
        self.assertEqual(self.imports('import "../b"\n'), [(None, self.path("a") + "/../b")])

    def test_alias(self):
        self.assertEqual(self.imports('import qs.b as B\nimport "c" as C\n'), [("B", self.path("b")), ("C", self.path("a/c"))])

    def test_scripts_skipped(self):
        self.assertEqual(self.imports('import "x.js" as X\nimport "y.mjs" as Y\n'), [])

    def test_two_statements_on_one_line(self):
        self.assertEqual(self.imports('import "b"; import "c"\n'), [(None, self.path("a/b")), (None, self.path("a/c"))])

    def test_version_token(self):
        self.assertEqual(self.imports("import qs.b 1.0 as B\n"), [("B", self.path("b"))])

    def test_other_imports_ignored(self):
        self.assertEqual(self.imports("import QtQuick\nimport qsx.b\n"), [])


class StripCodeTest(unittest.TestCase):
    def strip(self, *lines):
        state = {"in_block": False}
        return [qml_imports.strip_code(line, state) for line in lines]

    def test_comment_markers_inside_strings(self):
        self.assertEqual(self.strip('a: "//x" // y', "b: '/*' + 1"), ['a: "" ', "b: '' + 1"])

    def test_escaped_quote(self):
        self.assertEqual(self.strip(r'a: "x\"y" + z'), ['a: "" + z'])

    def test_block_comment_across_lines(self):
        self.assertEqual(self.strip("a /* b", "c */ d", "e"), ["a ", " d", "e"])


class GreeterEntriesTest(unittest.TestCase):
    def test_reads_the_real_list(self):
        entries = qml_imports.greeter_entries(os.path.dirname(os.path.dirname(CHECK_DIR)))
        self.assertTrue(entries)
        self.assertFalse([entry for entry in entries if "?" in entry or "*" in entry])


class ImportsTest(TreeCase):
    def imports(self, name, text):
        write_tree(self.root, {name: text})
        return list(qml_imports.imports(self.path(name)))

    def test_every_form_with_line_numbers(self):
        text = 'import QtQuick\nimport qs\nimport qs.a.b as B\nimport "../c" as C\nimport "x.js" as X\n'
        self.assertEqual(self.imports("a/F.qml", text), [("qs", "", 2), ("qs", "a/b", 3), ("folder", "../c", 4), ("script", "x.js", 5)])

    def test_dot_import_in_a_js_file(self):
        self.assertEqual(self.imports("F.js", '.pragma library\n.import "y.mjs" as Y\n'), [("script", "y.mjs", 2)])

    def test_comments_do_not_count(self):
        self.assertEqual(self.imports("F.qml", '// import "x.js"\n/* import qs.a\n*/ import qs.b\n'), [("qs", "b", 3)])


class StagedFilesTest(unittest.TestCase):
    def test_folders_globs_optional_and_unmatched(self):
        files = {"a/x.qml", "fonts/F.ttf", "fonts/O.txt", "VERSION"}
        entries = ["a/", "fonts/*.ttf", "VERSION?", "gone?", "missing/"]
        self.assertEqual(qml_imports.staged_files(files, entries), ({"a/x.qml", "fonts/F.ttf", "VERSION"}, ["missing/"]))

    def test_a_glob_follows_bash_pathname_expansion(self):
        files = {"fonts/F.ttf", "fonts/nested/G.ttf", "fonts/.H.ttf", "fonts/OFL-x.txt"}
        staged, _ = qml_imports.staged_files(files, ["fonts/*.ttf", "fonts/OFL-?.txt", "fonts/[!x]*.txt"])
        self.assertEqual(staged, {"fonts/F.ttf", "fonts/OFL-x.txt"})
        self.assertEqual(qml_imports.staged_files(files, ["fonts/.*.ttf"])[0], {"fonts/.H.ttf"})


class KeepStringsTest(unittest.TestCase):
    def test_strings_survive_and_comments_do_not(self):
        state = {"in_block": False}
        self.assertEqual(qml_imports.strip_code('a: "//x" + \'b\' // c', state, keep_strings=True), 'a: "//x" + \'b\' ')


if __name__ == "__main__":
    unittest.main()
