"""frame-app-corners: each screen-frame corner style gives the expected yazi border and Firefox CSS."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SCRIPT = os.path.join(ROOT, "home/quickshell/.config/quickshell/scripts/frame-app-corners")
gen = SourceFileLoader("frame_app_corners", SCRIPT).load_module()


def frame(corner, radius=12, on=True):
    return {"on": on, "corner": corner, "radius": radius}


class YaziBorder(unittest.TestCase):
    def test_each_corner_style(self):
        for corner, expected in [("round", "rounded"), ("square", "plain"), ("pixel", "plain"), ("chamfer", "plain")]:
            self.assertEqual(gen.yazi_border(frame(corner)), expected, corner)

    def test_unknown_or_no_corner_is_plain(self):
        self.assertEqual(gen.yazi_border(frame("blob")), "plain")
        self.assertEqual(gen.yazi_border({"on": False, "corner": "", "radius": 0}), "plain")

    def test_corner_applies_with_the_frame_off(self):
        for corner, expected in [("round", "rounded"), ("square", "plain"), ("pixel", "plain"), ("chamfer", "plain")]:
            self.assertEqual(gen.yazi_border(frame(corner, on=False)), expected, corner)


class FirefoxCss(unittest.TestCase):
    def test_round_sets_the_radius_only(self):
        css = gen.firefox_css(frame("round", 14))
        self.assertIn("--tf-rounding: 14px;", css)
        self.assertNotIn("clip-path", css)

    def test_square_and_pixel_have_no_rounding(self):
        for corner in ("square", "pixel"):
            css = gen.firefox_css(frame(corner, 8))
            self.assertIn("--tf-rounding: 0px;", css, corner)
            self.assertNotIn("clip-path", css, corner)

    def test_chamfer_bevels_textfox_panes_only(self):
        css = gen.firefox_css(frame("chamfer", 12))
        self.assertIn("--tf-rounding: 0px;", css)
        # A clip or mask would cut the URL bar's results and TextFox's title labels, so the bevel is only painted.
        self.assertNotIn("clip-path", css)
        self.assertNotIn("mask", css)
        for block in css.split("}"):
            if "::after" in block:
                self.assertEqual([x.strip() for x in block.split("{")[0].split(",")], [p + "::after" for p in gen.TEXTFOX_PANES])
        self.assertIn("var(--tf-bevel-line)", css)
        self.assertIn("pointer-events: none;", css)
        self.assertIn("position: relative;", css)
        self.assertIn("findbar {\n  padding: 8px !important;", css)
        self.assertIn("--tf-bevel-line: var(--tf-accent);", css)
        self.assertIn("#nav-bar:hover", css)
        # The stroke must fade with TextFox's border (border-color var(--tf-border-transition)), not jump.
        self.assertIn('@property --tf-bevel-line {\n  syntax: "<color>";', css)
        self.assertIn("transition: --tf-bevel-line var(--tf-border-transition);", css)
        self.assertIn("#nav-bar:focus", css)
        cover = css.split("--tf-bevel-outside: var(--toolbox-background-color")[0].rsplit("\n\n", 1)[1]
        covered = [x.strip() for x in cover.split("*/")[-1].split("{")[0].split(",")]
        self.assertEqual(covered, ["#nav-bar", "#PersonalToolbar", "#TabsToolbar", "box#vertical-tabs", ".buttons-wrapper"])
        for pane in ("#sidebar-box", "#tabbrowser-tabbox", "findbar"):
            self.assertNotIn(pane, covered)

    def test_round_has_no_bevel_rules(self):
        css = gen.firefox_css(frame("round", 12))
        for text in ("pointer-events", "position: relative", "padding: 8px"):
            self.assertNotIn(text, css)

    def test_zero_radius_chamfer_does_not_clip(self):
        self.assertNotIn("clip-path", gen.firefox_css(frame("chamfer", 0)))

    def test_no_corner_leaves_firefox_alone(self):
        self.assertNotIn("--tf-rounding", gen.firefox_css({"on": False, "corner": "", "radius": 0}))
        self.assertNotIn("--tf-rounding", gen.firefox_css({"on": False}))

    def test_corner_applies_with_the_frame_off(self):
        self.assertIn("--tf-rounding: 14px;", gen.firefox_css(frame("round", 14, on=False)))
        self.assertIn("--tf-rounding: 0px;", gen.firefox_css(frame("square", 8, on=False)))
        self.assertIn("--tf-bevel-line", gen.firefox_css(frame("chamfer", 12, on=False)))


class Run(unittest.TestCase):
    def run_into(self, tmp, data):
        path = os.path.join(tmp, "frame.json")
        with open(path, "w") as f:
            json.dump(data, f)
        ff = os.path.join(tmp, "ff/chrome")
        os.makedirs(ff)
        result = subprocess.run([sys.executable, "-I", SCRIPT, path, "--yazi-dir", os.path.join(tmp, "yazi"), "--firefox-dirs", ff], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return open(os.path.join(tmp, "yazi/frame-border.lua")).read(), open(os.path.join(ff, "frame.css")).read()

    def test_files_follow_the_corner(self):
        with tempfile.TemporaryDirectory() as tmp:
            lua, css = self.run_into(tmp, frame("round", 10))
            self.assertEqual(lua, 'return "rounded"\n')
            self.assertIn("--tf-rounding: 10px;", css)

    def test_files_follow_the_corner_with_the_frame_off(self):
        with tempfile.TemporaryDirectory() as tmp:
            lua, css = self.run_into(tmp, frame("round", 10, on=False))
            self.assertEqual(lua, 'return "rounded"\n')
            self.assertIn("--tf-rounding: 10px;", css)

    def test_rerun_follows_a_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.run_into(tmp, frame("round", 10))
            path = os.path.join(tmp, "frame.json")
            with open(path, "w") as f:
                json.dump(frame("chamfer", 12), f)
            subprocess.run([sys.executable, "-I", SCRIPT, path, "--yazi-dir", os.path.join(tmp, "yazi"), "--firefox-dirs", os.path.join(tmp, "ff/chrome")], check=True)
            self.assertEqual(open(os.path.join(tmp, "yazi/frame-border.lua")).read(), 'return "plain"\n')
            self.assertIn("--tf-bevel-line", open(os.path.join(tmp, "ff/chrome/frame.css")).read())

    def test_missing_input_fails_without_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run([sys.executable, "-I", SCRIPT, os.path.join(tmp, "none.json"), "--yazi-dir", tmp + "/y", "--firefox-dirs"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertFalse(os.path.exists(tmp + "/y"))

    def test_malformed_json_fails_without_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "frame.json")
            with open(path, "w") as f:
                f.write("{not json")
            result = subprocess.run([sys.executable, "-I", SCRIPT, path, "--yazi-dir", tmp + "/y", "--firefox-dirs"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("cannot read", result.stderr)
            self.assertFalse(os.path.exists(tmp + "/y"))

    def test_chrome_dirs_come_from_the_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "frame.json")
            with open(path, "w") as f:
                json.dump(frame("round", 10), f)
            env = dict(os.environ, FIREFOX_CHROME_DIRS=f"{tmp}/a:{tmp}/b")
            subprocess.run([sys.executable, "-I", SCRIPT, path, "--yazi-dir", tmp + "/y"], env=env, check=True)
            for name in ("a", "b"):
                self.assertTrue(os.path.exists(f"{tmp}/{name}/frame.css"), name)

    def test_profile_without_chrome_dir_gets_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(tmp + "/.mozilla/firefox/abc.default-release")
            os.makedirs(tmp + "/.local/state/quickshell")
            with open(tmp + "/.local/state/quickshell/frame.json", "w") as f:
                json.dump(frame("round", 10), f)
            env = {"HOME": tmp, "PATH": os.environ["PATH"]}
            subprocess.run([sys.executable, "-I", SCRIPT], env=env, check=True)
            self.assertIn("--tf-rounding: 10px;", open(tmp + "/.mozilla/firefox/abc.default-release/chrome/frame.css").read())


class YaziInit(unittest.TestCase):
    """init.lua reads the generated border from $XDG_CONFIG_HOME and falls back to plain when it is missing."""

    LUA = os.path.join(ROOT, "home/yazi/.config/yazi/init.lua")

    def border_after_init(self, env):
        # Run only the frame-border head of init.lua, with full-border stubbed to print its setup value.
        head = open(self.LUA).read().split("-- Fuse Archive")[0]
        stub = 'package.preload["full-border"] = function() return { setup = function(_, o) print(o.set) end } end\n'
        result = subprocess.run(["lua", "-e", stub + head], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def setUp(self):
        if subprocess.run(["which", "lua"], capture_output=True).returncode != 0:
            self.skipTest("no lua interpreter")

    def test_reads_xdg_config_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(tmp + "/yazi")
            with open(tmp + "/yazi/frame-border.lua", "w") as f:
                f.write('return "rounded"\n')
            self.assertEqual(self.border_after_init({"HOME": "/nonexistent", "XDG_CONFIG_HOME": tmp}), "rounded")

    def test_missing_file_falls_back_to_plain(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.border_after_init({"HOME": tmp, "XDG_CONFIG_HOME": tmp}), "plain")

    def test_unset_home_still_falls_back(self):
        self.assertEqual(self.border_after_init({}), "plain")


if __name__ == "__main__":
    unittest.main()
