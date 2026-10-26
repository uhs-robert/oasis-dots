"""Tests the registry step (lib/check/steps/registry.py) on tiny git repositories, plus one run on the real tree."""

import copy
import json
import os
import shutil
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_DIR = os.path.dirname(os.path.dirname(CHECK_DIR))
sys.path.insert(0, os.path.join(CHECK_DIR, "steps"))
import registry  # noqa: E402
from test_qml import TreeCase, write_tree  # noqa: E402

DIR = "home/oasis-djinn/.config/oasis-djinn"
ZOOM_QML = 'IpcHandler { target: "zoom"; function toggle(): void {}; function untyped(x) {} }\n'
GOOD_ACTIONS = {"actions": [
    {"id": "zoom.toggle", "label": "Zoom", "intent": "Toggle zoom.", "params": [],
     "key": {"key": "Z", "leader": True, "universal": False}, "extra_keys": []},
    {"id": "shot.take", "label": "Shot", "intent": "Take one.", "params": [{"name": "mode", "type": "enum", "values": ["a", "b"]}],
     "key": {"key": "Print", "leader": False, "universal": True}, "extra_keys": []},
]}
GOOD_BINDINGS = {"bindings": {
    "zoom.toggle": {"kind": "ipc", "target": "zoom", "function": "toggle", "args": []},
    "shot.take": {"kind": "command", "argv": ["~/.config/hypr/scripts/shot.sh", "--{mode}"]},
}}
LUA_ACTION = {"id": "window.close", "label": "Close", "intent": "Close it.", "params": [], "extra_keys": []}
NO_PERFORMERS = "local by_id = {}\nreturn by_id\n"
PERFORMERS_LUA = 'local by_id = {\n  ["window.close"] = function() end,\n}\nreturn by_id\n'


class RegistryCase(TreeCase):
    def check(self, actions=GOOD_ACTIONS, bindings=GOOD_BINDINGS, extra=None, hyprland=None):
        for name in os.listdir(self.root):
            full = os.path.join(self.root, name)
            shutil.rmtree(full) if os.path.isdir(full) else os.remove(full)
        for schema in (registry.ACTIONS_SCHEMA, registry.BINDINGS_SCHEMA):
            os.makedirs(os.path.dirname(os.path.join(self.root, schema)), exist_ok=True)
            shutil.copy(os.path.join(REPO_DIR, schema), os.path.join(self.root, schema))
        write_tree(self.root, {
            f"{DIR}/actions.json": json.dumps(actions),
            f"{DIR}/bindings/quickshell.json": json.dumps(bindings),
            "qs/Zoom.qml": ZOOM_QML,
            "home/hypr/.config/hypr/scripts/shot.sh": "#!/bin/sh\n",
            registry.PERFORMERS: NO_PERFORMERS,
            **({f"{DIR}/bindings/hyprland.json": json.dumps(hyprland)} if hyprland is not None else {}),
            **(extra or {}),
        })
        subprocess.run(("git", "init", "-q"), cwd=self.root, check=True)
        return registry.run_checks(self.root, DIR, ("qs",))

    def broken(self, mutate):
        """The findings for the good manifest after mutate(actions, bindings) edits copies of it."""
        actions, bindings = copy.deepcopy(GOOD_ACTIONS), copy.deepcopy(GOOD_BINDINGS)
        mutate(actions["actions"], bindings["bindings"])
        return self.check(actions, bindings)

    def with_lua(self, hyprland=None, performers=PERFORMERS_LUA, quickshell=GOOD_BINDINGS):
        """The findings for the good manifest plus a keyless window.close bound in hyprland.json."""
        actions = copy.deepcopy(GOOD_ACTIONS)
        actions["actions"].append(copy.deepcopy(LUA_ACTION))
        hyprland = {"bindings": {"window.close": {"kind": "lua"}}} if hyprland is None else hyprland
        return self.check(actions, quickshell, {registry.PERFORMERS: performers}, hyprland)

    def assertFinding(self, found, text):
        self.assertTrue(any(text in line for line in found), f"{text!r} not in {found}")


