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

DIR = "home/actions/.config/actions"
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


class RegistryCase(TreeCase):
    def check(self, actions=GOOD_ACTIONS, bindings=GOOD_BINDINGS, extra=None):
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
            **(extra or {}),
        })
        subprocess.run(("git", "init", "-q"), cwd=self.root, check=True)
        return registry.run_checks(self.root, DIR, ("qs",))

    def broken(self, mutate):
        """The findings for the good manifest after mutate(actions, bindings) edits copies of it."""
        actions, bindings = copy.deepcopy(GOOD_ACTIONS), copy.deepcopy(GOOD_BINDINGS)
        mutate(actions["actions"], bindings["bindings"])
        return self.check(actions, bindings)

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


if __name__ == "__main__":
    unittest.main()
