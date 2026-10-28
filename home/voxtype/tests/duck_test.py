"""Tests for voxtype-duck against a fake wpctl and a fake voxtype. The real audio server is never reached.

  python3 -I home/voxtype/tests/duck_test.py

Each test runs the follower as a process with its own runtime dir and a PATH that holds only the fakes (plus the
system's /usr/bin for cat), then drives it through a FIFO that stands in for `voxtype status --follow`.
"""

import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
DUCK = os.path.join(os.path.dirname(HERE), ".local", "bin", "voxtype-duck")

# A python that never writes bytecode beside the stowed script, whatever runs this file.
FOLLOWER = [sys.executable, "-I", "-B", DUCK]

FAKE_WPCTL = """#!{python}
import json, os, re, sys, time
state_path = os.environ["FAKE_STATE"]
state = json.load(open(state_path))
args = sys.argv[1:]
journal = os.path.exists(os.path.join(os.environ["XDG_RUNTIME_DIR"], "voxcmd", "duck.json"))
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write(json.dumps({{"args": args, "journal": journal, "time": time.time()}}) + "\\n")
if state.get("fail_all") or (args[0] == "set-volume" and state.get("fail_set")):
    sys.exit(1)

def sink_for(name):
    sink_id = state["default"] if name == "@DEFAULT_AUDIO_SINK@" else int(name)
    sink = state["sinks"].get(str(sink_id))
    if sink is None:
        sys.exit(1)
    return sink_id, sink

if args[0] == "inspect":
    sink_id, sink = sink_for(args[1])
    print("id %d, type PipeWire:Interface:Node" % sink_id)
    print('    node.name = "%s"' % sink["name"])
elif args[0] == "get-volume":
    sink_id, sink = sink_for(args[1])
    print("Volume: %.2f%s" % (sink["volume"], " [MUTED]" if sink["muted"] else ""))
elif args[0] == "set-volume":
    time.sleep(state.get("set_delay", 0))
    state = json.load(open(state_path))
    sink_id, sink = sink_for(args[1])
    sink["volume"] = float(args[2])
    json.dump(state, open(state_path + ".wpctl", "w"))
    os.replace(state_path + ".wpctl", state_path)
else:
    sys.exit(2)
"""


def wait_until(condition, timeout=5.0, what="condition"):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.02)
    raise AssertionError("timed out waiting for " + what)


