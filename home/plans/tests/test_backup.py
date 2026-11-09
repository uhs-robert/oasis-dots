"""`plans backup` and `plans restore` against a stub `restic` on PATH. No test runs the real restic or rclone or
touches Google Drive. The stub keeps snapshots as plain folders under STUB_STORE and logs each call.
"""

import io
import json
import os
import shutil
import stat
import sys
import tempfile
import unittest

from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_cli  # noqa: E402,F401  (puts the library on sys.path)

from plans import backup, cli  # noqa: E402

FAKE_RESTIC = r'''#!/usr/bin/env python3
import json, os, shutil, sys
args = sys.argv[1:]
store = os.environ["STUB_STORE"]
with open(os.path.join(store, "log"), "a") as log:
    log.write(json.dumps({"args": args, "repo": os.environ.get("RESTIC_REPOSITORY"),
                          "pw": os.environ.get("RESTIC_PASSWORD_FILE")}) + "\n")
if os.environ.get("STUB_FAIL") == args[0]:
    sys.exit("restic: boom")
snaps = os.path.join(store, "snaps")
os.makedirs(snaps, exist_ok=True)
names = sorted(os.listdir(snaps))
if args[0] == "backup":
    paths = [a for a in args[1:] if a.startswith("/")]
    name = "snap%d" % (len(names) + 1)
    for path in paths:
        shutil.copytree(path, os.path.join(snaps, name, "data", path.lstrip("/")), symlinks=True)
    json.dump(paths, open(os.path.join(snaps, name, "paths.json"), "w"))
elif args[0] == "snapshots":
    wanted = [a for a in args[2:]] if len(args) > 2 else []
    out = []
    for name in names:
        if wanted and wanted[0] not in (name, "latest"):
            continue
        out.append({"id": name + "0" * 8, "time": "2026-11-09T10:00:00Z", "hostname": "laptop",
                    "paths": json.load(open(os.path.join(snaps, name, "paths.json")))})
    if wanted == ["latest"]:
        out = out[-1:]
    print(json.dumps(out))
elif args[0] == "restore":
    name = args[1] if args[1] != "latest" else names[-1]
    target = args[args.index("--target") + 1]
    includes = [args[i + 1] for i, a in enumerate(args) if a == "--include"]
    data = os.path.join(snaps, name, "data")
    for include in includes:
        shutil.copytree(os.path.join(data, include.lstrip("/")), os.path.join(target, include.lstrip("/")),
                        symlinks=True, dirs_exist_ok=True)
'''


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        handle.write(text)


def read(path):
    with open(path) as handle:
        return handle.read()


