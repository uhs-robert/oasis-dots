"""lib/docs/gen-keybinds: a fixture dump renders the expected table, --check catches a stale or unmarked doc, and the
real docs/keybinds.md is current."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SCRIPT = os.path.join(ROOT, "lib/docs/gen-keybinds")

# Registration order within a submap; "Go" is registered before "Apps" and "global" comes last, as the keymaps load.
DUMP = (
    "Go\tG\tgo.home\tHome\tpress\t-\n"
    "Apps\tT\tterminal.open\tTerminal\tpress\t-\n"
    "Go\tH\t-\tHalf | page\tpress\t-\n"
    "global\tSUPER + X\twindow.close\tClose window\tpress\t-\n"
    "Apps\tB\tapps.browser\tBrowser\tpress\t-\n"
    "global\tSUPER + A\t-\t\trelease\t-\n"
)
TABLE = (
    "| Key | On | Submap | Label | Id |\n"
    "| --- | --- | --- | --- | --- |\n"
    "| `SUPER + X` | press | global | Close window | `window.close` |\n"
    "| `SUPER + A` | release | global |  |  |\n"
    "| `T` | press | Apps | Terminal | `terminal.open` |\n"
    "| `B` | press | Apps | Browser | `apps.browser` |\n"
    "| `G` | press | Go | Home | `go.home` |\n"
    "| `H` | press | Go | Half \\| page |  |\n"
)


def load():
    return SourceFileLoader("gen_keybinds", SCRIPT).load_module()


def doc_with(body):
    return f"# Keybinds\n\nhand written\n\n<!-- BEGIN generated -->\n{body}<!-- END generated -->\n"


def run(*args):
    return subprocess.run([sys.executable, "-B", SCRIPT, *args], capture_output=True, text=True, cwd=ROOT)


class Render(unittest.TestCase):
    def test_global_first_then_submaps_alphabetically_keys_in_registration_order(self):
        self.assertEqual(load().render(load().parse_dump(DUMP)), TABLE)

    def test_splice_replaces_only_the_marked_block(self):
        gen = load()
        out = gen.splice(doc_with("old\n"), TABLE)
        self.assertEqual(out, doc_with(TABLE))

    def test_missing_markers_raise(self):
        gen = load()
        with self.assertRaises(gen.GenError):
            gen.splice("# no markers\n", TABLE)


class Passthrough(unittest.TestCase):
    def test_a_transparent_bind_is_not_rendered(self):
        gen = load()
        rows = gen.parse_dump("Bar\tSLASH\t-\t\tpress\ttransparent\nBar\tA\tbar.a\tA\tpress\t-\n")
        self.assertEqual([row[1] for row in rows], ["A"])


class WhichKeyToggle(unittest.TestCase):
    def test_the_unlabelled_which_key_toggle_gets_a_label(self):
        gen = load()
        rows = gen.parse_dump("Go\tSHIFT + SLASH\t-\t\tpress\t-\nGo\tSHIFT + A\t-\t\tpress\t-\n")
        self.assertEqual([row[3] for row in rows], ["Toggle which-key help", ""])


class Cells(unittest.TestCase):
    def test_pipes_are_escaped_and_whitespace_collapsed_in_label_and_id(self):
        gen = load()
        table = gen.render(gen.parse_dump("Go\tK\t a|b \t Two \u00a0 lines \tpress\t-\n"))
        row = table.splitlines()[2]
        self.assertEqual(row, "| `K` | press | Go | Two lines | `a\\|b` |")
        self.assertEqual(len(table.splitlines()), 3)

    def test_a_press_and_a_release_on_one_key_are_distinct_rows(self):
        gen = load()
        table = gen.render(gen.parse_dump("Cursor\tE\tcursor.scroll\tUp\tpress\t-\nCursor\tE\tcursor.scroll_stop\t\trelease\t-\n"))
        rows = table.splitlines()[2:]
        self.assertEqual(len(set(rows)), 2)


class Check(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        self.dump = os.path.join(self.dir, "dump.tsv")
        with open(self.dump, "w") as file:
            file.write(DUMP)
        self.doc = os.path.join(self.dir, "keybinds.md")

    def put(self, text):
        with open(self.doc, "w") as file:
            file.write(text)

    def args(self, mode):
        return [mode, "--dump", self.dump, "--doc", self.doc]

    def test_write_then_check_passes(self):
        self.put(doc_with("old\n"))
        self.assertEqual(run(*self.args("--write")).returncode, 0)
        self.assertEqual(run(*self.args("--check")).returncode, 0)
        with open(self.doc) as file:
            self.assertEqual(file.read(), doc_with(TABLE))

    def test_hand_edit_inside_the_markers_fails(self):
        self.put(doc_with(TABLE.replace("Terminal", "Term")))
        done = run(*self.args("--check"))
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("just docs-gen", done.stdout + done.stderr)

    def test_missing_markers_fail(self):
        self.put("# Keybinds\n\nno markers\n")
        self.assertNotEqual(run(*self.args("--check")).returncode, 0)


@unittest.skipUnless(shutil.which("lua"), "needs lua")
class RealFile(unittest.TestCase):
    def test_table_comes_from_the_default_config_only(self):
        gen = load()
        rows = gen.parse_dump(gen.run_dump())
        # Go gets a "1" row only on a machine with a monitor; the dump's synthetic three-monitor variant must not leak in.
        self.assertEqual([row for row in rows if row[0] == "Go" and row[1] in ("1", "2", "3")], [])
        self.assertEqual(len(rows), len(set(rows)))

    def test_docs_keybinds_is_current(self):
        done = run("--check")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)


if __name__ == "__main__":
    unittest.main()
