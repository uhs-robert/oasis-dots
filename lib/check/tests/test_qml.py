"""Tests the qmllint step's pure parts (lib/check/steps/qml.py) on tiny trees; none of them runs qmllint."""

import os
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(CHECK_DIR, "steps"))
import qml  # noqa: E402


def write_tree(root, files):
    for path, text in files.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as file:
            file.write(text)


class TreeCase(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = os.path.realpath(scratch.name)

    def path(self, *parts):
        return os.path.join(self.root, *parts)


class FolderImportsTest(TreeCase):
    def imports(self, text):
        write_tree(self.root, {"a/File.qml": text})
        return list(qml.folder_imports(self.path("a/File.qml"), self.root))

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


class ReachedDirsTest(TreeCase):
    def test_chain_cycle_lowercase_and_missing(self):
        write_tree(self.root, {
            "shell.qml": "import qs.a\nimport qs.missing\n",
            "a/A.qml": "import qs.b\n",
            "b/B.qml": "import qs.a\n",
            "b/lower.qml": "import qs.c\n",
            "c/C.qml": "",
        })
        self.assertEqual(qml.reached_dirs(self.root), [self.root, self.path("a"), self.path("b")])


class WriteQmldirsTest(TreeCase):
    def read(self, *parts):
        with open(self.path(*parts, "qmldir")) as file:
            return file.read()

    def test_modules_singletons_and_skips(self):
        write_tree(self.root, {
            "Root.qml": "",
            "a/b/Single.qml": "pragma Singleton\nimport QtQuick\n",
            "a/b/Plain.qml": "",
            "empty/lower.qml": "",
            "kept/K.qml": "",
            "kept/qmldir": "module custom\n",
        })
        dirs = [self.root, self.path("a/b"), self.path("empty"), self.path("kept")]
        qml.write_qmldirs(dirs, self.root)
        self.assertEqual(self.read(), "module qs\nRoot 1.0 Root.qml\n")
        self.assertEqual(self.read("a/b"), "module qs.a.b\nPlain 1.0 Plain.qml\nsingleton Single 1.0 Single.qml\n")
        self.assertFalse(os.path.exists(self.path("empty/qmldir")))
        self.assertEqual(self.read("kept"), "module custom\n")


class StripCodeTest(unittest.TestCase):
    def strip(self, *lines):
        state = {"in_block": False}
        return [qml.strip_code(line, state) for line in lines]

    def test_comment_markers_inside_strings(self):
        self.assertEqual(self.strip('a: "//x" // y', "b: '/*' + 1"), ['a: "" ', "b: '' + 1"])

    def test_escaped_quote(self):
        self.assertEqual(self.strip(r'a: "x\"y" + z'), ['a: "" + z'])

    def test_block_comment_across_lines(self):
        self.assertEqual(self.strip("a /* b", "c */ d", "e"), ["a ", " d", "e"])


class FirstUnregisteredUseTest(TreeCase):
    def use(self, text, types=("Foo", "FooBar"), singletons=("Single",)):
        write_tree(self.root, {"File.qml": text})
        return qml.first_unregistered_use(self.path("File.qml"), list(types), list(singletons))

    def test_patterns(self):
        self.assertEqual(self.use("Item {\n    Foo {}\n}\n"), (2, "Foo"))
        self.assertEqual(self.use("    property Foo f\n"), (1, "Foo"))
        self.assertEqual(self.use("    required property list<FooBar> fs\n"), (1, "FooBar"))
        self.assertEqual(self.use("    x: Single.value\n"), (1, "Single"))

    def test_instance_tried_before_declared(self):
        self.assertEqual(self.use("property FooBar a: Foo {}\n"), (1, "Foo"))

    def test_comments_strings_and_members_ignored(self):
        self.assertIsNone(self.use('// Foo {}\n/* Foo {\n*/ s: "Foo {"\nx.Foo {}\nSingleX.y\n'))

    def test_prefix_is_not_a_use(self):
        self.assertIsNone(self.use("FooBaz {}\n", types=("Foo",)))
        self.assertEqual(self.use("FooBar {}\n", types=("Foo", "FooBar")), (1, "FooBar"))


class PruneQmltypesTest(TreeCase):
    def test_stub_with_concrete_twin_dropped_and_sole_stub_kept(self):
        write_tree(self.root, {
            "Quickshell/a.qmltypes": (
                "Module {\n"
                "    Component {\n"
                '        name: "Real"\n'
                "    }\n"
                '    Component { isTypeOpaque: true; name: "Real" }\n'
                '    Component { isTypeOpaque: true; name: "Lonely" }\n'
                "}\n"
            ),
            "Quickshell/b/b.qmltypes": '    Component { isTypeOpaque: true; name: "Real" }\n',
        })
        qml.prune_qmltypes(self.root)
        with open(self.path("Quickshell/a.qmltypes")) as file:
            self.assertEqual(file.read(), (
                "Module {\n    Component {\n        name: \"Real\"\n    }\n"
                '    Component { isTypeOpaque: true; name: "Lonely" }\n}\n'
            ))
        with open(self.path("Quickshell/b/b.qmltypes")) as file:
            self.assertEqual(file.read(), "")


def report(*warnings):
    return [{"files": [{"filename": "/s/F.qml", "warnings": list(warnings)}]}]


def finding(**warning):
    found = qml.failing_findings(report({"line": 1, "column": 2, **warning}))
    return found[0] if found else None


class FailingFindingsTest(unittest.TestCase):
    CASES = [
        ({"id": "syntax", "message": "Expected token"}, "/s/F.qml:1:2: Expected token [syntax]"),
        ({"id": "incompatible-type", "message": "Cannot assign x"}, "/s/F.qml:1:2: Cannot assign x [incompatible-type]"),
        ({"id": "incompatible-type", "message": "Cannot assign binding of type int to Edges::Flags"}, None),
        ({"id": "uncreatable-type", "message": "Type PanelWindow is not creatable"}, None),
        ({"id": "missing-property", "message": 'Member "x" not found on type "QObject"'}, None),
        ({"id": "missing-property", "message": "Loader::item with type QQuickItem"}, None),
        (
            {"id": "missing-property", "message": 'Could not find property "colr".', "suggestions": [
                {"message": "Other"}, {"message": 'Did you mean "color"?'}, {"message": 'Did you mean "c"?'}]},
            '/s/F.qml:1:2: Could not find property "colr". Did you mean "color"? [missing-property]',
        ),
        ({"id": "unqualified", "message": "Unqualified access"}, "/s/F.qml:1:2: Unqualified access [unqualified]"),
        ({"id": "unqualified", "message": "Unqualified access", "suggestions": [{"replacement": "root."}]}, None),
        ({"id": "unqualified", "message": "Unqualified access", "suggestions": [{"documentEdits": [{"replacement": "pragma ComponentBehavior: Bound"}]}]}, None),
        ({"id": "unqualified", "message": "Unqualified access", "suggestions": [{"message": "Use root", "replacement": "root"}]}, "/s/F.qml:1:2: Unqualified access [unqualified]"),
        ({"id": "unqualified", "message": "Something else"}, None),
        ({"id": "unused-imports", "message": "Unused import"}, None),
    ]

    def test_cases(self):
        for warning, expected in self.CASES:
            with self.subTest(warning=warning):
                self.assertEqual(finding(**warning), expected)

    def test_missing_position_prints_null(self):
        found = qml.failing_findings(report({"id": "import", "message": "m"}))
        self.assertEqual(found, ["/s/F.qml:null:null: m [import]"])

    def test_bad_shape_keeps_earlier_findings(self):
        documents = [{"files": [{"filename": "F", "warnings": [{"id": "syntax", "message": "m", "line": 1, "column": 1}]}, {}]}]
        with self.assertRaises(qml.ReportShapeError) as raised:
            qml.failing_findings(documents)
        self.assertEqual(raised.exception.findings, ["F:1:1: m [syntax]"])

    def test_documents_back_to_back(self):
        self.assertEqual(qml.parse_documents(b'{"files": [1]}\n{"files": []}\n'), [{"files": [1]}, {"files": []}])
        self.assertIsNone(qml.parse_documents(b'{"files": [1]} {'))


class RelabelTest(unittest.TestCase):
    def test_stage_path_replaced_as_a_string(self):
        self.assertEqual(qml.relabel("/t/a.b/shell/F.qml: in /t/a.b/shell/x", "/t/a.b/shell", "repo"), "repo/F.qml: in repo/x")
        self.assertEqual(qml.relabel("/t/aXb/shell/F.qml", "/t/a.b/shell", "repo"), "/t/aXb/shell/F.qml")


class GreeterEntriesTest(unittest.TestCase):
    def test_reads_the_real_list(self):
        entries = qml.greeter_entries(os.path.dirname(os.path.dirname(CHECK_DIR)))
        self.assertTrue(entries)
        self.assertFalse([entry for entry in entries if "?" in entry or "*" in entry])


if __name__ == "__main__":
    unittest.main()
