"""The board's themes: the generated blocks match oasis.nvim, every theme reads well, and the server reports the desktop theme."""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from unittest import mock

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.dirname(HERE)
LIB = os.path.join(PACKAGE, ".local", "lib", "plans")
sys.path.insert(0, LIB)
from plans import server  # noqa: E402
import gen_board_themes  # noqa: E402

BOARD = gen_board_themes.BOARD
THEME_RULE = re.compile(r'html\[data-theme="(\w+)"\] \{([^}]*)\}')


def board_themes():
    with open(BOARD, encoding="utf-8") as handle:
        text = handle.read()
    return {key: dict(re.findall(r"--([\w-]+): ([^;]+);", body)) for key, body in THEME_RULE.findall(text)}


class GeneratedThemesTest(unittest.TestCase):
    def test_every_dark_theme_is_there_with_every_role(self):
        themes = board_themes()
        self.assertEqual(len(themes), 16)
        self.assertIn("night_dark", themes)
        for key, roles in themes.items():
            expected = {*gen_board_themes.ROLES, "overlay"}
            self.assertEqual(set(roles), expected, key)

    def test_text_and_dim_reach_the_contrast_floor_on_cards(self):
        for key, roles in board_themes().items():
            for role in ("text", "dim"):
                ratio = gen_board_themes.contrast(roles[role], roles["card"])
                self.assertGreaterEqual(ratio, 4.5, f"{key} {role} on card is {ratio:.2f}:1")

    def test_night_matches_the_static_fallback(self):
        with open(BOARD, encoding="utf-8") as handle:
            root = re.search(r":root \{([^}]*)\}", handle.read()).group(1)
        fallback = dict(re.findall(r"--([\w-]+): ([^;]+);", root))
        night = board_themes()["night_dark"]
        for role, value in fallback.items():
            self.assertEqual(night[role], value, role)

    def test_overlay_comes_from_the_theme_shadow(self):
        self.assertEqual(board_themes()["night_dark"]["overlay"], "rgba(5, 10, 16, 0.6)")

    def test_a_low_contrast_dim_is_raised_to_a_lighter_neutral(self):
        values = {"fg-dim": "#404040", "fg-muted": "#909090", "fg-core": "#FFFFFF", "syntax-bracket": "#404040"}
        picked = gen_board_themes.lighter_neutral(values, "#000000", "#404040")
        self.assertEqual(picked, "#909090")

    def test_board_matches_a_fresh_generate_when_oasis_is_checked_out(self):
        oasis = gen_board_themes.default_oasis_dir()
        if not os.path.isdir(os.path.join(oasis, "extras", "css", "themes", "dark")):
            self.skipTest("repos/oasis.nvim is not checked out")
        with open(BOARD, encoding="utf-8") as handle:
            current = handle.read()
        self.assertEqual(gen_board_themes.generate(oasis, current), current,
                         "board.html is stale: run home/plans/.local/lib/plans/gen_board_themes.py")


class DesktopThemeTest(unittest.TestCase):
    def read_with(self, content):
        with tempfile.TemporaryDirectory() as state:
            if content is not None:
                os.makedirs(os.path.join(state, "hypr"))
                with open(os.path.join(state, "hypr", "theme"), "w", encoding="utf-8") as handle:
                    handle.write(content)
            with mock.patch.dict(os.environ, {"XDG_STATE_HOME": state}):
                return server.desktop_theme()

    def test_oasis_name_maps_to_a_dark_key(self):
        self.assertEqual(self.read_with("oasis_moonlight\n"), "moonlight_dark")

    def test_a_missing_state_file_is_none(self):
        self.assertIsNone(self.read_with(None))

    def test_a_foreign_or_empty_name_is_none(self):
        self.assertIsNone(self.read_with("gruvbox\n"))
        self.assertIsNone(self.read_with(""))

    def test_the_board_json_carries_it_and_survives_a_missing_file(self):
        with tempfile.TemporaryDirectory() as state, mock.patch.dict(os.environ, {"XDG_STATE_HOME": state}):
            board = server.Board(os.path.join(state, "roots.json"))
            self.assertIn("desktop_theme", board.as_json())
            self.assertIsNone(board.as_json()["desktop_theme"])


@unittest.skipUnless(shutil.which("node"), "the theme test needs node")
class ThemeLogicTest(unittest.TestCase):
    def test_theme_choice(self):
        result = subprocess.run(["node", os.path.join(HERE, "theme.test.mjs")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
