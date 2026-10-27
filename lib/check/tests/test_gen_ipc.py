"""lib/docs/gen-ipc: fixture handlers render the expected table with action ids joined, --check catches a stale or
unmarked doc, --write is idempotent, and the real Quickshell README is current."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SCRIPT = os.path.join(ROOT, "lib/docs/gen-ipc")
QS = "home/quickshell/.config/quickshell"

POPUP = """IpcHandler {
    target: "popup"
    function open(name: string): void {}
    function step(delta: int,  mode: list<string>): void {}
    function helper(x) { return x }
    function state(): string { return "closed" }
}
"""
OSD = 'IpcHandler { target: "osd"; function state(): string { return "" } }\n'
ACTIONS = {"actions": [
    {"id": "popup.open", "perform": {"kind": "ipc", "target": "popup", "function": "open"}},
    {"id": "popup.show", "perform": {"kind": "ipc", "target": "popup", "function": "open"}},
    {"id": "app.run", "perform": {"kind": "lua"}},
]}
TABLE = (
    "| Target | Signature | Action id |\n"
    "| --- | --- | --- |\n"
    "| `osd` | `state(): string` |  |\n"
    "| `popup` | `open(name: string): void` | `popup.open, popup.show` |\n"
    "| `popup` | `step(delta: int, mode: list<string>): void` |  |\n"
    "| `popup` | `state(): string` |  |\n"
)


def doc_with(body):
    return f"# Quickshell\n\nhand written\n\n<!-- BEGIN generated -->\n{body}<!-- END generated -->\n\nnotes\n"


def load():
    return SourceFileLoader("gen_ipc", SCRIPT).load_module()


class Fixture(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        for name, text in ((f"{QS}/Popup.qml", POPUP), (f"{QS}/Osd.qml", OSD)):
            full = os.path.join(self.dir, name)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as file:
                file.write(text)
        subprocess.run(("git", "init", "-q"), cwd=self.dir, check=True)
        self.actions = os.path.join(self.dir, "actions.json")
        with open(self.actions, "w") as file:
            json.dump(ACTIONS, file)
        self.doc = os.path.join(self.dir, "README.md")

    def put(self, text):
        with open(self.doc, "w") as file:
            file.write(text)

    def run_gen(self, mode):
        return subprocess.run([sys.executable, "-B", SCRIPT, mode, "--actions", self.actions, "--doc", self.doc, "--root", self.dir], capture_output=True, text=True)

    def test_rows_are_targets_alphabetical_signatures_in_source_order_ids_joined_and_helpers_dropped(self):
        self.put(doc_with("old\n"))
        self.assertEqual(self.run_gen("--write").returncode, 0)
        with open(self.doc) as file:
            self.assertEqual(file.read(), doc_with(TABLE))

    def test_write_is_idempotent(self):
        self.put(doc_with("old\n"))
        self.run_gen("--write")
        with open(self.doc) as file:
            first = file.read()
        self.assertEqual(self.run_gen("--write").returncode, 0)
        with open(self.doc) as file:
            self.assertEqual(file.read(), first)
        self.assertEqual(self.run_gen("--check").returncode, 0)

    def test_a_stale_block_fails_with_the_regenerate_hint(self):
        self.put(doc_with(TABLE.replace("osd", "osdx")))
        done = self.run_gen("--check")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("just docs-gen", done.stdout + done.stderr)

    def test_a_hand_edit_outside_the_block_passes(self):
        self.put(doc_with(TABLE).replace("notes", "other notes"))
        self.assertEqual(self.run_gen("--check").returncode, 0)

    def test_missing_or_duplicate_markers_fail(self):
        for text in ("# no markers\n", doc_with(TABLE) + doc_with(TABLE)):
            self.put(text)
            self.assertNotEqual(self.run_gen("--check").returncode, 0)


class Splice(unittest.TestCase):
    def test_splice_replaces_only_the_marked_block(self):
        self.assertEqual(load().splice(doc_with("old\n"), TABLE), doc_with(TABLE))


class RealTree(unittest.TestCase):
    def test_the_quickshell_readme_is_current(self):
        done = subprocess.run([sys.executable, "-B", SCRIPT, "--check"], capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)


if __name__ == "__main__":
    unittest.main()
