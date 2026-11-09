"""Runs the node test of the board's markdown renderer, so the `plans` check step covers it."""

import os
import shutil
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


@unittest.skipUnless(shutil.which("node"), "the renderer test needs node")
class BoardMarkdownTest(unittest.TestCase):
    def test_renderer(self):
        result = subprocess.run(["node", os.path.join(HERE, "markdown.test.mjs")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