@unittest.skipUnless(shutil.which("check-jsonschema"), "check-jsonschema is not installed")
class RegistryTest(RegistryCase):
    def test_a_good_manifest_passes(self):
        self.assertEqual(self.check(), [])

    def test_the_real_tree_passes(self):
        self.assertEqual(registry.run_checks(REPO_DIR), [])

    def test_a_duplicate_id_fails(self):
        found = self.broken(lambda actions, bindings: actions.append(copy.deepcopy(actions[0])))
        self.assertFinding(found, "action id zoom.toggle appears 2 times")

    def test_a_repeated_param_name_fails(self):
        found = self.broken(lambda actions, bindings: actions[1]["params"].append(copy.deepcopy(actions[1]["params"][0])))
        self.assertFinding(found, "shot.take repeats param mode")

    def test_an_unknown_param_type_fails(self):
        self.assertTrue(self.broken(lambda actions, bindings: actions[1]["params"][0].update(type="color")))

    def test_an_enum_without_values_fails(self):
        self.assertTrue(self.broken(lambda actions, bindings: actions[1]["params"][0].pop("values")))

    def test_values_on_a_non_enum_fail(self):
        self.assertTrue(self.broken(lambda actions, bindings: actions[1]["params"][0].update(type="string")))

    def test_an_unknown_field_fails(self):
        self.assertTrue(self.broken(lambda actions, bindings: actions[0].update(enabled=True)))

    def test_a_bad_id_fails(self):
        self.assertTrue(self.broken(lambda actions, bindings: actions[0].update(id="Zoom")))

    def test_a_default_of_the_wrong_type_fails(self):
        self.assertTrue(self.broken(lambda actions, bindings: actions[1]["params"].append({"name": "n", "type": "int", "default": "x"})))

    def test_an_enum_default_outside_its_values_fails(self):
        found = self.broken(lambda actions, bindings: actions[1]["params"][0].update(default="c"))
        self.assertFinding(found, "default 'c' is not one of its values")

    def test_a_required_param_after_a_default_fails(self):
        found = self.broken(lambda actions, bindings: actions[1]["params"].insert(0, {"name": "n", "type": "int", "default": 1}))
        self.assertFinding(found, "requires param mode after n")

    def test_an_int_default_beyond_i64_fails(self):
        self.assertTrue(self.broken(lambda actions, bindings: actions[1]["params"].append({"name": "n", "type": "int", "default": 2**63})))

    def test_an_int_default_at_the_i64_edge_passes(self):
        found = self.broken(lambda actions, bindings: actions[1]["params"].append({"name": "n", "type": "int", "default": 2**63 - 1}))
        self.assertEqual(found, [])

    def test_an_int_default_written_as_a_float_fails(self):
        found = self.broken(lambda actions, bindings: actions[1]["params"].append({"name": "n", "type": "int", "default": 1.0}))
        self.assertFinding(found, "must be written as an integer")

    def test_a_default_that_fits_passes(self):
        found = self.broken(lambda actions, bindings: actions[1]["params"][0].update(default="a"))
        self.assertEqual(found, [])

    def test_a_string_default_with_a_dash_fails(self):
        found = self.broken(lambda actions, bindings: actions[1]["params"].append({"name": "s", "type": "string", "default": "-x"}))
        self.assertFinding(found, "default starts with '-'")

    def test_an_action_without_a_binding_fails(self):
        found = self.broken(lambda actions, bindings: bindings.pop("zoom.toggle"))
        self.assertFinding(found, "zoom.toggle has no binding")

    def test_a_binding_without_an_action_fails(self):
        found = self.broken(lambda actions, bindings: bindings.update({"gone.now": bindings["zoom.toggle"]}))
        self.assertFinding(found, "binding gone.now names no action")

    def test_a_missing_ipc_function_fails(self):
        found = self.broken(lambda actions, bindings: bindings["zoom.toggle"].update(function="spin"))
        self.assertFinding(found, 'calls "zoom spin"')

    def test_an_untyped_ipc_function_fails(self):
        found = self.broken(lambda actions, bindings: bindings["zoom.toggle"].update(function="untyped"))
        self.assertFinding(found, 'calls "zoom untyped"')

    def test_a_missing_ipc_target_fails(self):
        found = self.broken(lambda actions, bindings: bindings["zoom.toggle"].update(target="nowhere"))
        self.assertFinding(found, 'IPC target "nowhere"')

    def test_a_missing_command_file_fails(self):
        found = self.broken(lambda actions, bindings: bindings["shot.take"].update(argv=["~/.config/hypr/scripts/none.sh"]))
        self.assertFinding(found, "~/.config/hypr/scripts/none.sh, which no home/<package>/ ships")

    def test_a_placeholder_that_is_no_param_fails(self):
        found = self.broken(lambda actions, bindings: bindings["shot.take"].update(argv=["~/.config/hypr/scripts/shot.sh", "{nope}"]))
        self.assertFinding(found, "{nope}, which is not one of its params")


    def test_a_lua_binding_with_a_performer_and_no_key_passes(self):
        self.assertEqual(self.with_lua(), [])

    def test_a_lua_binding_without_a_performer_fails(self):
        found = self.with_lua(performers=NO_PERFORMERS)
        self.assertFinding(found, "window.close is a lua binding, but performers.lua has no function for it")

    def test_a_performer_no_lua_binding_names_fails(self):
        found = self.with_lua(performers=PERFORMERS_LUA.replace("}\nreturn", '  ["gone.now"] = function() end,\n}\nreturn'))
        self.assertFinding(found, "gone.now, which no lua binding names")

    def test_an_action_bound_in_two_files_fails(self):
        hyprland = {"bindings": {"window.close": {"kind": "lua"}, "zoom.toggle": {"kind": "lua"}}}
        found = self.with_lua(hyprland, PERFORMERS_LUA.replace("}\nreturn", '  ["zoom.toggle"] = function() end,\n}\nreturn'))
        self.assertFinding(found, "zoom.toggle is bound in both bindings/hyprland.json and bindings/quickshell.json")

    def test_a_lua_binding_in_the_quickshell_file_fails(self):
        quickshell = copy.deepcopy(GOOD_BINDINGS)
        quickshell["bindings"]["window.close"] = {"kind": "lua"}
        found = self.with_lua({"bindings": {}}, quickshell=quickshell)
        self.assertFinding(found, "bindings/quickshell.json: window.close is a lua binding, which this file cannot hold")

    def test_an_unknown_bindings_file_fails(self):
        found = self.check(extra={f"{DIR}/bindings/sway.json": json.dumps({"bindings": {}})})
        self.assertFinding(found, "bindings/sway.json is not a bindings file")


if __name__ == "__main__":
    unittest.main()
