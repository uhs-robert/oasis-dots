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
    ("lib/check/steps/qml.py", "checkscope qml"),
    ("lib/check/qml_imports.py", "checkscope qml"),
    ("lib/check/steps/qml_paths.py", "checkscope qml"),
    ("lib/check/steps/qml_layers.py", "checkscope qml"),
    ("lib/check/qml-layers.allow", "checkscope qml"),
    ("lib/check/steps/qml_singleton_names.py", "checkscope qml"),
    ("lib/check/qml-singleton-names.allow", "checkscope qml"),
    ("lib/check/steps/qml_ipc.py", "checkscope"),
    ("lib/check/qml-ipc.allow", "checkscope"),
    ("lib/check/steps/lua.sh", "checkscope lua"),
    ("lib/check/steps/symlinks.sh", "checkscope"),
    # Specs and their schemas reach only the steps that always run, the specs step among them.
    ("lib/check/steps/specs.py", "checkscope"),
    ("specs/core/bar.md", ""),
    ("specs/schema/spec.yaml", ""),
    ("specs/roadmap.md", ""),
    # The registry step is a tree step: the step itself reaches only the always-run steps. The Lua it loads is Lua.
    ("lib/check/steps/registry.py", "checkscope"),
    ("home/hypr/tests/act_refs.lua", " lua"),
    ("home/hypr/tests/hypr-act.sh", " lua"),
    ("home/hypr/tests/act-global.sh", " lua"),
    ("home/hypr/tests/act_global.lua", " lua"),
    ("home/hypr/.local/bin/hypr-act", " lua"),
    ("docs/keybinds.md", ""),
    # First match wins: the greeter's Lua ahead of its QML, the Quickshell tests ahead of the rest of Quickshell.
    ("system/etc/greetd/quickshell/init.lua", " lua qml"),
    ("system/etc/greetd/quickshell/Greeter.qml", " qml"),
    ("system/etc/greetd/config.toml", " lua"),
    # The input vectors' inputs reach their scope ahead of the folders that hold them.
    ("home/hypr/.config/hypr/config/input/init.lua", " lua inputvec"),
    ("home/hypr/.config/hypr/lib/state.lua", " lua inputvec"),
    ("home/hypr/.config/hypr/lib/json.lua", " lua keyring inputvec"),
    ("home/quickshell/tests/input_settings/vectors.tsv", " inputvec qml"),
    ("home/quickshell/.config/quickshell/features/settings/HyprInputValidation.js", " inputvec qml node"),
    ("home/quickshell/.config/quickshell/features/settings/HyprInputSettings.qml", " inputvec qml node"),
    ("home/quickshell/tests/notification_markup.js", " node qml"),
    ("home/quickshell/tests/json_store/run.py", " node qml"),
    ("home/quickshell/tests/polled_command/run.py", " polledcmd qml"),
    ("home/quickshell/.config/quickshell/core/PolledCommand.qml", " polledcmd qml node"),
    ("home/quickshell/tests/polled_file/run.py", " polledfile qml"),
    ("home/quickshell/.config/quickshell/core/PolledFile.qml", " polledfile qml node"),
    ("home/quickshell/tests/restarting_stream/run.py", " restartstream qml"),
    ("home/quickshell/.config/quickshell/core/RestartingStream.qml", " restartstream qml node"),
    ("home/quickshell/.config/quickshell/core/JsonStore.qml", " qml node"),
    # The consumers OUTSIDE_REFS in lib/check/steps/qml_paths.py names reach the qml scope beside their own.
    ("home/hypr/.config/hypr/scripts/lock-screen.sh", " lua qml"),
    ("home/voxcmd/src/timer.rs", " rust voxphrases voxclick voxcalendar voxwake voxfirefox qml"),
    ("home/voxcmd/tests/run-monitors.sh", " voxclick qml"),
    ("home/quickshell/.config/quickshell/shell.qml", " qml node"),
    # A shader reaches only the shader step; its compiled output also reaches QML, which names it by path.
    ("home/quickshell/.config/quickshell/ui/effects/scanlines.frag", " shaders"),
    ("home/quickshell/.config/quickshell/ui/effects/scanlines.frag.qsb", " shaders qml"),
    ("lib/check/steps/shaders.sh", "checkscope shaders"),
    ("home/hypr/.config/hypr/hyprland.lua", " lua"),
    (".luacheckrc", " lua"),
    # A suite's own files reach that suite only; what several read reaches each of them.
    ("home/voxcmd/tests/run.sh", " voxclick"),
    ("home/voxcmd/tests/run-phrases.sh", " voxphrases"),
    ("home/voxcmd/tests/run-calendar.sh", " voxcalendar"),
    ("home/voxcmd/tests/run-wake.sh", " voxwake"),
    ("home/voxcmd/tests/wake_test.py", " voxwake"),
    ("home/voxcmd/tests/run-firefox-extension.sh", " voxfirefox"),
    ("home/voxcmd/tests/lib.sh", " voxclick"),
    ("home/voxtype/.local/bin/voxtype-prompt", " voxtype voxwake"),
    ("home/voxcmd/tests/sandbox.sh", " voxphrases voxclick voxcalendar voxwake"),
    ("home/voxcmd/tests/firefox-profile", " voxphrases voxclick voxcalendar"),
    ("home/voxcmd/tests/fixtures/binds.json", " voxphrases voxclick"),
    ("home/voxcmd/tests/fixtures/overview.json", " voxclick"),
    # The crate's sources reach the suites that build it; its tests, snapshots and goldens only cargo test. An integration
    # file is read by the suites.
    ("home/voxcmd/src/main.rs", " rust voxphrases voxclick voxcalendar voxwake voxfirefox"),
    ("home/voxcmd/Cargo.lock", " rust voxphrases voxclick voxcalendar voxwake voxfirefox"),
    ("home/voxcmd/rustfmt.toml", " rust"),
    ("home/voxcmd/tests/cli.rs", " rust"),
    ("home/voxcmd/tests/fixtures/x.txt", " voxphrases voxclick voxcalendar voxwake voxfirefox"),
    ("home/voxcmd/tests/snapshots/cli__x.snap", " rust"),
    ("home/voxcmd/tests/fixtures/match-goldens.tsv", " rust"),
    ("home/voxcmd/tests/fixtures/legacy-dump.jsonl", " rust"),
    # The fixtures the suites read reach them.
    ("home/voxcmd/tests/fixtures/ocr.tsv", " voxphrases"),
    ("home/voxcmd/tests/fixtures/monitor-places/grid.none.json", " rust"),
    ("home/voxcmd/.config/voxcmd/integrations/x.toml", " rust voxphrases voxclick voxcalendar voxwake voxfirefox"),
    ("lib/check/steps/voxcmd-rust.sh", "checkscope rust"),
    ("extras/voxcmd-firefox/background.js", " voxphrases voxclick voxcalendar voxwake voxfirefox"),
    ("extras/other/file", ""),
    ("lib/install/voice.sh", " policy loader"),
    ("lib/install/tests/migrate-quickshell-input.sh", " migratelock"),
    ("lib/install/tests/migrate-quickshell-weather.sh", " migratelock"),
    ("lib/install/tests/firefox-policy.sh", " policy"),
    ("lib/install/greeter.sh", " keyring loader"),
    ("lib/install/tests/greeter-keyring.sh", " keyring"),
    ("lib/install/fonts.sh", " loader"),
    ("lib/install/tests/load.sh", " loader"),
    ("lib/common/greeter-files.sh", " qml ship loader keyring"),
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

    def test_a_crate_edit_selects_the_voxcmd_suites(self):
        """The suites build the crate and run its binary, so editing its sources or manifest must run them; its test
        sources, snapshots and goldens are read only by cargo test."""
        for path in ("home/voxcmd/src/cli.rs", "home/voxcmd/Cargo.toml"):
            with self.subTest(path=path):
                self.assertIn("voxclick", keys.path_scopes(path).split())
        for path in ("home/voxcmd/tests/cli.rs", "home/voxcmd/tests/snapshots/cli__x.snap"):
            with self.subTest(path=path):
                self.assertFalse(set(scopes.VOXCMD_SUITE_SCOPES) & set(keys.path_scopes(path).split()))

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
