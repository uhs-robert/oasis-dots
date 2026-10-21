"""Tests the step keys of lib/check/keys.py against goldens, in a scratch repository whose content is fixed, so its trees
and keys are too, and tests which edits move which keys.

Keys depend on the scope table too, so the tests run against FROZEN_ADDITIVE_SCOPES, FROZEN_PATH_SCOPES and
FROZEN_STEPS, a copy of the table as of the shell runner at e3e2aa654, patched over the live scopes.py: later edits to
scopes.py never touch them, and the goldens need regenerating only if the key format itself changes (print them from
step_key over build_repo's repository). test_scopes.py covers the live table."""

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

# Key version 2, over (step, shell list) pairs.
GOLDEN_TREE = "ba39b53717554009c4abb92a39a45c05fd76328f"
GOLDEN_KEYS = {
    ("voxcmd-click", "run"): "40c4a763a05de289c7f861ec7a63b4bc8609cb0c",
    ("check-scope", "run"): "1a572f34cd33cc6bce605c772f70649ac612f830",
    ("qmllint", "run"): "e5f9386e95383f8e9e2ea2d625b331a2a7a47d33",
    ("luacheck", "run"): "5ad146ec93c9fb03509c36cd449a82961a7fade1",
    ("notification-markup", "run"): "01b0c69970bce1191b50f9695fb8372544cec79c",
    ("install-load", "run"): "f4049088ad8a39604f655b8236248e487c26534f",
    ("packages", "run"): "dd87c70483085cf25e9fdd1680b7bf2110a4d718",
    ("git-diff-check", "run"): "86e4ebb106131abaa213f246c8780a5ae26bf33f",
    ("ignored-integrations", "run"): "184275857b6a2b4417eebf76e1a047e335b80444",
    ("shellcheck", "run"): "c1294268a8c0b90ec44d9865084d57ca04e113d6",
    ("shfmt", "fmt"): "b088898f0fdc23abaa8a4f78078f223de03e6aea",
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
    ("lib/common/greeter-files.sh", "qml ship loader keyring"),
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
# A key reads a step's definition fields (keys.DEFINITION_FIELDS), here only its name and scope.
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

    def test_keys_match_the_goldens(self):
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

    def key_of(self, step):
        tree = keys.snapshot_tree(self.logs)
        return keys.step_key(step, keys.classify_tree(tree), tree, "no-repos", SHELL_LISTS["run"])

    def all_keys(self):
        return {name: self.key_of(step) for name, step in FROZEN_STEPS.items()}

    def moved_since(self, before):
        after = self.all_keys()
        return {name for name in before if before[name] != after[name]}

    def test_an_unrelated_scopes_edit_keeps_the_other_steps_keys(self):
        write_files(self.repo, {"lib/check/scopes.py": "scopes\n"})
        before = self.all_keys()
        write_files(self.repo, {"lib/check/scopes.py": "scopes, edited\n"})
        # check-scope reads scopes.py through its own scope; the tree steps key on the whole tree.
        self.assertEqual(self.moved_since(before) - {"packages", "git-diff-check", "ignored-integrations"}, {"check-scope"})

    def test_widening_a_steps_scope_moves_the_keys_of_the_steps_that_read_the_file(self):
        before = self.all_keys()
        widened = [("home/quickshell/.config/quickshell/shell.qml", "qml voxcmd")] + FROZEN_PATH_SCOPES
        with mock.patch.object(scopes, "PATH_SCOPES", widened):
            moved = self.moved_since(before)
        self.assertEqual(moved - {"packages", "git-diff-check", "ignored-integrations"}, {"voxcmd-click", "qmllint", "notification-markup"})

    def test_editing_a_steps_command_moves_that_steps_key_only(self):
        before = self.all_keys()
        edited = FROZEN_STEPS["voxcmd-click"]._replace(command="bash ./other.sh")
        self.assertNotEqual(self.key_of(edited), before["voxcmd-click"])
        for name, step in FROZEN_STEPS.items():
            if name != "voxcmd-click":
                self.assertEqual(self.key_of(step), before[name])

    def test_every_definition_field_moves_the_key(self):
        step = FROZEN_STEPS["voxcmd-click"]
        changes = {"name": "renamed", "scope": "qml", "command": "true", "needs": ("jq",), "probe": "true"}
        self.assertEqual(set(changes), set(keys.DEFINITION_FIELDS))
        for field, value in changes.items():
            with self.subTest(field=field):
                self.assertNotEqual(self.key_of(step), self.key_of(step._replace(**{field: value})))

    def test_the_ignored_integrations_step_reads_the_toml_directory_too(self):
        """The step script, run in the scratch repository: an ignored integrations/*.toml is reported, a symlink is not."""
        step_dir = os.path.join(self.repo, "lib", "check", "steps")
        os.makedirs(step_dir)
        shutil.copy(os.path.join(os.path.dirname(keys.__file__), "steps", "ignored-integrations.sh"), step_dir)
        toml_dir = "home/voxcmd/.config/voxcmd/integrations"
        write_files(self.repo, {f"{toml_dir}/.gitignore": "*\n", f"{toml_dir}/private.toml": "x\n"})
        os.symlink("private.toml", os.path.join(self.repo, toml_dir, "linked.toml"))
        done = subprocess.run(
            ("sh", os.path.join(step_dir, "ignored-integrations.sh")), capture_output=True, text=True, check=False
        )
        self.assertEqual(done.returncode, 1)
        self.assertIn(f"{toml_dir}/private.toml is ignored by git", done.stderr)
        self.assertNotIn("linked.toml", done.stderr)

    def test_scheduling_fields_leave_the_key_alone(self):
        step = FROZEN_STEPS["voxcmd-click"]
        self.assertEqual(self.key_of(step), self.key_of(step._replace(skip_reason="other reason", serial_lane=True)))


class StepFields(unittest.TestCase):
    def test_every_step_field_is_keyed_or_declared_not_to_matter(self):
        """Fails when a Step gains a field: decide whether it can change whether the step passes (then add it to
        keys.DEFINITION_FIELDS) or not (then keys.NON_KEY_FIELDS)."""
        self.assertEqual(set(scopes.Step._fields), set(keys.DEFINITION_FIELDS) | set(keys.NON_KEY_FIELDS))
        self.assertFalse(set(keys.DEFINITION_FIELDS) & set(keys.NON_KEY_FIELDS))


if __name__ == "__main__":
    unittest.main()
