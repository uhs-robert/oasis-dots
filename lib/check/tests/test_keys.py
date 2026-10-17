"""Tests the step keys of lib/check/keys.py against goldens taken once from the shell runner it replaced, in a scratch
repository whose content is fixed, so its trees and keys are too. Branches cut before the port still run the shell
runner against the same pass records, so a changed key here means passes neither runner honours from the other.

The goldens were produced by the shell runner at e3e2aa654 (its snapshot_tree, classify_tree and step_key, run in
build_repo's repository with SHELL_LISTS written as its list files). Keys depend on the scope table too, so the tests
run against FROZEN_ADDITIVE_SCOPES, FROZEN_PATH_SCOPES and FROZEN_STEPS, copies of that runner's table, patched over
the live scopes.py: later edits to scopes.py never touch them, and the goldens need regenerating only if the key format
itself changes. test_scopes.py covers the live table."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import keys  # noqa: E402
import scopes  # noqa: E402

GIT_ENV = {
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.invalid",
}

# Paths whose names ls-tree quotes even with core.quotePath=false (a quote, a tab), a space, a non-ASCII name it then
# leaves alone, files every scope column shape reaches (none, one scope, two, checkscope plus all, all alone), and
# files an ignored-integrations key must see.
COMMITTED = {
    "lib/check.sh": "runner\n",
    "lib/check/passed.py": "passed\n",
    "justfile": "just\n",
    "README.md": "readme\n",
    "home/voxcmd/tests/run.sh": "voxcmd\n",
    "home/quickshell/.config/quickshell/shell.qml": "qml\n",
    "system/etc/greetd/quickshell/init.lua": "lua\n",
    "lib/install/fonts.sh": "fonts\n",
    "lib/common/output.sh": "output\n",
    "with space/a b.sh": "space\n",
    'home/voxcmd/quote"d.txt': "quote\n",
    "home/voxcmd/tab\tname.txt": "tab\n",
    "home/voxcmd/café.txt": "cafe\n",
    "home/voxcmd/.config/voxcmd/integrations.d/.gitignore": "*\n!.gitignore\n",
}
DIRTY = {"home/voxcmd/tests/run.sh": "voxcmd edited\n"}
UNTRACKED = {
    "newdir/new file.txt": "untracked\n",
    "home/quickshell/tests/new.js": "node\n",
}
IGNORED = {"home/voxcmd/.config/voxcmd/integrations.d/private.sh": "private\n"}

SHELL_LISTS = {
    "run": {"plain": ["lib/install/fonts.sh", "with space/a b.sh"], "sourcing": [], "agent": ["lib/common/output.sh"]},
    "fmt": {"plain": ["with space/a b.sh"], "sourcing": [], "agent": []},
    # A listed file the snapshot does not hold (git quotes this one's name): no key can be made.
    "unkeyable": {"plain": ["lib/install/fonts.sh", 'home/voxcmd/quote"d.txt'], "sourcing": [], "agent": []},
}

# From the shell runner at e3e2aa654 (see the module docstring), over (step, shell list) pairs.
GOLDEN_TREE = "ba39b53717554009c4abb92a39a45c05fd76328f"
GOLDEN_KEYS = {
    ("voxcmd-click", "run"): "db1c513895f0b2788cd44df588a30bc856e592f5",
    ("check-scope", "run"): "a942cb4c687eff98b70e6eea1658deac0227ce7d",
    ("qmllint", "run"): "dc1f4d544d1a4c844008a7f74dd506966f0ba5d1",
    ("luacheck", "run"): "1702ec6b79471df0b15eec350aeb2f9db4af2db4",
    ("notification-markup", "run"): "851f973c2749fd663465dae91b4a0eba3337947a",
    ("install-load", "run"): "607759bdd21756b70ed9f5caaa4e179715f3d08b",
    ("packages", "run"): "59f3dc59883518a1067a530904aba39f036a95e4",
    ("git-diff-check", "run"): "e8a6d91c3104367ddad725110cc98852ce52b56a",
    ("ignored-integrations", "run"): "b482d409971218170895a25b27a44c1eb995b1a4",
    ("shellcheck", "run"): "74cac4b4e3c3c2d5b45e17c9f00dec14d600749b",
    ("shfmt", "fmt"): "c755ffee09101fdf4f9c4ef1336a4800a97764d4",
    ("shellcheck", "unkeyable"): None,
}


def write_files(root, files):
    for path, content in files.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as handle:
            handle.write(content)


def build_repo(root):
    """The fixed scratch repository: COMMITTED in one commit, then DIRTY, UNTRACKED and IGNORED on top. Run with
    GIT_ENV in the environment."""
    subprocess.run(("git", "init", "-q", "--object-format=sha1", root), check=True)
    write_files(root, COMMITTED)
    subprocess.run(("git", "add", "-A"), cwd=root, check=True)
    subprocess.run(("git", "commit", "-q", "-m", "base"), cwd=root, check=True)
    write_files(root, DIRTY)
    write_files(root, UNTRACKED)
    write_files(root, IGNORED)


# The scope table of the shell runner at e3e2aa654, in scopes.py's form, for the goldens above.
FROZEN_ADDITIVE_SCOPES = [("lib/check/*", "checkscope")]
FROZEN_PATH_SCOPES = [
    ("lib/check.sh", "all"),
    ("lib/check/lock.sh", "all"),
    ("lib/check/passed.sh", "all"),
    ("lib/check/passed.py", "all"),
    ("justfile", "all"),
    (".claude/check-commands", "all"),
    ("lib/check/steps/lua.sh", "lua"),
    (".luacheckrc", "lua"),
    ("home/hypr/*", "lua"),
    ("system/etc/greetd/*.lua", "lua qml"),
    ("lib/common/greeter-files.sh", "qml ship loader"),
    ("lib/check/steps/qml.sh", "qml"),
    ("lib/check/steps/lock-skins.sh", "qml"),
    ("lib/check/steps/style-exports.sh", "qml"),
    ("lib/check/steps/time-format.sh", "qml"),
    ("system/etc/greetd/quickshell/*", "qml"),
    ("home/quickshell/tests/*", "node"),
    ("home/quickshell/*", "qml node"),
    ("home/voxcmd/*", "voxcmd"),
    ("extras/voxcmd-firefox/*", "voxcmd"),
    ("lib/install/voice.sh", "policy loader"),
    ("lib/install/tests/firefox-policy.sh", "policy"),
    ("lib/install/greeter.sh", "keyring loader"),
    ("lib/install/tests/greeter-keyring.sh", "keyring"),
    ("lib/install/*.sh", "loader"),
    ("lib/common/*.sh", "loader"),
    ("home/calendar/*", "calendar"),
    ("home/claude/.claude/hooks/*", "hooks"),
    (".claude/hooks/*", "hooks"),
    (".claude/skills/owner-test-bar/*", "bar"),
    (".claude/skills/ship-batch/*", "ship"),
    ("home/claude/.claude/skills/merge-prs/*", "ship"),
    ("system/etc/greetd/*", "lua"),
    ("lib/*", ""),
    ("install.sh", ""),
    ("uninstall.sh", ""),
    ("demo/*", ""),
    ("packages/*", ""),
    ("docs/*", ""),
    ("extras/*", ""),
    ("system/*", ""),
    ("home/*", ""),
    (".claude/*", ""),
    ("*.md", ""),
    ("LICENSE", ""),
    ("*", "all"),
]
# A key reads only a step's name and scope.
FROZEN_STEPS = {
    name: scopes.Step(name, scope, "")
    for name, scope in (
        ("voxcmd-click", "voxcmd"),
        ("check-scope", "checkscope"),
        ("qmllint", "qml"),
        ("luacheck", "lua"),
        ("notification-markup", "node"),
        ("install-load", "loader"),
        ("packages", "tree"),
        ("git-diff-check", "tree"),
        ("ignored-integrations", "tree"),
        ("shellcheck", "shell"),
        ("shfmt", "shell"),
    )
}


class StepKeys(unittest.TestCase):
    def setUp(self):
        # The global config could set an object format or quoting, and an outer hook's GIT_DIR another repository.
        patcher = mock.patch.dict(os.environ, GIT_ENV)
        patcher.start()
        self.addCleanup(patcher.stop)
        for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            os.environ.pop(name, None)
        for name, frozen in (("ADDITIVE_SCOPES", FROZEN_ADDITIVE_SCOPES), ("PATH_SCOPES", FROZEN_PATH_SCOPES)):
            table_patcher = mock.patch.object(scopes, name, frozen)
            table_patcher.start()
            self.addCleanup(table_patcher.stop)
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, True)
        self.logs = os.path.join(self.root, "logs")
        os.mkdir(self.logs)
        self.repo = os.path.join(self.root, "repo")
        build_repo(self.repo)
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(self.repo)

    def test_snapshot_holds_dirty_and_untracked_content(self):
        self.assertEqual(keys.snapshot_tree(self.logs), GOLDEN_TREE)

    def test_snapshot_leaves_the_real_index_alone(self):
        before = subprocess.run(("git", "diff", "--cached", "--name-only"), stdout=subprocess.PIPE, check=True).stdout
        keys.snapshot_tree(self.logs)
        after = subprocess.run(("git", "diff", "--cached", "--name-only"), stdout=subprocess.PIPE, check=True).stdout
        self.assertEqual(before, after)

    def test_keys_match_the_shell_runner(self):
        tree = keys.snapshot_tree(self.logs)
        entries = keys.classify_tree(tree)
        for (name, lists), golden in GOLDEN_KEYS.items():
            with self.subTest(step=name, lists=lists):
                key = keys.step_key(FROZEN_STEPS[name], entries, tree, "no-repos", SHELL_LISTS[lists])
                self.assertEqual(key, golden)

    def test_classified_lines_keep_the_scope_column(self):
        entries = keys.classify_tree(keys.snapshot_tree(self.logs))
        by_path = {entry.path: entry.classified for entry in entries}
        self.assertTrue(by_path["README.md"].startswith(b"  \t100644 blob "))
        self.assertTrue(by_path["lib/check/passed.py"].startswith(b" checkscope all \t"))
        self.assertTrue(by_path["system/etc/greetd/quickshell/init.lua"].startswith(b"  lua qml \t"))
        self.assertIn('"home/voxcmd/quote\\"d.txt"', by_path)
        self.assertIn("home/voxcmd/café.txt", by_path)

    def test_a_key_moves_with_its_scope_only(self):
        tree = keys.snapshot_tree(self.logs)
        before = keys.classify_tree(tree)
        write_files(self.repo, {"home/quickshell/.config/quickshell/shell.qml": "qml edited\n"})
        after_tree = keys.snapshot_tree(self.logs)
        after = keys.classify_tree(after_tree)
        voxcmd = FROZEN_STEPS["voxcmd-click"]
        qml = FROZEN_STEPS["qmllint"]
        self.assertEqual(
            keys.step_key(voxcmd, before, tree, "no-repos", {}),
            keys.step_key(voxcmd, after, after_tree, "no-repos", {}),
        )
        self.assertNotEqual(
            keys.step_key(qml, before, tree, "no-repos", {}), keys.step_key(qml, after, after_tree, "no-repos", {})
        )


if __name__ == "__main__":
    unittest.main()