class Rig:
    """A temp sandbox with fakes, and the running follower."""

    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="voxtype-duck-test-")
        self.runtime = os.path.join(self.root, "run")
        self.bin = os.path.join(self.root, "bin")
        os.makedirs(self.runtime)
        os.makedirs(self.bin)
        self.state_path = os.path.join(self.root, "state.json")
        self.log_path = os.path.join(self.root, "wpctl.log")
        self.fifo_path = os.path.join(self.root, "status.fifo")
        os.mkfifo(self.fifo_path)
        self.journal_path = os.path.join(self.runtime, "voxcmd", "duck.json")
        self.voice_env = os.path.join(self.root, "voice.env")
        self.write_script("wpctl", FAKE_WPCTL.format(python=sys.executable))
        self.write_script("voxtype", '#!/bin/sh\nexec cat "$FAKE_FIFO"\n')
        self.set_state(sinks={"79": {"name": "usb", "volume": 1.0, "muted": False},
                              "80": {"name": "hdmi", "volume": 0.5, "muted": False}}, default=79)
        self.env = {
            "PATH": self.bin + ":/usr/bin:/bin",
            "HOME": self.root,
            "XDG_RUNTIME_DIR": self.runtime,
            "XDG_STATE_HOME": os.path.join(self.root, "state"),
            "VOXCMD_VOICE_ENV_FILE": self.voice_env,
            "FAKE_STATE": self.state_path,
            "FAKE_LOG": self.log_path,
            "FAKE_FIFO": self.fifo_path,
        }
        self.proc = None
        self.writer = None

    def write_script(self, name, body):
        path = os.path.join(self.bin, name)
        with open(path, "w") as f:
            f.write(body)
        os.chmod(path, 0o755)

    def set_state(self, **fields):
        state = {}
        if os.path.exists(self.state_path):
            with open(self.state_path) as f:
                state = json.load(f)
        state.update(fields)
        with open(self.state_path + ".new", "w") as f:
            json.dump(state, f)
        os.replace(self.state_path + ".new", self.state_path)

    def sink(self, sink_id=79):
        with open(self.state_path) as f:
            return json.load(f)["sinks"][str(sink_id)]

    def set_sink(self, sink_id=79, **fields):
        with open(self.state_path) as f:
            state = json.load(f)
        state["sinks"][str(sink_id)].update(fields)
        self.set_state(sinks=state["sinks"])

    def calls(self, command):
        if not os.path.exists(self.log_path):
            return []
        with open(self.log_path) as f:
            entries = [json.loads(line) for line in f]
        return [entry for entry in entries if entry["args"][0] == command]

    def volume_writes(self):
        return [float(entry["args"][2]) for entry in self.calls("set-volume")]

    def journal(self):
        try:
            with open(self.journal_path) as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def start(self, extra_env=None):
        env = dict(self.env, **(extra_env or {}))
        self.proc = subprocess.Popen(FOLLOWER, env=env, stderr=subprocess.PIPE)
        self.open_stream()

    def open_stream(self):
        # RDWR never blocks on a FIFO, and closing it ends the follower's `cat` (EOF) like voxtype stopping.
        self.writer = os.open(self.fifo_path, os.O_RDWR)

    def say(self, state):
        os.write(self.writer, (json.dumps({"text": "", "alt": state, "class": state}) + "\n").encode())

    def end_stream(self):
        os.close(self.writer)
        self.writer = None

    def run_once(self, *args):
        return subprocess.run(FOLLOWER + list(args), env=self.env, capture_output=True, text=True, timeout=10)

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        if self.proc:
            self.proc.stderr.close()
        if self.writer is not None:
            os.close(self.writer)
        shutil.rmtree(self.root, ignore_errors=True)


