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


if __name__ == "__main__":
    unittest.main()
