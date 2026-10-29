"""Tests the registry step (lib/check/steps/registry.py): the list checks on tiny git repositories with a handed-in
list and handed-in binds, and the headless Lua loads on the real tree and on definitions and keymaps planted in a temp
directory."""

import contextlib
import copy
import io
import os
import shutil
import subprocess
import sys
import unittest
import unittest.mock

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_DIR = os.path.dirname(os.path.dirname(CHECK_DIR))
sys.path.insert(0, os.path.join(CHECK_DIR, "steps"))
import registry  # noqa: E402
from test_qml import TreeCase, write_tree  # noqa: E402

ZOOM_QML = 'IpcHandler { target: "zoom"; function toggle(): void {}; function step(by: int, unit: string): void {}; function untyped(x) {} }\n'
GOOD_LIST = {"version": 1, "actions": [
    {"id": "zoom.toggle", "perform": {"kind": "ipc", "target": "zoom", "function": "toggle", "args": []}},
    {"id": "shot.take", "perform": {"kind": "command", "argv": ["~/.config/hypr/scripts/shot.sh", "--x"]}},
    {"id": "fn.run", "perform": {"kind": "lua"}},
]}
ZOOM_STEP = {"id": "zoom.step", "perform": {"kind": "ipc", "target": "zoom", "function": "step", "args": ["{by}", "px"]}}


# Actions with no key whose run is an Ipc call (lib/act/defs/{notifications,style,lock,power,screenshot,zoom,overview,settings,launcher,bareditor}.lua).
KEYLESS_IPC_IDS = [
    "notifications.toggle_dnd",
    "notifications.clear_all",
    "notifications.dismiss_latest",
    "notifications.dismiss_all",
    "style.cycle",
    "style.set",
    "lock.open",
    "power.confirm",
    "screenshot.menu",
    "screenshot.select",
    "screenshot.stop_recording",
    "zoom.step",
    "zoom.size",
    "zoom.full",
    "overview.toggle",
    "overview.close",
    "tmux.toggle",
    "tmux.close",
    "tmux.search",
    "settings.open",
    "settings.toggle",
    "picker.open",
    "picker.toggle",
    "picker.close",
    "bareditor.open",
    "bareditor.toggle",
    "bareditor.close",
]

class ListCase(TreeCase):
    def check(self, listing=GOOD_LIST):
        write_tree(self.root, {
            "qs/Zoom.qml": ZOOM_QML,
            "home/hypr/.config/hypr/scripts/shot.sh": "#!/bin/sh\n",
        })
        subprocess.run(("git", "init", "-q"), cwd=self.root, check=True)
        return registry.list_findings(self.root, listing, ("qs",))

    def broken(self, mutate):
        """The findings for the good list after mutate(actions) edits a copy of it."""
        listing = copy.deepcopy(GOOD_LIST)
        mutate(listing["actions"])
        return self.check(listing)

    def assertFinding(self, found, text):
        self.assertTrue(any(text in line for line in found), f"{text!r} not in {found}")


