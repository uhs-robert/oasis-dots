"""Tests that a check sends its temp files to a disk cache folder and sweeps only stale entries from it. Every path
is under a scratch dir; the owner's real cache and HOME are never touched."""

import os
import shutil
import signal
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, CHECK_DIR)
import runner  # noqa: E402

DAY = runner.STALE_SECS


def age(path, secs):
    stamp = time.time() - secs
    os.utime(path, (stamp, stamp), follow_symlinks=False)


class CacheTmpdirTest(unittest.TestCase):
    def setUp(self):
        self.scratch = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.scratch, True)
        self.folder = os.path.join(self.scratch, "cache", "dotfiles", "check")
        saved_tmpdir = os.environ.get("TMPDIR")
        self.addCleanup(self.restore_tmpdir, saved_tmpdir)

    def restore_tmpdir(self, saved):
        if saved is None:
            os.environ.pop("TMPDIR", None)
        else:
            os.environ["TMPDIR"] = saved
        tempfile.tempdir = None

    def env(self, **extra):
        base = {"HOME": os.path.join(self.scratch, "home"), "XDG_CACHE_HOME": os.path.join(self.scratch, "cache")}
        base.update(extra)
        return mock.patch.dict(os.environ, base)

    def test_the_folder_is_absolute_and_follows_xdg_cache_home(self):
        with self.env():
            self.assertEqual(runner.check_cache_dir(), self.folder)

    def test_the_folder_falls_back_to_home_dot_cache(self):
        with self.env():
            os.environ.pop("XDG_CACHE_HOME")
            self.assertEqual(runner.check_cache_dir(), os.path.join(self.scratch, "home", ".cache", "dotfiles", "check"))

    def test_no_folder_for_an_empty_or_relative_cache_path(self):
        with self.env(XDG_CACHE_HOME="relative/cache", HOME=""):
            self.assertIsNone(runner.check_cache_dir())
        with self.env(XDG_CACHE_HOME=""):
            os.environ.pop("HOME")
            self.assertIsNone(runner.check_cache_dir())

    def test_no_folder_when_it_resolves_to_home(self):
        home = os.path.join(self.scratch, "home")
        os.makedirs(os.path.join(home, "dotfiles"))
        os.symlink(home, os.path.join(home, "dotfiles", "check"))
        with self.env(XDG_CACHE_HOME=home):
            self.assertIsNone(runner.check_cache_dir())

    def test_no_folder_when_it_resolves_to_root(self):
        with mock.patch.object(os.path, "realpath", return_value="/"), self.env():
            self.assertIsNone(runner.check_cache_dir())

    def test_main_setup_exports_tmpdir_and_makes_temp_files_there(self):
        with self.env():
            runner.use_check_cache_as_tmpdir()
            self.assertEqual(os.environ["TMPDIR"], self.folder)
            made = tempfile.mkdtemp()
        self.assertEqual(os.path.dirname(made), self.folder)

    def test_main_exports_the_cache_tmpdir_before_its_first_temp_file(self):
        parents = []
        real_mkdtemp = tempfile.mkdtemp

        def recording_mkdtemp(*args, **kwargs):
            made = real_mkdtemp(*args, **kwargs)
            parents.append(os.path.dirname(made))
            return made

        cwd = os.getcwd()
        self.addCleanup(os.chdir, cwd)
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            self.addCleanup(signal.signal, signum, signal.getsignal(signum))
        with self.env(), mock.patch("sys.stdout"), mock.patch.object(tempfile, "mkdtemp", recording_mkdtemp):
            os.environ.pop("TMPDIR", None)
            tempfile.tempdir = None
            self.assertEqual(runner.main(["--plan"]), 0)
            self.assertEqual(os.environ["TMPDIR"], self.folder)
        self.assertEqual(parents[0], self.folder)
        self.assertEqual(os.listdir(self.folder), [])

    def test_tmpdir_is_unchanged_when_no_folder_is_usable(self):
        with self.env(XDG_CACHE_HOME="relative", HOME=""):
            os.environ["TMPDIR"] = "/somewhere"
            runner.use_check_cache_as_tmpdir()
            self.assertEqual(os.environ["TMPDIR"], "/somewhere")

    def test_the_sweep_runs_at_setup_and_keeps_new_entries(self):
        old = os.path.join(self.folder, "old")
        new = os.path.join(self.folder, "new")
        os.makedirs(old)
        os.makedirs(new)
        age(old, 2 * DAY)
        with self.env():
            runner.use_check_cache_as_tmpdir()
        self.assertFalse(os.path.exists(old))
        self.assertTrue(os.path.isdir(new))

    def test_the_sweep_removes_only_entries_over_a_day_old(self):
        for name, secs in (("two_days", 2 * DAY), ("just_over", DAY + 60), ("just_under", DAY - 60), ("fresh", 0)):
            path = os.path.join(self.folder, name)
            os.makedirs(os.path.join(path, "inner"))
            open(os.path.join(path, "inner", "file"), "w").close()
            age(path, secs)
        old_file = os.path.join(self.folder, "old_file")
        open(old_file, "w").close()
        age(old_file, 2 * DAY)
        runner.sweep_stale(self.folder)
        self.assertEqual(sorted(os.listdir(self.folder)), ["fresh", "just_under"])

    def test_a_live_run_with_an_old_inner_file_survives(self):
        live = os.path.join(self.folder, "tmpLIVE")
        os.makedirs(live)
        inner = os.path.join(live, "step.log")
        open(inner, "w").close()
        age(inner, 3 * DAY)
        runner.sweep_stale(self.folder)
        self.assertTrue(os.path.exists(inner))

    def test_the_sweep_never_follows_a_symlink_out_of_the_folder(self):
        outside = os.path.join(self.scratch, "outside")
        os.makedirs(os.path.join(outside, "keep"))
        os.makedirs(self.folder)
        link = os.path.join(self.folder, "link")
        os.symlink(outside, link)
        age(link, 2 * DAY)
        age(outside, 2 * DAY)
        runner.sweep_stale(self.folder)
        self.assertFalse(os.path.lexists(link))
        self.assertTrue(os.path.isdir(os.path.join(outside, "keep")))

    def test_the_sweep_leaves_what_is_outside_the_folder_alone(self):
        sibling = os.path.join(self.scratch, "cache", "dotfiles", "greeter")
        os.makedirs(sibling)
        os.makedirs(self.folder)
        age(sibling, 5 * DAY)
        runner.sweep_stale(self.folder)
        self.assertTrue(os.path.isdir(sibling))

    def test_the_sweep_ignores_a_missing_folder(self):
        runner.sweep_stale(os.path.join(self.scratch, "absent"))

    def test_two_runs_get_different_folders(self):
        with self.env():
            runner.use_check_cache_as_tmpdir()
            first = tempfile.mkdtemp()
            runner.use_check_cache_as_tmpdir()
            second = tempfile.mkdtemp()
        self.assertNotEqual(first, second)
        self.assertTrue(os.path.isdir(first), "a second run's sweep removed the first run's folder")

    def test_temp_home_steps_keep_the_resolved_folder(self):
        # A temp_home step replaces XDG_CACHE_HOME, but the env it gets still names the folder resolved first.
        with self.env():
            runner.use_check_cache_as_tmpdir()
            pool = runner.StepPool(self.scratch, 1)
            step_env = runner.temp_home_env(pool.env, os.path.join(self.scratch, "step_home"))
        self.assertEqual(step_env["XDG_CACHE_HOME"], os.path.join(self.scratch, "step_home", ".cache"))
        self.assertEqual(step_env["TMPDIR"], self.folder)


if __name__ == "__main__":
    unittest.main()