class BackupCase(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.root = os.path.join(self.tmp, "dev")
        self.alpha = self.make_repo("alpha")
        self.beta = self.make_repo("beta")
        os.makedirs(os.path.join(self.root, "nogit", "x"))  # not a repo
        self.store = os.path.join(self.tmp, "store")
        os.makedirs(self.store)
        bin_dir = os.path.join(self.tmp, "bin")
        os.makedirs(bin_dir)
        stub = os.path.join(bin_dir, "restic")
        write(stub, FAKE_RESTIC)
        os.chmod(stub, 0o755)
        config = os.path.join(self.tmp, "config")
        write(os.path.join(config, "plans", "roots"), self.root + "\n")
        self.password = os.path.join(config, "plans", "backup-password")
        write(self.password, "secret\n")
        os.chmod(self.password, 0o600)
        env = {"PATH": bin_dir + os.pathsep + os.environ["PATH"], "XDG_CONFIG_HOME": config,
               "STUB_STORE": self.store, "PLANS_BACKUP_REPO": "stub-repo", "PLANS_BACKUP_PASSWORD_FILE": self.password}
        patcher = mock.patch.dict(os.environ, env)
        patcher.start()
        self.addCleanup(patcher.stop)
        notify = mock.patch.object(backup, "notify_failure")
        self.notify = notify.start()
        self.addCleanup(notify.stop)

    def make_repo(self, name):
        repo = os.path.join(self.root, name)
        os.makedirs(os.path.join(repo, ".git"))
        write(os.path.join(repo, ".plans", "p", "one.md"), f"{name} one\n")
        write(os.path.join(repo, ".plans", "p", "two.md"), f"{name} two\n")
        write(os.path.join(repo, ".logs", "p", "one", "log.md"), f"{name} log\n")
        return repo

    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = cli.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def calls(self):
        path = os.path.join(self.store, "log")
        return [json.loads(line) for line in read(path).splitlines()] if os.path.exists(path) else []


class TestBackup(BackupCase):
    def test_backs_up_only_plans_and_logs_of_repos_under_roots(self):
        os.remove(os.path.join(self.beta, ".logs", "p", "one", "log.md"))
        shutil.rmtree(os.path.join(self.beta, ".logs"))
        code, out, _ = self.run_cli("backup")
        self.assertEqual(code, 0)
        first = self.calls()[0]
        paths = [a for a in first["args"] if a.startswith("/")]
        self.assertEqual(paths, [f"{self.alpha}/.plans", f"{self.alpha}/.logs", f"{self.beta}/.plans"])
        self.assertEqual((first["repo"], first["pw"]), ("stub-repo", self.password))

    def test_forget_keeps_the_agreed_retention(self):
        self.run_cli("backup")
        forget = self.calls()[1]["args"]
        self.assertEqual(forget[:2], ["forget", "--prune"])
        self.assertIn("48", forget[forget.index("--keep-hourly") + 1])
        self.assertEqual(forget[forget.index("--keep-daily") + 1], "30")

    def test_default_repo_is_the_drive_remote(self):
        with mock.patch.dict(os.environ):
            os.environ.pop("PLANS_BACKUP_REPO")
            self.run_cli("backup")
        self.assertEqual(self.calls()[0]["repo"], "rclone:gdrive:backups/plans")

    def test_failed_backup_exits_nonzero_and_notifies(self):
        with mock.patch.dict(os.environ, {"STUB_FAIL": "backup"}):
            code, _, err = self.run_cli("backup")
        self.assertEqual(code, 1)
        self.assertIn("backup failed", err)
        self.notify.assert_called_once()
        self.assertEqual([c["args"][0] for c in self.calls()], ["backup"])  # no forget after a failed backup

    def test_refuses_a_password_file_others_can_read(self):
        os.chmod(self.password, 0o644)
        code, _, err = self.run_cli("backup")
        self.assertEqual(code, 1)
        self.assertIn("chmod 600", err)
        self.assertEqual(self.calls(), [])

    def test_missing_password_file_refused_without_init(self):
        os.remove(self.password)
        code, _, err = self.run_cli("backup")
        self.assertEqual(code, 1)
        self.assertIn("--init", err)

    def test_init_makes_a_private_password_file_once_and_keeps_an_existing_one(self):
        os.remove(self.password)
        code, out, _ = self.run_cli("backup", "--init")
        self.assertEqual(code, 0)
        self.assertEqual(stat.S_IMODE(os.stat(self.password).st_mode), 0o600)
        first = read(self.password)
        self.assertEqual(self.calls()[0]["args"], ["init"])
        self.run_cli("backup", "--init")
        self.assertEqual(read(self.password), first)


class TestRestore(BackupCase):
    def setUp(self):
        super().setUp()
        self.run_cli("backup")
        self.store_log_size = len(self.calls())
        # Live state moves on after the snapshot: one edit, one deleted file, one file the snapshot lacks.
        write(os.path.join(self.alpha, ".plans", "p", "one.md"), "edited\n")
        os.remove(os.path.join(self.alpha, ".plans", "p", "two.md"))
        write(os.path.join(self.alpha, ".plans", "p", "later.md"), "made after the snapshot\n")

    def test_list_shows_the_snapshots(self):
        code, out, _ = self.run_cli("restore", "--list")
        self.assertEqual(code, 0)
        self.assertIn("snap10000000"[:8], out)
        self.assertIn("2 repos", out)

    def test_needs_list_or_a_snapshot(self):
        self.assertEqual(self.run_cli("restore")[0], 2)
        self.assertEqual(self.run_cli("restore", "--list", "snap1")[0], 2)

    def test_default_changes_nothing_and_names_the_differences(self):
        code, out, _ = self.run_cli("restore", "latest")
        self.assertEqual(code, 0)
        self.assertIn(f"differs\t{self.alpha}/.plans/p/one.md", out)
        self.assertIn(f"new\t{self.alpha}/.plans/p/two.md", out)
        self.assertNotIn("beta", out)  # unchanged files stay quiet
        self.assertEqual(read(os.path.join(self.alpha, ".plans", "p", "one.md")), "edited\n")
        self.assertFalse(os.path.exists(os.path.join(self.alpha, ".plans", "p", "two.md")))

    def test_temp_folder_is_removed(self):
        before = {n for n in os.listdir(tempfile.gettempdir()) if n.startswith("plans-restore-")}
        self.run_cli("restore", "latest")
        self.run_cli("restore", "latest", "--apply")
        after = {n for n in os.listdir(tempfile.gettempdir()) if n.startswith("plans-restore-")}
        self.assertEqual(after - before, set())

    def test_apply_restores_files_and_deletes_nothing(self):
        code, out, _ = self.run_cli("restore", "latest", "--apply")
        self.assertEqual(code, 0)
        plans = os.path.join(self.alpha, ".plans", "p")
        self.assertEqual(read(os.path.join(plans, "one.md")), "alpha one\n")
        self.assertEqual(read(os.path.join(plans, "two.md")), "alpha two\n")
        self.assertEqual(read(os.path.join(plans, "later.md")), "made after the snapshot\n")
        self.assertEqual([n for n in os.listdir(plans) if "restore-tmp" in n], [])

    def test_repo_by_name_touches_only_that_repo(self):
        write(os.path.join(self.beta, ".plans", "p", "one.md"), "beta edited\n")
        self.run_cli("restore", "latest", "--repo", "alpha", "--apply")
        self.assertEqual(read(os.path.join(self.alpha, ".plans", "p", "one.md")), "alpha one\n")
        self.assertEqual(read(os.path.join(self.beta, ".plans", "p", "one.md")), "beta edited\n")

    def test_repo_by_path(self):
        code, out, _ = self.run_cli("restore", "latest", "--repo", self.alpha)
        self.assertEqual(code, 0)
        self.assertIn("one.md", out)

    def test_refuses_a_repo_path_outside_the_roots(self):
        outside = os.path.join(self.tmp, "elsewhere")
        os.makedirs(os.path.join(outside, ".git"))
        write(os.path.join(outside, ".plans", "keep.md"), "live\n")
        code, _, err = self.run_cli("restore", "latest", "--repo", outside, "--apply")
        self.assertEqual(code, 1)
        self.assertIn("not under the roots", err)
        self.assertEqual(read(os.path.join(outside, ".plans", "keep.md")), "live\n")
        self.assertNotIn("restore", [c["args"][0] for c in self.calls()[self.store_log_size:]])

    def test_skips_snapshot_repos_outside_the_roots_but_restores_the_rest(self):
        # The snapshot came from a machine where beta lived elsewhere: shrink the roots to alpha only.
        write(os.path.join(self.tmp, "config", "plans", "roots"), self.alpha + "\n")
        code, out, _ = self.run_cli("restore", "latest", "--apply")
        self.assertEqual(code, 1)
        self.assertIn(f"skipped {self.beta}/.plans: not under the roots", out)
        self.assertEqual(read(os.path.join(self.alpha, ".plans", "p", "one.md")), "alpha one\n")

    def test_skips_a_repo_that_is_not_cloned(self):
        shutil.rmtree(self.beta)
        code, out, _ = self.run_cli("restore", "latest", "--apply")
        self.assertEqual(code, 1)
        self.assertIn("repo is not cloned here", out)
        self.assertFalse(os.path.exists(self.beta))

    def test_unknown_snapshot_refused(self):
        code, _, err = self.run_cli("restore", "nope")
        self.assertEqual(code, 1)
        self.assertIn("no snapshot", err)

    def test_never_writes_through_a_symlink_that_leaves_the_folder(self):
        outside = os.path.join(self.tmp, "outside")
        os.makedirs(outside)
        # The snapshot holds a plain file under p/, but live p/ is now a link to a folder elsewhere.
        shutil.rmtree(os.path.join(self.alpha, ".plans", "p"))
        os.symlink(outside, os.path.join(self.alpha, ".plans", "p"))
        code, _, err = self.run_cli("restore", "latest", "--apply")
        self.assertEqual(code, 1)
        self.assertEqual(os.listdir(outside), [])


if __name__ == "__main__":
    unittest.main()
