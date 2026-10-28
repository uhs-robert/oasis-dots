"""Tests which scopes a changed path reaches (keys.path_scopes over scopes.py), without a clone. The expected strings
are the raw $scopes of the shell runner the port replaced, leading space included, since they are part of the key bytes.
"""

import os
import shlex
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import keys  # noqa: E402
import scopes  # noqa: E402

CASES = [
    # The runner's own files run everything.
    ("lib/check.sh", " all"),
    ("lib/check/runner.py", " checkscope all"),
    ("lib/check/keys.py", " checkscope all"),
    ("lib/check/scopes.py", " checkscope all"),
    ("lib/check/passed.py", " checkscope all"),
    ("lib/check/passed.sh", " checkscope all"),
    ("lib/check/lock.sh", " checkscope all"),
    ("justfile", " all"),
    (".claude/check-commands", " all"),
    # Named one by one above because `*` crosses `/`: a test module is no runner file.
    ("lib/check/tests/test_keys.py", " checkscope"),
    ("lib/check/tests/scope.sh", " checkscope"),
    ("lib/check/steps/symlinks.sh", " checkscope"),
    ("lib/check/registry.allow", " checkscope"),
    ("lib/check/qml-ipc.allow", " checkscope"),
    ("lib/plan_new.py", " checkscope"),
    # A check module or allow list that a step of another folder reads reaches that folder as well.
    ("lib/check/steps/qml.py", " checkscope quickshell"),
    ("lib/check/qml-layers.allow", " checkscope quickshell"),
    ("lib/check/steps/qml_paths.py", " checkscope quickshell docsgen"),
    ("lib/check/steps/qml_ipc.py", " checkscope docsgen"),
    ("lib/check/steps/lua.sh", " checkscope hypr"),
    ("lib/check/steps/shaders.sh", " checkscope quickshell"),
    ("lib/check/steps/voxcmd-rust.sh", " checkscope voxrust"),
    ("lib/check/steps/docs-generated.sh", " checkscope docsgen"),
    ("lib/docs/gen-keybinds", " checkscope docsgen"),
    ("lib/docs/gen-ipc", " checkscope docsgen"),
    ("lib/docs/docgen.py", " checkscope docsgen"),
    # hypr: the Lua config and its tests; the generated keybind table reads the keymaps.
    ("home/hypr/tests/act-global.sh", " hypr docsgen"),
    ("home/hypr/tests/act_stubs.lua", " hypr docsgen"),
    ("home/hypr/.local/bin/hypr-act", " hypr docsgen"),
    ("home/hypr/.config/hypr/hyprland.lua", " hypr docsgen"),
    (".claude/skills/shadow/shadow.sh", " hypr"),
    (".luacheckrc", " hypr"),
    ("system/etc/greetd/config.toml", " hypr"),
    # The greeter's Lua is ahead of its QML, which is ahead of nothing else under greetd.
    ("system/etc/greetd/hyprland.lua", " hypr quickshell install"),
    ("system/etc/greetd/quickshell/init.lua", " hypr quickshell"),
    ("system/etc/greetd/quickshell/Greeter.qml", " quickshell"),
    # Files a Lua file shares with another folder's steps reach both.
    ("home/hypr/.config/hypr/config/input/init.lua", " hypr quickshell docsgen"),
    ("home/hypr/.config/hypr/lib/state.lua", " hypr quickshell docsgen"),
    ("home/hypr/.config/hypr/lib/json.lua", " hypr install quickshell docsgen"),
    ("home/hypr/.config/hypr/scripts/lock-screen.sh", " hypr quickshell docsgen"),
    ("lib/install/greeter-monitors.lua", " install hypr"),
    # quickshell: the bar and every test of it. A handler file also feeds the generated IPC table.
    ("home/quickshell/.config/quickshell/shell.qml", " quickshell"),
    ("home/quickshell/.config/quickshell/core/JsonStore.qml", " quickshell"),
    ("home/quickshell/.config/quickshell/features/lock/LockIpc.qml", " docsgen quickshell"),
    ("home/quickshell/.config/quickshell/features/bar_editor/BarEditorIpc.qml", " docsgen quickshell"),
    # A test fixture named like a handler is not read by the IPC table.
    ("home/quickshell/tests/polled_command/FakeIpc.qml", " quickshell"),
    ("home/quickshell/tests/notification_markup.js", " quickshell"),
    ("home/quickshell/tests/input_settings/vectors.tsv", " quickshell"),
    ("home/quickshell/tests/bar_editor/run.py", " quickshell"),
    ("home/quickshell/.config/quickshell/ui/effects/scanlines.frag", " quickshell"),
    ("home/quickshell/.config/quickshell/ui/effects/scanlines.frag.qsb", " quickshell"),
    # voxcmd. A suite's own files reach that suite only; what several read reaches each of them.
    ("home/voxcmd/tests/run.sh", " voxclick"),
    ("home/voxcmd/tests/lib.sh", " voxclick"),
    ("home/voxcmd/tests/run-phrases.sh", " voxphrases"),
    ("home/voxcmd/tests/run-calendar.sh", " voxrest"),
    ("home/voxcmd/tests/run-wake.sh", " voxrest"),
    ("home/voxcmd/tests/wake_test.py", " voxrest"),
    ("home/voxcmd/tests/run-firefox-extension.sh", " voxrest"),
    ("home/voxcmd/tests/sandbox.sh", " voxphrases voxclick voxrest"),
    ("home/voxcmd/tests/firefox-profile", " voxphrases voxclick voxrest"),
    ("home/voxcmd/tests/fixtures/binds.json", " voxphrases voxclick"),
    ("home/voxcmd/tests/fixtures/overview.json", " voxclick"),
    ("home/voxcmd/tests/fixtures/ocr.tsv", " voxphrases"),
    ("home/voxcmd/tests/fixtures/x.txt", " voxphrases voxclick voxrest"),
    # The crate's sources reach the suites that build it; its tests, snapshots and goldens only cargo test (voxrust).
    ("home/voxcmd/src/main.rs", " voxphrases voxclick voxrest voxrust"),
    ("home/voxcmd/Cargo.lock", " voxphrases voxclick voxrest voxrust"),
    ("home/voxcmd/.config/voxcmd/integrations/x.toml", " voxphrases voxclick voxrest voxrust"),
    ("extras/voxcmd-firefox/background.js", " voxphrases voxclick voxrest"),
    ("home/voxcmd/rustfmt.toml", " voxrust"),
    ("home/voxcmd/tests/cli.rs", " voxrust"),
    # Cargo tests read the shipped share/ files and replacement rules, so they reach the crate step too.
    ("home/voxcmd/.local/share/voxcmd/hook-cache.sh", " voxphrases voxclick voxrest voxrust"),
    ("home/voxcmd/.config/voxcmd/replacements.d/resize", " voxphrases voxclick voxrest voxrust"),
    ("home/voxcmd/tests/snapshots/cli__x.snap", " voxrust"),
    ("home/voxcmd/tests/fixtures/match-goldens.tsv", " voxrust"),
    ("home/voxcmd/tests/fixtures/monitor-places/grid.none.json", " voxrust"),
    # Consumers that lib/check/steps/qml_paths.py names reach the quickshell scope beside their own.
    ("home/voxcmd/src/timer.rs", " voxphrases voxclick voxrest voxrust quickshell"),
    ("home/voxcmd/tests/run-monitors.sh", " voxclick quickshell"),
    # voxtype is the duck suite's; the daemon runs the voxcmd suites and the prompt is also asserted by the wake suite.
    ("home/voxtype/tests/run-duck.sh", " voxduck"),
    ("home/voxtype/.local/bin/voxtype-daemon", " voxphrases voxclick voxrest"),
    ("home/voxtype/.local/bin/voxtype-prompt", " voxduck voxrest"),
    ("home/systemd/.config/systemd/user/voxtype-duck.service", " voxduck"),
    # install: the libraries, their tests, the common ones they load, and the host-side calendar.
    ("lib/install/voice.sh", " install"),
    ("lib/install/fonts.sh", " install"),
    ("lib/install/tests/greeter-keyring.sh", " install"),
    ("lib/common/output.sh", " install"),
    ("lib/common/greeter-files.sh", " quickshell install skills"),
    ("packages/snapper.ini", " install"),
    # hooks: the agent hooks and the tests of the reviewers and owner-test-bar; skills: ship-batch and merge-prs.
    (".claude/hooks/check-before-commit.sh", " hooks"),
    ("home/claude/.claude/skills/orchestrator/reviewers.json", " hooks"),
    (".claude/skills/owner-test-bar/owner-test-bar.sh", " hooks"),
    (".claude/skills/ship-batch/tests/run.sh", " skills"),
    ("home/claude/.claude/skills/merge-prs/tests/run.sh", " skills"),
    # Only the steps that always run look at these.
    ("extras/other/file", ""),
    ("home/kitty/.config/kitty/kitty.conf", ""),
    ("install.sh", ""),
    ("demo/showcase.sh", ""),
    ("packages/stow.ini", ""),
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

    def test_a_crate_edit_selects_the_voxcmd_suites(self):
        """The suites build the crate and run its binary, so editing its sources or manifest must run them and the
        crate's own step; its test sources, snapshots and goldens are read only by cargo test, in the voxrust scope."""
        for path in ("home/voxcmd/src/cli.rs", "home/voxcmd/Cargo.toml"):
            with self.subTest(path=path):
                self.assertEqual(set(keys.path_scopes(path).split()), {*scopes.VOXCMD_SUITE_SCOPES, scopes.VOX_RUST})
        for path in ("home/voxcmd/tests/cli.rs", "home/voxcmd/tests/snapshots/cli__x.snap"):
            with self.subTest(path=path):
                self.assertEqual(keys.path_scopes(path).split(), [scopes.VOX_RUST])

    def test_a_voxcmd_click_edit_selects_only_the_click_sub_scope(self):
        for path in ("home/voxcmd/tests/run.sh", "home/voxcmd/tests/run-sessions.sh", "home/voxcmd/tests/fixtures/overview.json"):
            with self.subTest(path=path):
                self.assertEqual(keys.path_scopes(path).split(), [scopes.VOX_CLICK])
        click_steps = [step.name for step in scopes.STEPS if step.scope == scopes.VOX_CLICK]
        self.assertEqual(click_steps, ["voxcmd-click"])

    def test_markdown_runs_no_step_unless_a_test_reads_it(self):
        for path in ("README.md", "lib/check/README.md", "home/claude/.claude/skills/merge-prs/SKILL.md",
                     ".claude/hooks/README.md", "home/voxcmd/.config/voxcmd/README.md", "home/hypr/.config/hypr/README.md"):
            with self.subTest(path=path):
                self.assertEqual(keys.path_scopes(path), "")
        # docs-generated compares these two against what the generators print.
        self.assertEqual(keys.path_scopes("docs/keybinds.md"), " docsgen")
        self.assertEqual(keys.path_scopes("home/quickshell/.config/quickshell/README.md"), " docsgen")

    def test_there_are_few_folder_scopes(self):
        folder_scopes = {step.scope for step in scopes.STEPS} - {"tree", "shell"}
        self.assertLessEqual(len(folder_scopes), 12, sorted(folder_scopes))

    def test_tests_are_found_by_naming_convention(self):
        """A tests/ file that follows a convention in scopes.py is a step without an entry of its own."""
        names = {step.name for step in scopes.STEPS}
        for name in ("act-global", "bar-layout", "polled-command", "install-pacman-tweaks", "hook-check-before-pr"):
            with self.subTest(name=name):
                self.assertIn(name, names)

    def test_every_step_scope_is_reachable(self):
        """A step whose scope no path reaches would run only in a full check."""
        reachable = {"tree", "shell", "all"}
        for _, scope in scopes.ADDITIVE_SCOPES + scopes.PATH_SCOPES:
            reachable.update(scope.split())
        for step in scopes.STEPS:
            with self.subTest(step=step.name):
                self.assertIn(step.scope, reachable)

    def test_step_commands_name_existing_paths(self):
        """A typo in a step command must fail here, with the tests, not only when that step runs."""
        repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
        for step in scopes.STEPS:
            for word in shlex.split(step.command):
                if word.startswith("./") and "$" not in word:
                    with self.subTest(step=step.name, path=word):
                        self.assertTrue(os.path.exists(os.path.join(repo, word)))

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
