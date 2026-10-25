"""Tests `act` (home/actions/.local/bin/act) against a temp manifest and a stub qs-ipc that records its arguments."""

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
REPO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ACT = os.path.join(REPO_DIR, "home/actions/.local/bin/act")
REAL_MANIFEST = os.path.join(REPO_DIR, "home/actions/.config/actions")

ACTIONS = {"actions": [
    {"id": "t.go", "label": "Go", "intent": "Go.", "params": [
        {"name": "n", "type": "int"}, {"name": "mode", "type": "enum", "values": ["a", "b"], "default": "a"},
        {"name": "flag", "type": "bool", "default": False}],
     "key": {"key": "G", "leader": True, "universal": False}, "extra_keys": []},
    {"id": "t.run", "label": "Run", "intent": "Run.", "params": [],
     "key": {"key": "R", "leader": True, "universal": False}, "extra_keys": []},
    {"id": "t.nobind", "label": "None", "intent": "None.", "params": [],
     "key": {"key": "N", "leader": True, "universal": False}, "extra_keys": []},
]}
BINDINGS = {"bindings": {
    "t.go": {"kind": "ipc", "target": "thing", "function": "go", "args": ["{n}", "{mode}", "{flag}"]},
    "t.run": {"kind": "command", "argv": ["{stub}", "ran", "--x"]},
}}


class ActTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.dir = scratch.name
        self.log = os.path.join(self.dir, "log")
        self.stub = os.path.join(self.dir, "stub")
        with open(self.stub, "w") as handle:
            handle.write(f'#!/bin/sh\necho "$@" >> {self.log}\n[ -z "$STUB_FAIL" ]\n')
        os.chmod(self.stub, os.stat(self.stub).st_mode | stat.S_IXUSR)
        manifest = os.path.join(self.dir, "actions")
        os.makedirs(os.path.join(manifest, "bindings"))
        bindings = json.loads(json.dumps(BINDINGS).replace("{stub}", self.stub))
        for name, data in (("actions.json", ACTIONS), ("bindings/quickshell.json", bindings)):
            with open(os.path.join(manifest, name), "w") as handle:
                json.dump(data, handle)
        self.manifest = manifest

    def act(self, *args, manifest=None, **env):
        done = subprocess.run([sys.executable, "-B", ACT, *args], capture_output=True, text=True,
                              env={**os.environ, "ACT_CONFIG_DIR": manifest or self.manifest, "ACT_QS_IPC": self.stub, **env})
        return done.returncode, done.stderr

    def calls(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log) as handle:
            return handle.read().splitlines()

    def test_an_ipc_action_calls_qs_ipc_with_its_params(self):
        self.assertEqual(self.act("t.go", "3", "b", "true")[0], 0)
        self.assertEqual(self.calls(), ["call thing go 3 b true"])

    def test_defaults_fill_the_params_left_out(self):
        self.act("t.go", "3")
        self.assertEqual(self.calls(), ["call thing go 3 a false"])

    def test_a_command_action_runs_its_argv(self):
        self.assertEqual(self.act("t.run")[0], 0)
        self.assertEqual(self.calls(), ["ran --x"])

    def test_a_failing_performer_exits_1(self):
        self.assertEqual(self.act("t.run", STUB_FAIL="1")[0], 1)

    def test_a_missing_program_exits_1(self):
        os.remove(self.stub)
        self.assertEqual(self.act("t.run")[0], 1)

    def rejected(self, *args):
        code, message = self.act(*args)
        self.assertEqual(code, 2, message)
        self.assertEqual(self.calls(), [])
        return message

    def test_an_unknown_id_exits_2_without_a_call(self):
        self.assertIn("unknown action 'nope.x'", self.rejected("nope.x"))

    def test_no_id_exits_2(self):
        self.rejected()

    def test_a_wrong_typed_param_exits_2(self):
        self.assertIn("param n", self.rejected("t.go", "three"))

    def test_a_value_outside_an_enum_exits_2(self):
        self.assertIn("not one of a, b", self.rejected("t.go", "3", "c"))

    def test_a_bad_bool_exits_2(self):
        self.rejected("t.go", "3", "a", "yes")

    def test_a_missing_required_param_exits_2(self):
        self.assertIn("needs param n", self.rejected("t.go"))

    def test_too_many_params_exit_2(self):
        self.rejected("t.run", "extra")

    def test_an_action_without_a_binding_exits_2(self):
        self.rejected("t.nobind")

    def test_a_missing_manifest_exits_2(self):
        self.assertEqual(self.act("t.run", manifest=os.path.join(self.dir, "none"))[0], 2)

    def test_the_real_manifest_performs_each_first_action(self):
        wanted = {"zoom.toggle": "call zoom toggle", "overview.open": "call overview open"}
        for action, call in wanted.items():
            self.assertEqual(self.act(action, manifest=REAL_MANIFEST)[0], 0)
            self.assertEqual(self.calls()[-1], call)

    def test_the_real_screenshot_actions_name_the_script(self):
        for action in ("screenshot.take", "screenshot.pixel"):
            code, message = self.act(action, manifest=REAL_MANIFEST, HOME=self.dir)
            self.assertEqual(code, 1, message)  # the script is not in the fake home; the argv was built and tried
            self.assertIn(os.path.join(self.dir, ".config/hypr/scripts/screenshot.sh"), message)


if __name__ == "__main__":
    unittest.main()
