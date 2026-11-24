"""Tests that a temp_home step runs under a throwaway HOME the runner removes afterwards. Nothing here reads or
writes the owner's real files."""

import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, CHECK_DIR)
import runner  # noqa: E402
import scopes  # noqa: E402

# Prints what the step saw into $SCRATCH/seen, one VAR=value per line.
SEE_ENV = 'env | grep "^\\(HOME\\|XDG_CONFIG_HOME\\|XDG_STATE_HOME\\|XDG_CACHE_HOME\\)=" >"$SCRATCH/seen"; ls "$HOME/.config" >>"$SCRATCH/seen"; '

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
        for name in ("registry", "submap-hints", "act-ipc", "docs-generated", "action-registry", "session-start", "check-cache"):
            self.assertIn(name, flagged)
        for name in ("stylua", "luacheck"):
            self.assertNotIn(name, flagged)

    def test_a_theme_write_lands_in_the_temp_home_and_is_gone_afterwards(self):
        # Stands for a generator writing theme.json: the file must go under the temp HOME, never the real one.
        command = (
            'mkdir -p "$XDG_STATE_HOME/quickshell" && echo x >"$XDG_STATE_HOME/quickshell/theme.json"'
            ' && echo "$XDG_STATE_HOME/quickshell/theme.json" >"$SCRATCH/written"'
        )
        pool = self.run_step(command, True)
        self.assertEqual(pool.failed, set())
        with open(os.path.join(self.scratch, "written")) as handle:
            written = handle.read().strip()
        self.assertTrue(written.startswith(tempfile.gettempdir() + os.sep))
        self.assertFalse(os.path.exists(written), "the written file outlived the step")

    def test_a_step_whose_temp_home_cannot_be_made_fails_the_run(self):
        for jobs in (1, 2):
            with self.subTest(jobs=jobs):
                pool = runner.StepPool(self.logs, jobs)
                step = scopes.Step("probe", "tree", "true", temp_home=True)
                with mock.patch.object(runner.tempfile, "mkdtemp", side_effect=OSError("no space")):
                    pool.run([], [step])
                self.assertEqual(pool.failed, {"probe"})


if __name__ == "__main__":
    unittest.main()