class ListTest(ListCase):
    def test_a_good_list_passes(self):
        self.assertEqual(self.check(), [])

    def test_a_duplicate_id_fails(self):
        found = self.broken(lambda actions: actions.append(copy.deepcopy(actions[0])))
        self.assertFinding(found, "action id zoom.toggle appears 2 times")

    def test_a_malformed_id_fails(self):
        found = self.broken(lambda actions: actions[0].update(id="Zoom"))
        self.assertFinding(found, "does not look like 'area.name'")

    def test_a_missing_ipc_function_fails(self):
        found = self.broken(lambda actions: actions[0]["perform"].update({"function": "spin"}))
        self.assertFinding(found, 'calls "zoom spin"')

    def test_an_untyped_ipc_function_fails(self):
        found = self.broken(lambda actions: actions[0]["perform"].update({"function": "untyped"}))
        self.assertFinding(found, 'calls "zoom untyped"')

    def test_matching_ipc_arguments_pass(self):
        self.assertEqual(self.broken(lambda actions: actions.append(dict(ZOOM_STEP))), [])

    def test_too_few_ipc_arguments_fail(self):
        short = copy.deepcopy(ZOOM_STEP)
        short["perform"]["args"] = ["{by}"]
        found = self.broken(lambda actions: actions.append(short))
        self.assertFinding(found, 'zoom.step calls "zoom step" with 1 argument(s), but step(by: int, unit: string) takes 2')

    def test_too_many_ipc_arguments_fail(self):
        found = self.broken(lambda actions: actions[0]["perform"].update(args=["now"]))
        self.assertFinding(found, 'zoom.toggle calls "zoom toggle" with 1 argument(s), but toggle() takes 0')

    def test_a_missing_ipc_target_fails(self):
        found = self.broken(lambda actions: actions[0]["perform"].update(target="nowhere"))
        self.assertFinding(found, 'IPC target "nowhere"')

    def test_a_missing_command_file_fails(self):
        found = self.broken(lambda actions: actions[1]["perform"].update(argv=["~/.config/hypr/scripts/none.sh"]))
        self.assertFinding(found, "~/.config/hypr/scripts/none.sh, which no home/<package>/ ships")

    def test_an_installer_built_executable_is_not_looked_up_in_home(self):
        found = self.broken(lambda actions: actions[1]["perform"].update(argv=["~/.local/bin/voxcmd", "session", "rapid"]))
        self.assertEqual(found, [])

    def test_a_built_executable_is_only_the_named_ones(self):
        found = self.broken(lambda actions: actions[1]["perform"].update(argv=["~/.local/bin/voxcmd-other"]))
        self.assertFinding(found, "~/.local/bin/voxcmd-other, which no home/<package>/ ships")

    def test_a_program_on_the_path_is_not_looked_up(self):
        self.assertEqual(self.broken(lambda actions: actions[1]["perform"].update(argv=["rofi-rbw"])), [])


SPIN_QML = 'IpcHandler { target: "zoom"; function toggle(): void {}; function spin(): void {} }\n'
ALLOW_PATH = "lib/check/registry.allow"


