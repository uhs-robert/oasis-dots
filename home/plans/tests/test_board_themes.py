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

    # Exceptions the generator reports and keeps as the source file has them: no lighter color of the same hue below
    # lightness 0.85 (accents), and no neutral between desert's dim and its text. Each carries a floor, so a real
    # regression still fails.
    LOW = {("desert_dark", "dim"): 4.4, ("desert_dark", "assignee-iris"): 3.0, ("dune_dark", "assignee-iris"): 3.0,
           ("lagoon_dark", "assignee-iris"): 3.0, ("rose_dark", "assignee-iris"): 3.0,
           ("cactus_dark", "assignee-iris"): 3.0, ("canyon_dark", "assignee-iris"): 3.0}

    def check_floor(self, role_filter):
        for key, roles in board_themes().items():
            for role in (role for role in roles if role_filter(role)):
                ratio = gen_board_themes.contrast(roles[role], roles["card"])
                if (key, role) in self.LOW:
                    self.assertGreaterEqual(ratio, self.LOW[(key, role)], f"{key} {role} fell to {ratio:.2f}:1")
                    self.assertLess(ratio, 4.5, f"{key} {role} now passes: drop it from LOW")
                else:
                    self.assertGreaterEqual(ratio, 4.5, f"{key} {role} on card is {ratio:.2f}:1")

    def test_text_and_dim_reach_the_contrast_floor_on_cards(self):
        self.check_floor(lambda role: role in ("text", "dim"))

    def test_assignee_accents_reach_the_contrast_floor_on_cards(self):
        self.check_floor(lambda role: role.startswith("assignee-"))

    def test_dim_differs_from_text(self):
        for key, roles in board_themes().items():
            self.assertNotEqual(roles["dim"], roles["text"], key)

    def test_borders_do_not_vanish_into_cards_or_the_error_background(self):
        for key, roles in board_themes().items():
            self.assertNotIn(roles["line"], (roles["card"], roles["error-bg"]), key)

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
        picked = gen_board_themes.lighter_neutral(values, "#404040", "#000000")
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

    def test_an_empty_file_keeps_the_previous_theme(self):
        # switch.lua and init.lua truncate the file before they write the new name.
        with tempfile.TemporaryDirectory() as state, mock.patch.dict(os.environ, {"XDG_STATE_HOME": state}):
            os.makedirs(os.path.join(state, "hypr"))
            with open(os.path.join(state, "hypr", "theme"), "w", encoding="utf-8"):
                pass
            self.assertEqual(server.desktop_theme("moonlight_dark"), "moonlight_dark")
            self.assertIsNone(server.desktop_theme())

    def test_the_board_json_carries_it_and_survives_a_missing_file(self):
        with tempfile.TemporaryDirectory() as state, mock.patch.dict(os.environ, {"XDG_STATE_HOME": state}):
            board = server.Board(os.path.join(state, "roots.json"))
            self.assertIn("desktop_theme", board.as_json())
            self.assertIsNone(board.as_json()["desktop_theme"])


class DesktopThemeWatchTest(unittest.TestCase):
    """A desktop theme change while the board is open bumps the version, so the event stream wakes the page."""

    def test_the_version_follows_the_state_file(self):
        with tempfile.TemporaryDirectory() as state, mock.patch.dict(os.environ, {"XDG_STATE_HOME": state}):
            path = os.path.join(state, "hypr", "theme")
            board = server.Board(os.path.join(state, "roots.json"))
            board.poll(rescan=True)
            version = board.version
            board.poll()
            self.assertEqual(board.version, version, "no change, no bump")

            os.makedirs(os.path.dirname(path))
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("oasis_night\n")
            board.poll()
            self.assertGreater(board.version, version, "a file that appears bumps")
            self.assertEqual(board.as_json()["desktop_theme"], "night_dark")
            version = board.version
            board.poll()
            self.assertEqual(board.version, version, "the same theme does not bump again")

            with open(path, "w", encoding="utf-8") as handle:
                handle.write("oasis_moonlight\n")
            board.poll()
            self.assertGreater(board.version, version, "a changed theme bumps")
            self.assertEqual(board.as_json()["desktop_theme"], "moonlight_dark")
            version = board.version

            with open(path, "w", encoding="utf-8"):
                pass
            board.poll()
            self.assertEqual(board.as_json()["desktop_theme"], "moonlight_dark", "a truncated file keeps the theme")
            self.assertEqual(board.version, version, "and does not bump")

            os.remove(path)
            board.poll()
            self.assertGreater(board.version, version, "a file that disappears bumps")
            self.assertIsNone(board.as_json()["desktop_theme"])


@unittest.skipUnless(shutil.which("node"), "the theme test needs node")
class ThemeLogicTest(unittest.TestCase):
    def test_theme_choice(self):
        result = subprocess.run(["node", os.path.join(HERE, "theme.test.mjs")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
