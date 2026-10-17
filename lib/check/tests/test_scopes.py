"""Tests which scopes a changed path reaches (keys.path_scopes over scopes.py), without a clone. The expected strings
are the raw $scopes of the shell runner the port replaced, leading space included, since they are part of the key bytes.
"""

import os
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import keys  # noqa: E402
import scopes  # noqa: E402

CASES = [
    # The runner's own files run everything; lib/check/ files also reach the check's own tests.
    ("lib/check.sh", " all"),
    ("lib/check/runner.py", "checkscope all"),
    ("lib/check/keys.py", "checkscope all"),
    ("lib/check/scopes.py", "checkscope all"),
    ("lib/check/passed.py", "checkscope all"),
    ("lib/check/passed.sh", "checkscope all"),
    ("lib/check/lock.sh", "checkscope all"),
    ("justfile", " all"),
    (".claude/check-commands", " all"),
    # Named one by one above because `*` crosses `/`: a test module is no runner file.
    ("lib/check/tests/test_keys.py", "checkscope"),
    ("lib/check/tests/scope.sh", "checkscope"),
    ("lib/check/steps/qml.sh", "checkscope qml"),
    ("lib/check/steps/lua.sh", "checkscope lua"),
    ("lib/check/steps/symlinks.sh", "checkscope"),
    # First match wins: the greeter's Lua ahead of its QML, the Quickshell tests ahead of the rest of Quickshell.
    ("system/etc/greetd/quickshell/init.lua", " lua qml"),
    ("system/etc/greetd/quickshell/Greeter.qml", " qml"),
    ("system/etc/greetd/config.toml", " lua"),
    ("home/quickshell/tests/notification_markup.js", " node"),
    ("home/quickshell/.config/quickshell/shell.qml", " qml node"),
    ("home/hypr/.config/hypr/hyprland.lua", " lua"),
    (".luacheckrc", " lua"),
    ("home/voxcmd/tests/run.sh", " voxcmd"),
    ("extras/voxcmd-firefox/background.js", " voxcmd"),
    ("extras/other/file", ""),
    ("lib/install/voice.sh", " policy loader"),
    ("lib/install/tests/firefox-policy.sh", " policy"),
    ("lib/install/greeter.sh", " keyring loader"),
    ("lib/install/tests/greeter-keyring.sh", " keyring"),
    ("lib/install/fonts.sh", " loader"),
    ("lib/install/tests/load.sh", " loader"),
    ("lib/common/greeter-files.sh", " qml ship loader"),
    ("lib/common/output.sh", " loader"),
    ("lib/common/README", ""),
    ("home/calendar/tests/run.sh", " calendar"),
    (".claude/hooks/check-before-commit.sh", " hooks"),
    ("home/claude/.claude/hooks/tests/stale-shells.sh", " hooks"),
    (".claude/skills/owner-test-bar/owner-test-bar.sh", " bar"),
    (".claude/skills/ship-batch/tests/run.sh", " ship"),
    ("home/claude/.claude/skills/merge-prs/tests/run.sh", " ship"),
    (".claude/skills/other/SKILL.md", ""),
    ("home/kitty/.config/kitty/kitty.conf", ""),
    ("install.sh", ""),
    ("demo/showcase.sh", ""),
    ("packages/stow.ini", ""),
    ("docs/x/README.md", ""),
    ("README.md", ""),
    ("LICENSE", ""),
    # Nothing claims these, so they run everything; nor a path git quoted (an unusual name in a diff).
    ("newdir/file", " all"),
    ("LICENSE.txt", " all"),
    (".github/workflows/ci.yml", " all"),
    ('"home/voxcmd/caf\\303\\251.txt"', " all"),
]


class PathScopes(unittest.TestCase):
    def test_cases(self):
        for path, expected in CASES:
            with self.subTest(path=path):
                self.assertEqual(keys.path_scopes(path), expected)

    def test_every_step_scope_is_reachable(self):
        """A step whose scope no path reaches would run only in a full check."""
        reachable = {"tree", "shell", "all"}
        for _, scope in scopes.ADDITIVE_SCOPES + scopes.PATH_SCOPES:
            reachable.update(scope.split())
        for step in scopes.STEPS:
            with self.subTest(step=step.name):
                self.assertIn(step.scope, reachable)

    def test_step_names_are_unique(self):
        names = [step.name for step in scopes.STEPS]
        self.assertEqual(len(names), len(set(names)))

    def test_skippable_steps_say_why(self):
        for step in scopes.STEPS:
            if step.needs or step.probe:
                with self.subTest(step=step.name):
                    self.assertTrue(step.skip_reason)


if __name__ == "__main__":
    unittest.main()
