"""Tests that a temp_home step runs under a throwaway HOME the runner removes afterwards, and that the real hypr Lua
steps leave the owner's live theme files alone."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, CHECK_DIR)
import runner  # noqa: E402
import scopes  # noqa: E402

# Prints what the step saw into $SCRATCH/seen, one VAR=value per line.
SEE_ENV = 'env | grep "^\\(HOME\\|XDG_CONFIG_HOME\\|XDG_STATE_HOME\\|XDG_CACHE_HOME\\)=" >"$SCRATCH/seen"; ls "$HOME/.config" >>"$SCRATCH/seen"; '

# Real files and folders the check must not touch, as the owner's live bar and theme read them.
LIVE_PATHS = (".local/state/quickshell", ".config/rofi", ".config/hypr")


def newest_mtimes(root):
    """Every file under root (or root itself, a file) with its mtime in ns, so a rewrite shows even within a second."""
    found = {}
    if os.path.isfile(root):
        return {root: os.stat(root).st_mtime_ns}
    for folder, _, names in os.walk(root):
        for name in names:
            path = os.path.join(folder, name)
            try:
                found[path] = os.stat(path).st_mtime_ns
            except OSError:
                pass
    return found


class TempHomeTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.mkdtemp()
        self.logs = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.scratch, True)
        self.addCleanup(shutil.rmtree, self.logs, True)
        os.environ["SCRATCH"] = self.scratch
        self.addCleanup(os.environ.pop, "SCRATCH", None)

    def run_step(self, command, temp_home, timeout=60):
        pool = runner.StepPool(self.logs, 1)
        step = scopes.Step("probe", "tree", command, temp_home=temp_home, timeout_secs=timeout)
        pool.run_buffered(step)
        return pool

    def seen(self):
        with open(os.path.join(self.scratch, "seen")) as handle:
            return handle.read().splitlines()

    def test_a_flagged_step_sees_a_temp_home_that_is_removed_afterwards(self):
        pool = self.run_step(SEE_ENV, True)
        self.assertEqual(pool.failed, set())
        seen = self.seen()
        home = dict(line.split("=", 1) for line in seen if "=" in line)
        self.assertNotEqual(home["HOME"], os.environ.get("HOME"))
        self.assertTrue(home["HOME"].startswith(tempfile.gettempdir()))
        self.assertEqual(home["XDG_STATE_HOME"], home["HOME"] + "/.local/state")
        self.assertEqual(home["XDG_CONFIG_HOME"], home["HOME"] + "/.config")
        self.assertEqual(home["XDG_CACHE_HOME"], home["HOME"] + "/.cache")
        self.assertIn("quickshell", seen)
        self.assertFalse(os.path.exists(home["HOME"]), "the temp HOME outlived the step")

    def test_an_unflagged_step_keeps_the_real_home(self):
        self.run_step(SEE_ENV, False)
        self.assertIn("HOME=" + os.environ["HOME"], self.seen())

    def test_the_temp_home_is_removed_when_the_step_times_out(self):
        pool = self.run_step('echo "$HOME" >"$SCRATCH/home"; sleep 300', True, timeout=1)
        self.assertEqual(pool.failed, {"probe"})
        with open(os.path.join(self.scratch, "home")) as handle:
            home = handle.read().strip()
        self.assertFalse(os.path.exists(home), "the temp HOME outlived the killed step")

    def test_the_hypr_lua_steps_are_flagged_and_the_lints_are_not(self):
        flagged = {step.name for step in scopes.STEPS if step.temp_home}
        for name in ("registry", "submap-hints", "act-ipc", "docs-generated", "action-registry", "session-start"):
            self.assertIn(name, flagged)
        for name in ("stylua", "luacheck"):
            self.assertNotIn(name, flagged)

    @unittest.skipUnless(shutil.which("lua"), "the hypr steps need lua")
    def test_running_the_hypr_lua_steps_leaves_the_live_theme_files_alone(self):
        real_home = os.path.expanduser("~")
        paths = [os.path.join(real_home, rel) for rel in LIVE_PATHS]
        before = {path: newest_mtimes(path) for path in paths}
        env = {**os.environ, "CHECK_NO_LOCK": "1"}
        result = subprocess.run(
            ["sh", "lib/check.sh", "--only", "registry,submap-hints,act-ipc,docs-generated"],
            cwd=runner.REPO_DIR, env=env, capture_output=True, text=True, timeout=600,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        after = {path: newest_mtimes(path) for path in paths}
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