class DuckTest(unittest.TestCase):
    def setUp(self):
        self.rig = Rig()
        self.addCleanup(self.rig.stop)

    def volume_is(self, expected, sink_id=79):
        return lambda: abs(self.rig.sink(sink_id)["volume"] - expected) < 1e-3

    def start_ducked(self, volume=1.0):
        self.rig.set_sink(79, volume=volume)
        self.rig.start()
        self.rig.say("recording")
        wait_until(self.volume_is(volume * 0.3), what="the duck")

    def test_ducks_to_the_percent_and_restores_exactly(self):
        self.rig.set_sink(79, volume=0.8)
        self.rig.start()
        self.rig.say("recording")
        wait_until(self.volume_is(0.24), what="the duck")
        self.assertEqual(self.rig.journal()["saved_volume"], 0.8)
        self.rig.say("idle")
        wait_until(self.volume_is(0.8), what="the restore")
        wait_until(lambda: self.rig.journal() is None, what="the journal to go")

    def test_fade_is_five_descending_steps_ending_on_the_target(self):
        self.rig.start()
        self.rig.say("recording")
        wait_until(self.volume_is(0.3))
        writes = self.rig.volume_writes()
        self.assertEqual(len(writes), 5)
        self.assertEqual(writes, sorted(writes, reverse=True))
        self.assertAlmostEqual(writes[-1], 0.3, places=4)

    def test_journal_exists_before_the_first_volume_write(self):
        self.start_ducked()
        first = self.rig.calls("set-volume")[0]
        self.assertTrue(first["journal"])
        self.rig.say("idle")
        wait_until(lambda: self.rig.journal() is None)
        self.assertTrue(self.rig.calls("set-volume")[-1]["journal"], "the journal outlives the last write")

    def test_restores_when_transcribing_starts(self):
        self.start_ducked()
        self.rig.say("transcribing")
        wait_until(self.volume_is(1.0), what="the restore")

    def test_restore_waits_out_the_hold_off(self):
        self.start_ducked()
        writes_before = len(self.rig.volume_writes())
        self.rig.say("idle")
        time.sleep(0.3)
        self.assertEqual(len(self.rig.volume_writes()), writes_before)
        wait_until(self.volume_is(1.0), what="the restore")

    def test_muted_sink_is_left_alone(self):
        self.rig.set_sink(79, muted=True)
        self.rig.start()
        self.rig.say("recording")
        self.rig.say("idle")
        time.sleep(0.8)
        self.assertEqual(self.rig.volume_writes(), [])
        self.assertIsNone(self.rig.journal())

    def test_a_target_that_would_raise_is_skipped(self):
        self.rig.start()
        self.rig.say("recording")
        self.rig.say("idle")
        with open(self.rig.voice_env, "w") as f:
            f.write("VOXCMD_DUCK_MEDIA_VOLUME=100\n")
        self.rig.say("recording")
        time.sleep(0.4)
        self.assertEqual(self.rig.sink()["volume"], 1.0)

    def test_percent_from_voice_env_and_environment(self):
        with open(self.rig.voice_env, "w") as f:
            f.write("VOXCMD_DUCK_MEDIA_VOLUME=50\n")
        self.rig.start()
        self.rig.say("recording")
        wait_until(self.volume_is(0.5), what="a 50% duck")

    def test_environment_beats_voice_env(self):
        with open(self.rig.voice_env, "w") as f:
            f.write("VOXCMD_DUCK_MEDIA_VOLUME=50\n")
        self.rig.start({"VOXCMD_DUCK_MEDIA_VOLUME": "10"})
        self.rig.say("recording")
        wait_until(self.volume_is(0.1), what="a 10% duck")

    def test_a_bad_value_falls_back_to_thirty(self):
        with open(self.rig.voice_env, "w") as f:
            f.write("VOXCMD_DUCK_MEDIA_VOLUME=loud\n")
        self.rig.start({"VOXCMD_DUCK_MEDIA_VOLUME": "150"})
        self.rig.say("recording")
        wait_until(self.volume_is(0.3), what="a 30% duck")

    def test_user_volume_change_during_the_duck_is_kept(self):
        self.start_ducked()
        self.rig.set_sink(79, volume=0.6)
        self.rig.say("idle")
        wait_until(lambda: self.rig.journal() is None, what="the journal to go")
        self.assertEqual(self.rig.sink()["volume"], 0.6)

    def test_user_mute_during_the_duck_is_kept(self):
        self.start_ducked()
        self.rig.set_sink(79, muted=True)
        self.rig.say("idle")
        wait_until(lambda: self.rig.journal() is None, what="the journal to go")
        self.assertTrue(self.rig.sink()["muted"])
        self.assertAlmostEqual(self.rig.sink()["volume"], 0.3, places=2)

    def test_default_sink_change_restores_the_journalled_sink(self):
        self.start_ducked()
        self.rig.set_state(default=80)
        self.rig.say("idle")
        wait_until(self.volume_is(1.0, 79), what="the first sink's restore")
        self.assertEqual(self.rig.sink(80)["volume"], 0.5)
        wait_until(lambda: self.rig.journal() is None)
        for entry in self.rig.calls("set-volume")[5:]:
            self.assertEqual(entry["args"][1], "79")

    def test_a_journalled_sink_that_is_gone_clears_the_journal(self):
        self.start_ducked()
        with open(self.rig.state_path) as f:
            sinks = json.load(f)["sinks"]
        del sinks["79"]
        self.rig.set_state(sinks=sinks, default=80)
        self.rig.say("idle")
        wait_until(lambda: self.rig.journal() is None, what="the journal to go")
        self.assertEqual(self.rig.sink(80)["volume"], 0.5)

    def test_overlapping_recordings_keep_one_duck_and_the_first_saved_volume(self):
        self.start_ducked(0.8)
        self.rig.say("transcribing")
        time.sleep(0.2)
        self.rig.say("recording")
        time.sleep(0.6)
        self.assertEqual(len(self.rig.volume_writes()), 5)
        self.assertEqual(self.rig.journal()["saved_volume"], 0.8)
        self.rig.say("idle")
        wait_until(self.volume_is(0.8), what="the restore")
        self.assertEqual(len(self.rig.volume_writes()), 10)

    def test_a_pending_restore_is_not_extended_by_later_states(self):
        self.start_ducked()
        self.rig.say("transcribing")
        time.sleep(0.3)
        self.rig.say("idle")
        idle_sent = time.time()
        # Due 200 ms from now; an extended hold-off would start it 500 ms from now. The cap only bounds the wait; the
        # assertion compares the follower's own write time, which test-process scheduling cannot move.
        wait_until(lambda: len(self.rig.volume_writes()) > 5, what="the restore to start")
        self.assertLess(self.rig.calls("set-volume")[5]["time"], idle_sent + 0.5)

    def test_stale_journal_is_restored_at_start(self):
        self.rig.set_sink(79, volume=0.3)
        os.makedirs(os.path.dirname(self.rig.journal_path))
        with open(self.rig.journal_path, "w") as f:
            json.dump({"version": 1, "sink_id": 79, "sink_name": "usb", "saved_volume": 1.0, "saved_muted": False,
                       "ducked_to": 0.3, "last_written": 0.3, "pid": 1}, f)
        self.rig.start()
        wait_until(self.volume_is(1.0), what="the restore at start")
        wait_until(lambda: self.rig.journal() is None)

    def test_stale_journal_cut_off_mid_fade_is_restored(self):
        self.rig.set_sink(79, volume=0.58)
        os.makedirs(os.path.dirname(self.rig.journal_path))
        with open(self.rig.journal_path, "w") as f:
            json.dump({"version": 1, "sink_id": 79, "sink_name": "usb", "saved_volume": 1.0, "saved_muted": False,
                       "ducked_to": 0.3, "last_written": 0.72, "pending": 0.58, "pid": 1}, f)
        self.rig.start()
        wait_until(self.volume_is(1.0), what="the restore at start")

    def test_stale_journal_keeps_a_user_volume_inside_the_duck_range(self):
        self.rig.set_sink(79, volume=0.6)
        os.makedirs(os.path.dirname(self.rig.journal_path))
        with open(self.rig.journal_path, "w") as f:
            json.dump({"version": 1, "sink_id": 79, "sink_name": "usb", "saved_volume": 1.0, "saved_muted": False,
                       "ducked_to": 0.3, "last_written": 0.3, "pending": 0.3, "pid": 1}, f)
        self.rig.start()
        wait_until(lambda: self.rig.journal() is None, what="the journal to go")
        self.assertEqual(self.rig.sink()["volume"], 0.6)

    def test_restore_flag_keeps_a_user_volume_after_a_kill(self):
        self.start_ducked()
        self.rig.proc.kill()
        self.rig.proc.wait()
        self.rig.set_sink(79, volume=0.6)
        self.rig.run_once("--restore")
        self.assertEqual(self.rig.sink()["volume"], 0.6)
        self.assertIsNone(self.rig.journal())

    def test_a_reused_sink_id_is_treated_as_gone(self):
        self.start_ducked()
        self.rig.set_sink(79, name="bluetooth", volume=0.9)
        self.rig.say("idle")
        wait_until(lambda: self.rig.journal() is None, what="the journal to go")
        self.assertEqual(self.rig.sink()["volume"], 0.9)
        self.assertEqual(len(self.rig.volume_writes()), 5)

    def test_stale_journal_with_a_changed_volume_is_dropped_not_restored(self):
        self.rig.set_sink(79, volume=0.9)
        os.makedirs(os.path.dirname(self.rig.journal_path))
        with open(self.rig.journal_path, "w") as f:
            json.dump({"version": 1, "sink_id": 79, "sink_name": "usb", "saved_volume": 0.5, "saved_muted": False,
                       "ducked_to": 0.15, "last_written": 0.15, "pid": 1}, f)
        self.rig.start()
        wait_until(lambda: self.rig.journal() is None, what="the journal to go")
        self.assertEqual(self.rig.sink()["volume"], 0.9)

    def test_restore_flag_without_a_journal_does_nothing(self):
        done = self.rig.run_once("--restore")
        self.assertEqual(done.returncode, 0)
        self.assertEqual(self.rig.calls("set-volume"), [])

    def test_restore_flag_undoes_a_killed_followers_duck(self):
        self.start_ducked()
        self.rig.proc.kill()
        self.rig.proc.wait()
        self.assertIsNotNone(self.rig.journal())
        self.rig.run_once("--restore")
        self.assertAlmostEqual(self.rig.sink()["volume"], 1.0, places=3)
        self.assertIsNone(self.rig.journal())

    def test_sigterm_while_ducked_restores_and_exits(self):
        self.start_ducked()
        self.rig.proc.send_signal(signal.SIGTERM)
        self.rig.proc.wait(5)
        self.assertAlmostEqual(self.rig.sink()["volume"], 1.0, places=3)
        self.assertIsNone(self.rig.journal())

    def test_sigterm_mid_fade_restores(self):
        self.rig.set_state(set_delay=0.15)
        self.rig.start()
        self.rig.say("recording")
        wait_until(lambda: len(self.rig.volume_writes()) >= 2, what="a fade underway")
        self.rig.set_state(set_delay=0)
        self.rig.proc.send_signal(signal.SIGTERM)
        self.rig.proc.wait(5)
        self.assertAlmostEqual(self.rig.sink()["volume"], 1.0, places=3)
        self.assertIsNone(self.rig.journal())

    def test_voxtype_stopping_restores_at_once_and_reconnects(self):
        self.start_ducked()
        writes_before = len(self.rig.calls("set-volume"))
        eof_sent = time.time()
        self.rig.end_stream()
        wait_until(lambda: self.rig.journal() is None, what="the restore on EOF")
        # "At once" means well under the 500 ms hold-off, judged by the fake's write time rather than the poll.
        self.assertLess(self.rig.calls("set-volume")[writes_before]["time"], eof_sent + 0.25)
        self.assertAlmostEqual(self.rig.sink()["volume"], 1.0, places=3)
        self.rig.open_stream()
        # The follower waits one second before reconnecting.
        wait_until(lambda: self.rig.proc.poll() is None)
        time.sleep(1.3)
        self.rig.say("recording")
        wait_until(self.volume_is(0.3), what="a duck on the new stream")

    def test_wpctl_failing_does_not_duck_or_crash(self):
        self.rig.set_state(fail_all=True)
        self.rig.start()
        self.rig.say("recording")
        self.rig.say("idle")
        time.sleep(0.8)
        self.assertIsNone(self.rig.proc.poll())
        self.assertIsNone(self.rig.journal())
        self.rig.set_state(fail_all=False)
        self.rig.say("recording")
        wait_until(self.volume_is(0.3), what="a duck once wpctl works")

    def test_set_volume_failing_leaves_no_journal(self):
        self.rig.set_state(fail_set=True)
        self.rig.start()
        self.rig.say("recording")
        wait_until(lambda: len(self.rig.calls("set-volume")) >= 1, what="the first write")
        time.sleep(0.3)
        self.assertIsNone(self.rig.journal())
        self.assertIsNone(self.rig.proc.poll())
        self.assertEqual(self.rig.sink()["volume"], 1.0)

    def test_status_lines_that_are_not_json_are_ignored(self):
        self.rig.start()
        os.write(self.rig.writer, b"not json\n{broken\n[]\n")
        self.rig.say("recording")
        wait_until(self.volume_is(0.3))


if __name__ == "__main__":
    # Bytecode would land in a __pycache__ inside the stow package.
    sys.dont_write_bytecode = True
    unittest.main()