class CoverageTest(ListCase):
    """Binds without an action and IPC functions without an action, against lib/check/registry.allow."""

    def coverage(self, binds=(), allow="", qml=SPIN_QML):
        write_tree(self.root, {
            "qs/Zoom.qml": qml,
            "home/hypr/.config/hypr/scripts/shot.sh": "#!/bin/sh\n",
            ALLOW_PATH: allow,
        })
        subprocess.run(("git", "init", "-q"), cwd=self.root, check=True)
        # zoom.toggle is the only action, so `spin` has none unless the allow text lists it.
        return registry.list_findings(self.root, GOOD_LIST, ("qs",), list(binds))

    def assertFinding(self, found, text):
        self.assertTrue(any(text in line for line in found), f"{text!r} not in {found}")

    def test_an_unlisted_bind_fails_with_its_submap_and_key(self):
        found = self.coverage([("Go", "SUPER + Z", None)], "ipc zoom spin  # x\n")
        self.assertEqual(len(found), 1)
        self.assertFinding(found, "bind Go SUPER + Z performs no action")

    def test_a_bind_that_performs_an_action_needs_no_line(self):
        self.assertEqual(self.coverage([("Go", "SUPER + Z", "zoom.toggle")], "ipc zoom spin  # x\n"), [])

    def test_a_listed_bind_passes(self):
        allow = "bind Go SUPER + Z  # a test key\nipc zoom spin  # x\n"
        self.assertEqual(self.coverage([("Go", "SUPER + Z", None)], allow), [])

    def test_a_key_is_compared_ignoring_case_and_spaces(self):
        allow = "bind Go super+z  # a test key\nipc zoom spin  # x\n"
        self.assertEqual(self.coverage([("Go", "SUPER + Z", None)], allow), [])

    def test_a_line_for_one_submap_does_not_cover_another(self):
        allow = "bind Go SUPER + Z  # a test key\nipc zoom spin  # x\n"
        found = self.coverage([("Go", "SUPER + Z", None), ("Move", "SUPER + Z", None)], allow)
        self.assertFinding(found, "bind Move SUPER + Z performs no action")

    def test_a_star_line_covers_every_named_submap_but_not_the_global_map(self):
        allow = "bind * ESCAPE  # leaves\nipc zoom spin  # x\n"
        binds = [("Go", "ESCAPE", None), ("Move", "ESCAPE", None)]
        self.assertEqual(self.coverage(binds, allow), [])
        found = self.coverage(binds + [("global", "ESCAPE", None)], allow)
        self.assertFinding(found, "bind global ESCAPE performs no action")

    def test_a_comma_list_covers_only_the_submaps_it_names(self):
        allow = "bind Go,Move SLASH  # no-op\nipc zoom spin  # x\n"
        found = self.coverage([("Go", "SLASH", None), ("Move", "SLASH", None), ("Delete", "SLASH", None)], allow)
        self.assertEqual(len(found), 1)
        self.assertFinding(found, "bind Delete SLASH performs no action")

    def test_a_submap_in_a_comma_list_that_matches_nothing_is_stale(self):
        found = self.coverage([("Go", "SLASH", None)], "bind Go,Move SLASH  # no-op\nipc zoom spin  # x\n")
        self.assertFinding(found, "registry.allow:1: bind Move SLASH is stale")
        self.assertEqual(len(found), 1)

    def test_a_stale_bind_line_fails(self):
        allow = "bind Go SUPER + Z  # gone\nipc zoom spin  # x\n"
        found = self.coverage([], allow)
        self.assertFinding(found, "registry.allow:1: bind Go SUPER + Z is stale")

    def test_a_bind_line_for_a_bind_with_an_action_is_stale(self):
        allow = "bind Go SUPER + Z  # now an action\nipc zoom spin  # x\n"
        found = self.coverage([("Go", "SUPER + Z", "zoom.toggle")], allow)
        self.assertFinding(found, "registry.allow:1: bind Go SUPER + Z is stale")

    def test_an_unlisted_ipc_function_fails(self):
        found = self.coverage()
        self.assertEqual(len(found), 1)
        self.assertFinding(found, "IPC function zoom spin has no action")

    def test_a_listed_ipc_function_passes(self):
        self.assertEqual(self.coverage(allow="ipc zoom spin  # a test hook\n"), [])

    def test_one_ipc_line_lists_several_functions(self):
        qml = 'IpcHandler { target: "zoom"; function toggle(): void {}; function spin(): void {}; function stop(): void {} }\n'
        self.assertEqual(self.coverage(allow="ipc zoom spin stop  # test hooks\n", qml=qml), [])

    def test_a_stale_ipc_line_fails(self):
        found = self.coverage(allow="ipc zoom spin  # x\nipc zoom gone  # x\nipc nowhere run  # x\n")
        self.assertFinding(found, "registry.allow:2: ipc zoom gone is stale")
        self.assertFinding(found, "registry.allow:3: ipc nowhere run is stale")
        self.assertEqual(len(found), 2)

    def test_an_ipc_line_for_a_function_with_an_action_is_stale(self):
        found = self.coverage(allow="ipc zoom spin toggle  # x\n")
        self.assertFinding(found, "registry.allow:1: ipc zoom toggle is stale: an action calls it now")

    def test_a_line_with_no_reason_fails(self):
        found = self.coverage(allow="ipc zoom spin\n")
        self.assertFinding(found, "registry.allow:1: needs a reason")
        found = self.coverage([("Go", "SUPER + Z", None)], "bind Go SUPER + Z  #   \nipc zoom spin  # x\n")
        self.assertFinding(found, "registry.allow:1: needs a reason")

    def test_a_malformed_line_fails(self):
        self.assertFinding(self.coverage(allow="ipc zoom  # x\n"), "registry.allow:1: malformed")
        self.assertFinding(self.coverage(allow="skip Go X  # x\n"), "registry.allow:1: malformed")

    def test_a_duplicate_line_fails(self):
        found = self.coverage(allow="ipc zoom spin  # x\nipc zoom spin  # y\n")
        self.assertFinding(found, "registry.allow:2: duplicate entry for ipc zoom spin")

    def test_comments_and_blank_lines_are_ignored(self):
        self.assertEqual(self.coverage(allow="# a comment\n\nipc zoom spin  # x\n"), [])


