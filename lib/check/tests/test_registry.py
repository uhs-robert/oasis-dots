"""Tests the registry step (lib/check/steps/registry.py): the list checks on tiny git repositories with a handed-in
list, and the headless Lua load on the real tree and on definitions planted in a temp directory."""

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

ZOOM_QML = 'IpcHandler { target: "zoom"; function toggle(): void {}; function untyped(x) {} }\n'
GOOD_LIST = {"version": 1, "actions": [
    {"id": "zoom.toggle", "perform": {"kind": "ipc", "target": "zoom", "function": "toggle", "args": []}},
    {"id": "shot.take", "perform": {"kind": "command", "argv": ["~/.config/hypr/scripts/shot.sh", "--x"]}},
    {"id": "fn.run", "perform": {"kind": "lua"}},
]}


# Actions with no key whose run is an Ipc call (lib/actions/defs/{notifications,style,lock,power,screenshot,zoom,overview,settings,launcher}.lua).
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


class SkipWithoutLuaTest(unittest.TestCase):
    def test_run_checks_returns_none_without_lua(self):
        with unittest.mock.patch.object(registry.shutil, "which", return_value=None):
            self.assertIsNone(registry.run_checks(REPO_DIR))

    def test_main_prints_the_skip_reason_and_passes_without_lua(self):
        out = io.StringIO()
        with unittest.mock.patch.object(registry.shutil, "which", return_value=None), contextlib.redirect_stdout(out):
            self.assertEqual(registry.main([]), 0)
        self.assertEqual(out.getvalue().strip(), f"skip: {registry.SKIP_REASON}")


@unittest.skipUnless(shutil.which("lua"), "lua is not installed")
class HeadlessLoadTest(TreeCase):
    def planted(self, source):
        """The findings for the real tree with `source` as the only definitions file."""
        write_tree(self.root, {"defs/planted.lua": 'local Act = require("lib.act")\n' + source})
        return registry.run_checks(REPO_DIR, self.path("defs"))

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
            "cursor.click", "cursor.move", "cursor.pointer_mode", "cursor.scroll", "cursor.scroll_stop",
            "cursor.send_key",
            "delete.close_group", "delete.close_workspace",
            "files.open",
            "groups.lock_toggle", "groups.move", "groups.move_out", "groups.next", "groups.prev",
            "groups.toggle",
            "help.keybinds",
            "hyprvim.edit_selection", "hyprvim.jump_mark", "hyprvim.terminal",
            "media.brightness_down", "media.brightness_up", "media.mute", "media.mute_mic", "media.next",
            "media.play_pause", "media.prev", "media.volume_down", "media.volume_up",
            "menu.agents", "menu.cli", "menu.drun", "menu.run_script", "menu.ssh",
            "monitor.focus", "monitor.move_window",
            "move.step",
            "picker.clipboard", "picker.clipboard_delete", "picker.directory", "picker.emoji",
            "resize.reset", "resize.step",
            "scratchpad.move", "scratchpad.toggle",
            "submap.enter",
            "system.display_manager", "system.edit_keymaps", "system.next_wallpaper", "system.replay_autostart",
            "system.restart_bar", "system.theme_switch", "system.voxtype_restart", "system.voxtype_settings",
            "terminal.bottom", "terminal.editor", "terminal.open", "terminal.task_manager", "terminal.tool",
            "terminal.tui_files", "terminal.yazi",
            "window.close", "window.cycle_float", "window.float_toggle", "window.focus", "window.focus_match",
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
