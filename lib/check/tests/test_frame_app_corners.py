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


def frame(corner, radius=12, step=0):
    return {"on": True, "corner": corner, "radius": radius, "step": step}


class YaziBorder(unittest.TestCase):
    def test_each_corner_style(self):
        for corner, expected in [("round", "rounded"), ("square", "plain"), ("pixel", "plain"), ("chamfer", "plain")]:
            self.assertEqual(gen.yazi_border(frame(corner)), expected, corner)

    def test_frame_off_or_unknown_is_plain(self):
        self.assertEqual(gen.yazi_border({"on": False, "corner": "round"}), "plain")
        self.assertEqual(gen.yazi_border(frame("blob")), "plain")


class FirefoxCss(unittest.TestCase):
    def test_round_sets_the_radius_only(self):
        css = gen.firefox_css(frame("round", 14))
        self.assertIn("--tf-rounding: 14px;", css)
        self.assertNotIn("clip-path", css)

    def test_square_and_pixel_have_no_rounding(self):
        for corner in ("square", "pixel"):
            css = gen.firefox_css(frame(corner, 8, 2))
            self.assertIn("--tf-rounding: 0px;", css, corner)
            self.assertNotIn("clip-path", css, corner)

    def test_chamfer_clips_with_the_radius(self):
        css = gen.firefox_css(frame("chamfer", 12))
        self.assertIn("--tf-rounding: 0px;", css)
        self.assertIn("polygon(12px 0, calc(100% - 12px) 0, 100% 12px", css)
        self.assertIn("clip-path: var(--tf-frame-clip);", css)

    def test_zero_radius_chamfer_does_not_clip(self):
        self.assertNotIn("clip-path", gen.firefox_css(frame("chamfer", 0)))

    def test_frame_off_leaves_firefox_alone(self):
        self.assertNotIn("--tf-rounding", gen.firefox_css({"on": False}))


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

    def test_rerun_follows_a_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.run_into(tmp, frame("round", 10))
            path = os.path.join(tmp, "frame.json")
            with open(path, "w") as f:
                json.dump(frame("chamfer", 12), f)
            subprocess.run([sys.executable, "-I", SCRIPT, path, "--yazi-dir", os.path.join(tmp, "yazi"), "--firefox-dirs", os.path.join(tmp, "ff/chrome")], check=True)
            self.assertEqual(open(os.path.join(tmp, "yazi/frame-border.lua")).read(), 'return "plain"\n')
            self.assertIn("clip-path", open(os.path.join(tmp, "ff/chrome/frame.css")).read())

    def test_missing_input_fails_without_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run([sys.executable, "-I", SCRIPT, os.path.join(tmp, "none.json"), "--yazi-dir", tmp + "/y", "--firefox-dirs"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertFalse(os.path.exists(tmp + "/y"))


if __name__ == "__main__":
    unittest.main()