class MissingLuaTest(unittest.TestCase):
    """The step fails, not skips, without lua: a machine that lacks it must not pass the registry unread."""

    def test_run_checks_fails_without_lua(self):
        with unittest.mock.patch.object(registry.shutil, "which", return_value=None):
            self.assertEqual(registry.run_checks(REPO_DIR), [registry.MISSING_LUA])

    def test_main_prints_the_reason_and_fails_without_lua(self):
        err, out = io.StringIO(), io.StringIO()
        with unittest.mock.patch.object(registry.shutil, "which", return_value=None):
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
                self.assertEqual(registry.main([]), 1)
        self.assertIn("lua is not installed", err.getvalue())
        self.assertNotIn("skip", out.getvalue())

    def test_the_step_is_not_declared_to_skip_without_lua(self):
        import scopes
        step = next(step for step in scopes.STEPS if step.name == "registry")
        self.assertEqual((step.needs, step.probe, step.skip_reason), ((), "", ""))


@unittest.skipUnless(shutil.which("lua"), "lua is not installed")
class HeadlessLoadTest(TreeCase):
    def planted(self, source):
        """The findings for the real tree with `source` as the only definitions file."""
        write_tree(self.root, {"defs/planted.lua": 'local Act = require("lib.act")\n' + source})
        return registry.run_checks(REPO_DIR, self.path("defs"), coverage=False)

    def assertFinding(self, found, text):
        self.assertTrue(any(text in line for line in found), f"{text!r} not in {found}")

    def test_the_real_tree_passes(self):
        self.assertEqual(registry.run_checks(REPO_DIR), [])

    def test_the_real_tree_defines_the_lua_actions(self):
        listing, findings = registry.load_list(REPO_DIR)
        self.assertEqual(findings, [])
        lua_ids = sorted(a["id"] for a in listing["actions"] if a["perform"]["kind"] == "lua")
        self.assertEqual(lua_ids, [
            "apps.focus", "apps.open",
            "cursor.click", "cursor.move", "cursor.move_stop", "cursor.pointer_mode", "cursor.scroll", "cursor.scroll_stop",
            "cursor.send_key",
            "delete.close_group", "delete.close_workspace",
            "files.open",
            "groups.lock_toggle", "groups.move", "groups.move_out", "groups.next", "groups.prev",
            "groups.toggle",
            "help.keybinds",
            "hyprvim.edit_selection", "hyprvim.jump_mark", "hyprvim.terminal",
            "media.brightness_down", "media.brightness_up", "media.mute", "media.mute_mic", "media.next",
            "media.play_pause", "media.prev", "media.volume_down", "media.volume_up",
            "menu.agents", "menu.drun", "menu.ssh",
            "monitor.focus", "monitor.move_window",
            "move.step",
            "picker.agents", "picker.clipboard", "picker.clipboard_delete", "picker.directory", "picker.emoji",
            "resize.reset", "resize.step",
            "scratchpad.move", "scratchpad.toggle",
            "submap.enter",
            "system.edit_keymaps", "system.replay_autostart", "system.voxtype_restart", "system.voxtype_settings",
            "terminal.bottom", "terminal.editor", "terminal.open", "terminal.task_manager", "terminal.tool",
            "terminal.yazi",
            "window.close", "window.cycle_float", "window.float_toggle", "window.focus",
            "window.fullscreen", "window.kill", "window.maximize", "window.move", "window.restore_closed",
            "windows.clear_selection", "windows.close_selected", "windows.confirm", "windows.float_selected",
            "windows.move_selected", "windows.pseudo_selected", "windows.select_toggle",
            "windows.split_selected", "windows.step_float", "windows.swap_selected",
            "windows.workspace_move_selected", "windows.workspace_selected",
            "workspace.cycle", "workspace.focus", "workspace.focus_last", "workspace.move",
            "workspace.move_window",
        ])
        self.assertEqual(len(listing["actions"]), 24 + len(lua_ids) + len(KEYLESS_IPC_IDS))

    def test_the_real_tree_defines_the_keyless_ipc_actions(self):
        listing, findings = registry.load_list(REPO_DIR)
        self.assertEqual(findings, [])
        keyless = sorted(a["id"] for a in listing["actions"] if a["perform"]["kind"] == "ipc" and not a["keys"])
        self.assertEqual(sorted(set(KEYLESS_IPC_IDS) - set(keyless)), [])

    def keymap(self, source):
        """The findings with a planted keymap module loaded instead of `keymaps`. The real allow lines then match nothing
        and are reported stale, so a test looks for its own finding."""
        write_tree(self.root, {"fixture_keymap.lua": 'local Bind = require("lib.key.bind")\n' + source})
        return registry.run_checks(REPO_DIR, keymap=("fixture_keymap", self.root))

    def test_a_planted_plain_bind_fails_with_its_key(self):
        found = self.keymap('Bind.key("SUPER + F12", function() end, "Plain")')
        self.assertFinding(found, "bind global SUPER + F12 performs no action")

    def test_a_planted_plain_bind_that_exists_only_with_monitors_fails(self):
        found = self.keymap('if #require("config").monitors > 0 then Bind.key("SUPER + F11", function() end, "M") end')
        self.assertFinding(found, "bind global SUPER + F11 performs no action")

    def test_a_planted_action_bind_needs_no_line(self):
        found = self.keymap(
            'local Act = require("lib.act")\n'
            'Act.define("fixture.run", { label = "F", run = function() end, key = "SUPER + F12" })'
        )
        self.assertFalse(any("SUPER + F12" in line for line in found), found)

    def test_a_planted_bind_in_a_submap_fails_with_the_submap(self):
        found = self.keymap('Bind.submap("Fixture", function() Bind.key("Q", function() end) end)')
        self.assertFinding(found, "bind Fixture Q performs no action")

    def test_a_planted_keymap_that_fails_to_load_fails(self):
        found = self.keymap('error("boom")')
        self.assertFinding(found, "boom")

    def test_the_real_binds_carry_action_ids_where_they_are_actions(self):
        binds, findings = registry.load_binds(REPO_DIR)
        self.assertEqual(findings, [])
        by_key = {(submap, key): action for submap, key, action in binds}
        self.assertEqual(by_key[("global", "SUPER + X")], "window.close")
        self.assertEqual(by_key[("System", "E")], "power.confirm")  # a one-shot submap wraps the row
        self.assertIsNone(by_key[("System", "ESCAPE")])

    def test_a_planted_good_definition_passes(self):
        self.assertEqual(self.planted('Act.define("zoom.again", { label = "Z", run = Act.Ipc("zoom", "toggle") })'), [])

    def test_a_planted_missing_ipc_function_fails(self):
        found = self.planted('Act.define("zoom.bad", { label = "Z", run = Act.Ipc("zoom", "no_such_function") })')
        self.assertFinding(found, 'zoom.bad calls "zoom no_such_function"')

    def test_a_planted_missing_script_fails(self):
        found = self.planted('Act.define("shot.bad", { label = "S", run = Act.Cmd("~/.config/hypr/scripts/none.sh") })')
        self.assertFinding(found, "shot.bad runs ~/.config/hypr/scripts/none.sh")

    def test_a_planted_duplicate_id_fails(self):
        found = self.planted(
            'Act.define("zoom.twice", { label = "Z", run = function() end })\n'
            'Act.define("zoom.twice", { label = "Z", run = function() end })'
        )
        self.assertFinding(found, "already defined")

    def test_a_planted_undeclared_placeholder_fails(self):
        found = self.planted('Act.define("zoom.size", { label = "Z", run = Act.Ipc("zoom", "toggle", "{n}") })')
        self.assertFinding(found, "not a declared param")

    def test_a_planted_unknown_id_in_bind_fails(self):
        found = self.planted('Act.bind("no.such", { key = "X" })')
        self.assertFinding(found, "unknown action id 'no.such'")

    def test_a_planted_unstubbed_require_names_the_module(self):
        found = self.planted('require("lua.not_a_module")')
        self.assertFinding(found, "lua.not_a_module")


if __name__ == "__main__":
    unittest.main()
