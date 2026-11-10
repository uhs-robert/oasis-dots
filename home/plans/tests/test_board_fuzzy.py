"""Runs the node tests of the board's repo matcher and owner colors, so the `plans` check step covers it."""

import os
import shutil
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


@unittest.skipUnless(shutil.which("node"), "the matcher test needs node")
class BoardFuzzyTest(unittest.TestCase):
    def test_matcher(self):
        result = subprocess.run(["node", os.path.join(HERE, "fuzzy.test.mjs")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_owner_colors(self):
        result = subprocess.run(["node", os.path.join(HERE, "owner_color.test.mjs")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
