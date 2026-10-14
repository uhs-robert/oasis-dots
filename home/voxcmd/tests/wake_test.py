"""Tests for voxcmd-wake's decisions with fake scores, time, audio and commands. No microphone is ever opened.

  python3 -I home/voxcmd/tests/wake_test.py
"""

import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
import stat
import sys
import tempfile
import time
import types
import unittest
import unittest.mock
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
WAKE_PATH = os.path.join(os.path.dirname(HERE), ".local", "bin", "voxcmd-wake")

# Bytecode would land in a __pycache__ inside the stow package.
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("voxcmd_wake", WAKE_PATH)
spec = importlib.util.spec_from_loader("voxcmd_wake", loader)
wake = importlib.util.module_from_spec(spec)
loader.exec_module(wake)

FRAME_SECS = 0.08
THRESHOLD = 0.8


def settings(**overrides):
    values = {"VOXCMD_WAKE_MODEL_DIR": "/nonexistent"}
    values.update(overrides)
    return wake.Settings(values)


class Clock:
    def __init__(self):
        self.now = 100.0
        self.slept = []

    def __call__(self):
        return self.now

    def sleep(self, secs):
        self.slept.append(secs)
        self.now += secs


class FakeSource:
    """Yields frames until its script ends, then the end of the audio. A string item raises SourceEnded at once."""

    def __init__(self, clock, frames):
        self.clock = clock
        self.frames = list(frames)
        self.closed = False

    def read_frame(self, timeout):
        if not self.frames:
            raise wake.SourceEnded()
        item = self.frames.pop(0)
        if item == "end":
            raise wake.SourceEnded()
        self.clock.now += FRAME_SECS
        return item

    def close(self):
        self.closed = True


class ScriptedScorer:
    """Ignores the audio and answers the scripted scores in order."""

    def __init__(self, scores):
        self.scores = list(scores)
        self.resets = 0

    def score(self, frame):
        return self.scores.pop(0)

    def reset(self):
        self.resets += 1


def run_now(work):
    work()


class HeldWork:
    """A spawn that keeps the confirmation's work until release(), so a test can act while it runs."""

    def __init__(self):
        self.pending = []

    def __call__(self, work):
        self.pending.append(work)

    def release(self):
        while self.pending:
            self.pending.pop(0)()


def wav_frames(content):
    """(rate, channels, sample width, frames) of a WAV file's content."""
    with wave.open(io.BytesIO(content)) as wav:
        return wav.getframerate(), wav.getnchannels(), wav.getsampwidth(), wav.readframes(wav.getnframes())


class FakeGate:
    def __init__(self):
        self.paused_now = False
        self.recording = False
        self.reason = None

    def voxtype_recording(self):
        return self.recording

    def paused(self):
        return self.paused_now


def feed(decider, scores, start=100.0):
    """Trigger times (frame index) for the scores, one 80 ms frame apart."""
    triggers = []
    for index, score in enumerate(scores):
        if decider.update(score, start + index * FRAME_SECS):
            triggers.append(index)
    return triggers


def decider(**kwargs):
    values = {"threshold": THRESHOLD, "frames": 3, "cooldown_secs": 3.0}
    values.update(kwargs)
    return wake.TriggerDecider(**values)


class TriggerDeciderTest(unittest.TestCase):
    def test_quiet_and_near_misses_never_trigger(self):
        self.assertEqual(feed(decider(), [0.0, 0.3, 0.79, 0.79, 0.79, 0.0, 0.0]), [])

    def test_two_frames_are_not_enough(self):
        self.assertEqual(feed(decider(), [0.9, 0.95, 0.1, 0.0]), [])

    def test_a_dip_resets_the_run(self):
        self.assertEqual(feed(decider(), [0.9, 0.9, 0.79, 0.9, 0.9, 0.1, 0.0]), [])

    def test_triggers_on_the_frame_that_completes_the_hold_not_after_the_phrase(self):
        scores = [0.0, 0.9, 0.95, 0.99, 0.9, 0.7, 0.2, 0.0]
        self.assertEqual(feed(decider(), scores), [3])

    def test_a_phrase_that_keeps_scoring_high_triggers_once(self):
        self.assertEqual(feed(decider(), [0.9] * 30), [2])

    def test_cooldown_ignores_a_second_phrase(self):
        phrase = [0.9, 0.9, 0.9, 0.1]
        # 3 s is 37 frames; the second phrase starts right after the first.
        self.assertEqual(feed(decider(), phrase + phrase), [2])

    def test_a_phrase_after_the_cooldown_triggers_again(self):
        phrase = [0.9, 0.9, 0.9, 0.1]
        quiet = [0.0] * 40
        self.assertEqual(feed(decider(), phrase + quiet + phrase), [2, 46])

    def test_configured_values_apply(self):
        self.assertEqual(feed(decider(threshold=0.95, frames=5, cooldown_secs=0.0), [0.9] * 6 + [0.0]), [])
        self.assertEqual(feed(decider(threshold=0.95, frames=5, cooldown_secs=0.0), [0.96] * 5 + [0.0]), [4])

    def test_reset_forgets_the_run_but_keeps_the_cooldown(self):
        d = decider()
        feed(d, [0.9, 0.9])
        d.reset()
        self.assertFalse(d.update(0.9, 101.0))
        d.cooldown_until = 200.0
        d.reset()
        self.assertEqual(d.cooldown_until, 200.0)


class SettingsTest(unittest.TestCase):
    def settings_with_file(self, content, env=None):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "voice.env")
            if content is not None:
                with open(path, "w") as f:
                    f.write(content)
            return wake.Settings({"VOXCMD_VOICE_ENV_FILE": path, **(env or {})})

    def test_each_saved_level_maps_to_its_threshold_and_frames(self):
        for level, expected in (("strict", (0.8, 3)), ("balanced", (0.7, 3)), ("relaxed", (0.6, 3))):
            s = self.settings_with_file(f"VOXCMD_WAKE_SENSITIVITY={level}\n")
            self.assertEqual((s.threshold, s.frames), expected, level)

    def test_environment_level_beats_the_file_and_raw_values_beat_the_level(self):
        s = self.settings_with_file("VOXCMD_WAKE_SENSITIVITY=relaxed\n", {"VOXCMD_WAKE_SENSITIVITY": "balanced"})
        self.assertEqual((s.threshold, s.frames), (0.7, 3))
        s = self.settings_with_file("VOXCMD_WAKE_SENSITIVITY=relaxed\n", {"VOXCMD_WAKE_THRESHOLD": "0.9"})
        self.assertEqual((s.threshold, s.frames), (0.9, 3))
        s = self.settings_with_file("VOXCMD_WAKE_SENSITIVITY=relaxed\n", {"VOXCMD_WAKE_FRAMES": "5"})
        self.assertEqual((s.threshold, s.frames), (0.6, 5))

    def test_a_missing_file_and_absent_key_are_strict(self):
        self.assertEqual(self.settings_with_file(None).threshold, 0.8)
        self.assertEqual(self.settings_with_file("VOXCMD_DUCK_MEDIA_VOLUME=20\n").frames, 3)

    def test_a_bad_saved_level_is_strict(self):
        for content in ("VOXCMD_WAKE_SENSITIVITY=loud\n", "VOXCMD_WAKE_SENSITIVITY=3\n", "VOXCMD_WAKE_SENSITIVITY=Strict\n", "VOXCMD_WAKE_SENSITIVITY=\n"):
            s = self.settings_with_file(content)
            self.assertEqual((s.threshold, s.frames), (0.8, 3), msg=content)

    def test_old_threshold_and_frames_lines_in_the_file_are_ignored(self):
        s = self.settings_with_file("VOXCMD_WAKE_THRESHOLD=0.6\nVOXCMD_WAKE_FRAMES=2\n")
        self.assertEqual((s.threshold, s.frames), (0.8, 3))

    def test_an_environment_level_that_is_not_a_level_is_refused(self):
        with self.assertRaises(ValueError):
            wake.Settings({"VOXCMD_WAKE_SENSITIVITY": "loud"})

    def test_the_last_valid_line_wins_and_junk_lines_are_ignored(self):
        s = self.settings_with_file("VOXCMD_WAKE_SENSITIVITY=relaxed\nnonsense\n$(touch x)\nVOXCMD_WAKE_SENSITIVITY=balanced\n")
        self.assertEqual((s.threshold, s.frames), (0.7, 3))

    def test_the_levels_are_the_cortana_models_alone(self):
        self.assertEqual(wake.WAKE_MODEL, "cortana.onnx")
        self.assertEqual(list(wake.SENSITIVITY_LEVELS), ["cortana.onnx"])
        self.assertEqual(sorted(wake.SENSITIVITY_LEVELS["cortana.onnx"]), ["balanced", "relaxed", "strict"])

    def test_the_default_model_dir_is_outside_the_stowed_share_folder(self):
        saved = os.environ.get("XDG_DATA_HOME")
        self.addCleanup(lambda: os.environ.pop("XDG_DATA_HOME") if saved is None else os.environ.__setitem__("XDG_DATA_HOME", saved))
        os.environ["XDG_DATA_HOME"] = "/data"
        self.assertEqual(wake.Settings({}).model_dir, "/data/voxcmd-wake/models")

    def test_defaults_are_the_strict_setting(self):
        s = wake.Settings({})
        self.assertEqual((s.threshold, s.frames, s.cooldown_secs), (0.8, 3, 3.0))

    def test_environment_overrides(self):
        s = wake.Settings(
            {"VOXCMD_WAKE_THRESHOLD": "0.6", "VOXCMD_WAKE_FRAMES": "2", "VOXCMD_WAKE_COOLDOWN_SECS": "5"}
        )
        self.assertEqual((s.threshold, s.frames, s.cooldown_secs), (0.6, 2, 5.0))

    def test_bad_values_are_refused(self):
        for name, value in (
            ("VOXCMD_WAKE_THRESHOLD", "0"),
            ("VOXCMD_WAKE_THRESHOLD", "1.5"),
            ("VOXCMD_WAKE_FRAMES", "0"),
            ("VOXCMD_WAKE_COOLDOWN_SECS", "-1"),
            ("VOXCMD_WAKE_THRESHOLD", "loud"),
        ):
            with self.assertRaises(ValueError, msg=f"{name}={value}"):
                wake.Settings({name: value})


class ListenerTest(unittest.TestCase):
    def build(self, sources, scores, gate=None, verdict=wake.CONFIRMED, spawn=run_now, **env):
        self.clock = Clock()
        self.gate = gate or FakeGate()
        self.listens = 0
        self.verdict = verdict
        self.confirmed_audio = []
        self.states = []
        self.reasons = []
        self.logs = []
        self.scorer = ScriptedScorer(scores)
        self.sources = []
        pending = list(sources)

        def open_source():
            if not pending:
                raise OSError("no more sources")
            source = FakeSource(self.clock, pending.pop(0))
            self.sources.append(source)
            return source

        def run_listen():
            self.listens += 1

        def confirm(wav):
            self.confirmed_audio.append(wav)
            if isinstance(self.verdict, Exception):
                raise self.verdict
            return self.verdict

        self.listener = wake.Listener(
            settings(**env),
            self.scorer,
            open_source,
            self.gate,
            run_listen,
            wake.Confirmation(confirm, spawn),
            self.record_state,
            self.clock,
            self.clock.sleep,
            self.logs.append,
        )

    def record_state(self, state, reason):
        self.states.append(state)
        self.reasons.append(reason)

    def steps(self, count):
        for _ in range(count):
            self.listener.step()

    def test_the_hold_starts_a_confirmation_and_a_confirmed_one_runs_listen(self):
        scores = [0.0, 0.9, 0.95, 0.97, 0.9, 0.3, 0.1, 0.0]
        self.build([[b"f"] * len(scores)], scores)
        self.steps(3)
        self.assertEqual(self.confirmed_audio, [])
        self.steps(1)
        self.assertEqual(len(self.confirmed_audio), 1)
        self.assertEqual(self.listens, 0)
        self.steps(1)
        self.assertEqual(self.listens, 1)
        self.assertIn("confirmed", self.logs)
        self.assertEqual(self.states[0], "armed")
        self.steps(len(scores) - 5)
        self.assertEqual(self.listens, 1)

    def test_a_rejected_trigger_does_nothing_visible(self):
        scores = [0.9, 0.95, 0.97, 0.0, 0.0]
        self.build([[b"f"] * len(scores)], scores, verdict=wake.REJECTED)
        self.steps(len(scores))
        self.assertEqual(len(self.confirmed_audio), 1)
        self.assertEqual(self.listens, 0)
        self.assertIn("rejected", self.logs)
        self.assertEqual(self.states, ["armed"])
        self.assertIsNone(self.listener.ready_deadline)

    def test_a_failed_confirmation_does_not_listen(self):
        for verdict in (wake.CONFIRM_FAILED, RuntimeError("voxcmd broke")):
            scores = [0.9, 0.95, 0.97, 0.0, 0.0]
            self.build([[b"f"] * len(scores)], scores, verdict=verdict)
            self.steps(len(scores))
            self.assertEqual(self.listens, 0, verdict)
            self.assertIn("confirm failed, not listening", self.logs)
            self.assertFalse(self.listener.confirmation.busy())

    def test_the_confirmation_gets_the_last_two_seconds_read_as_a_wav(self):
        count = wake.CONFIRM_AUDIO_FRAMES + 5
        frames = [bytes([index]) * wake.FRAME_BYTES for index in range(count)]
        self.build([frames], [0.0] * (count - 3) + [0.9] * 3)
        self.steps(count)
        self.assertEqual(wake.CONFIRM_AUDIO_FRAMES, 25)
        rate, channels, width, audio = wav_frames(self.confirmed_audio[0])
        self.assertEqual((rate, channels, width), (16000, 1, 2))
        self.assertEqual(audio, b"".join(frames[-wake.CONFIRM_AUDIO_FRAMES:]))

    def test_a_reopened_stream_starts_its_buffer_afresh(self):
        before = [b"\x01\x00" * wake.FRAME_SAMPLES] * 10
        after = [b"\x02\x00" * wake.FRAME_SAMPLES] * 3
        self.build([before, after], [0.0] * 10 + [0.9] * 3)
        self.steps(40)
        self.assertEqual(len(self.sources), 2)
        self.assertEqual(wav_frames(self.confirmed_audio[0])[3], b"".join(after))

    def test_frames_keep_being_read_while_a_confirmation_runs_and_its_triggers_are_skipped(self):
        held = HeldWork()
        phrase = [0.9, 0.9, 0.9, 0.0]
        scores = phrase + [0.0] * 3 + phrase
        self.build([[b"f"] * (len(scores) + 2)], scores + [0.0, 0.0], spawn=held, VOXCMD_WAKE_COOLDOWN_SECS="0")
        self.steps(len(scores))
        self.assertEqual(self.scorer.scores, [0.0, 0.0])
        self.assertEqual(len(held.pending), 1)
        self.assertTrue(any("skipped, still confirming" in line for line in self.logs))
        held.release()
        self.steps(1)
        self.assertEqual(self.listens, 1)
        self.assertEqual(len(self.confirmed_audio), 1)

    def test_a_verdict_that_arrives_while_paused_is_dropped(self):
        held = HeldWork()
        self.build([[b"f"] * 5, [b"f"] * 5], [0.9, 0.95, 0.97] + [0.0] * 7, spawn=held)
        self.steps(3)
        self.gate.paused_now = True
        self.steps(1)
        held.release()
        self.steps(1)
        self.gate.paused_now = False
        self.steps(2)
        self.assertEqual(self.listens, 0)
        self.assertIn("confirmed while paused, dropped", self.logs)

    def test_two_phrases_inside_the_cooldown_run_listen_once(self):
        phrase = [0.9, 0.95, 0.97, 0.1]
        scores = phrase + [0.0] * 5 + phrase + [0.0] * 5
        self.build([[b"f"] * len(scores)], scores)
        self.steps(len(scores))
        self.assertEqual(self.listens, 1)
        self.assertEqual(len(self.confirmed_audio), 1)

    def test_media_playing_closes_the_stream_and_ignores_the_wake_phrase(self):
        self.build([[b"f"] * 5, [b"f"] * 5], [0.0] * 10)
        self.steps(2)
        self.assertFalse(self.sources[0].closed)
        self.gate.paused_now = True
        self.steps(3)
        self.assertTrue(self.sources[0].closed)
        self.assertEqual(len(self.sources), 1)
        self.assertEqual(self.states[-1], "paused")
        self.assertEqual(self.listens, 0)
        self.gate.paused_now = False
        self.steps(1)
        self.assertEqual(len(self.sources), 2)
        self.assertEqual(self.states[-1], "armed")
        self.assertGreaterEqual(self.scorer.resets, 1)

    def test_a_hold_interrupted_by_media_never_runs_listen(self):
        self.build([[b"f"] * 4, [b"f"] * 4], [0.9, 0.95, 0.9, 0.9, 0.0, 0.0, 0.0, 0.0])
        self.steps(2)
        self.gate.paused_now = True
        self.steps(1)
        self.gate.paused_now = False
        self.steps(3)
        self.assertEqual(self.listens, 0)

    def test_ready_is_published_while_the_recording_it_started_is_under_way(self):
        self.build([[b"f"] * 5], [0.9, 0.95, 0.97, 0.0, 0.0])
        self.steps(4)
        self.assertEqual(self.listens, 1)
        self.assertEqual(self.states, ["armed"])
        self.gate.paused_now = True
        self.gate.recording = True
        self.steps(1)
        self.assertEqual(self.states[-1], "ready")
        self.steps(2)
        self.assertEqual(self.states[-1], "ready")
        self.gate.recording = False
        self.steps(1)
        self.assertEqual(self.states[-1], "paused")
        self.gate.paused_now = False
        self.assertIsNone(self.listener.ready_deadline)

    def test_a_recording_that_never_starts_gives_up_the_ready_cue(self):
        self.build([[b"f"] * 3, [b"f"] * 5], [0.9, 0.95, 0.97, 0.0, 0.0, 0.0, 0.0, 0.0])
        self.steps(4)
        self.assertEqual(self.listens, 1)
        self.gate.paused_now = True
        self.steps(1)
        self.assertEqual(self.states[-1], "paused")
        self.clock.now += wake.READY_WAIT_SECS
        self.steps(1)
        self.assertIsNone(self.listener.ready_deadline)

    def test_the_pause_reason_is_published_with_paused_and_cleared_on_resume(self):
        self.build([[b"f"] * 5, [b"f"] * 5], [0.0] * 10)
        self.steps(1)
        self.gate.paused_now = True
        self.gate.reason = "media_playing"
        self.steps(1)
        self.assertEqual((self.states[-1], self.reasons[-1]), ("paused", "media_playing"))
        self.gate.paused_now = False
        self.gate.reason = None
        self.steps(1)
        self.assertEqual((self.states[-1], self.reasons[-1]), ("armed", None))

    def test_a_stream_failure_is_paused_without_a_reason(self):
        self.build([], [])
        self.steps(1)
        self.assertEqual((self.states[-1], self.reasons[-1]), ("paused", None))

    def test_a_recording_the_voice_key_started_is_paused_not_ready(self):
        self.build([[b"f"] * 3], [0.0] * 3)
        self.steps(1)
        self.gate.paused_now = True
        self.gate.recording = True
        self.steps(1)
        self.assertEqual(self.states[-1], "paused")

    def test_pw_record_dying_is_restarted_with_growing_backoff(self):
        self.build([["end"], ["end"], ["end"], [b"f"]], [0.0])
        self.steps(40)
        self.assertEqual(len(self.sources), 4)
        waits = [line for line in self.logs if line.startswith("stream:")]
        self.assertIn("retry in 1s", waits[0])
        self.assertIn("retry in 2s", waits[1])
        self.assertIn("retry in 4s", waits[2])

    def test_a_pw_record_that_cannot_start_is_retried(self):
        self.build([], [])
        self.steps(5)
        self.assertEqual(self.sources, [])
        self.assertTrue(any("cannot start pw-record" in line for line in self.logs))
        self.assertEqual(self.states[-1], "paused")

    def test_backoff_resets_after_a_stable_stream(self):
        long_run = [b"f"] * int(wake.STABLE_STREAM_SECS / FRAME_SECS + 5)
        self.build([["end"], long_run + ["end"], ["end"]], [0.0] * len(long_run))
        self.steps(len(long_run) + 60)
        waits = [line for line in self.logs if line.startswith("stream:")]
        self.assertIn("retry in 1s", waits[0])
        self.assertIn("retry in 1s", waits[1])
        self.assertIn("retry in 2s", waits[2])

    def test_only_scores_and_events_are_logged(self):
        self.build([[b"secret-audio"] * 5], [0.9, 0.95, 0.97, 0.1, 0.0])
        self.steps(6)
        self.assertFalse(any("secret" in line for line in self.logs))
        self.assertTrue(any(line.startswith("trigger score") for line in self.logs))
        self.assertIn("confirmed", self.logs)


class StateFileTest(unittest.TestCase):
    def setUp(self):
        runtime = tempfile.TemporaryDirectory()
        self.addCleanup(runtime.cleanup)
        patcher = unittest.mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": runtime.name})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.state_file = wake.StateFile()

    def written(self):
        with open(self.state_file.path) as handle:
            return json.load(handle)

    def test_a_paused_state_carries_its_reason_and_resuming_drops_it(self):
        self.state_file.publish("paused", "mic_in_use")
        self.assertEqual(self.written()["reason"], "mic_in_use")
        self.state_file.publish("armed")
        self.assertEqual(self.written()["state"], "armed")
        self.assertNotIn("reason", self.written())

    def test_the_file_is_rewritten_only_when_state_or_reason_changes(self):
        self.state_file.publish("paused", "media_playing")
        first = os.stat(self.state_file.path).st_ino
        self.state_file.publish("paused", "media_playing")
        self.assertEqual(os.stat(self.state_file.path).st_ino, first)
        self.state_file.publish("paused", "mic_in_use")
        self.assertEqual(self.written()["reason"], "mic_in_use")
        self.assertNotEqual(os.stat(self.state_file.path).st_ino, first)


class PauseFlagsTest(unittest.TestCase):
    def test_defaults_keep_listening_for_media_and_pause_for_the_mic(self):
        s = wake.Settings({})
        self.assertEqual((s.pause_for_media, s.pause_for_mic), (False, True))

    def test_file_flips_both(self):
        s = SettingsTest().settings_with_file("VOXCMD_WAKE_PAUSE_FOR_MEDIA=1\nVOXCMD_WAKE_PAUSE_FOR_MIC=0\n")
        self.assertEqual((s.pause_for_media, s.pause_for_mic), (True, False))

    def test_environment_beats_the_file(self):
        s = SettingsTest().settings_with_file("VOXCMD_WAKE_PAUSE_FOR_MEDIA=1\n", {"VOXCMD_WAKE_PAUSE_FOR_MEDIA": "0"})
        self.assertFalse(s.pause_for_media)

    def test_a_file_value_other_than_exactly_0_or_1_is_the_default(self):
        for value in ("2", "0.5", "01", "1.0", "0.0", "yes"):
            s = SettingsTest().settings_with_file(f"VOXCMD_WAKE_PAUSE_FOR_MEDIA={value}\nVOXCMD_WAKE_PAUSE_FOR_MIC={value}\n")
            self.assertEqual((s.pause_for_media, s.pause_for_mic), (False, True), value)

    def test_an_environment_value_other_than_0_or_1_is_refused(self):
        with self.assertRaises(ValueError):
            wake.Settings({"VOXCMD_WAKE_PAUSE_FOR_MIC": "yes"})

    def test_media_is_never_asked_when_not_paused_for(self):
        calls = []
        clock = Clock()
        gate = wake.PauseGate(clock, "/nonexistent", lambda: calls.append(1) or True, pause_for_media=False)
        for _ in range(5):
            self.assertFalse(gate.paused())
            clock.now += 2.0
        self.assertEqual(calls, [])

    def test_the_mic_check_pauses_on_the_same_once_a_second_cadence(self):
        calls = []
        clock = Clock()
        gate = wake.PauseGate(clock, "/nonexistent", lambda: False, pause_for_media=False, other_app_recording=lambda: calls.append(1) or True)
        for _ in range(5):
            self.assertTrue(gate.paused())
            clock.now += 0.1
        self.assertEqual(len(calls), 1)

    def test_without_a_mic_check_nothing_is_asked(self):
        gate = wake.PauseGate(Clock(), "/nonexistent", lambda: False, pause_for_media=False)
        self.assertFalse(gate.paused())


def source_output(index, client, source, properties=None, corked=False):
    return {"index": index, "client": str(client), "source": source, "corked": corked, "properties": properties or {}}


def client(index, binary, pid=None, name=None):
    properties = {"application.process.binary": binary, "application.name": name or binary}
    if pid is not None:
        properties["application.process.id"] = str(pid)
    return {"index": index, "properties": properties}


class MicActivityTest(unittest.TestCase):
    MIC, MONITOR, VIRTUAL = 91, 85, 34
    SOURCES = [
        {"index": MIC, "name": "alsa_input.pci-0000_07_00.6.analog-stereo", "properties": {"device.class": "sound"}},
        {"index": MONITOR, "name": "alsa_output.pci.hdmi-stereo.monitor", "properties": {"device.class": "monitor"}},
        {"index": 33, "name": "easyeffects_sink.monitor", "properties": {}},
    ]
    CLIENTS = [
        client(10, "pw-cat", pid=4242),
        client(11, "firefox", pid=3676),
        client(12, "zoom"),
        client(13, "voxtype"),
        client(14, "pw-cat", pid=777),
    ]

    def check(self, outputs, sources=None, clients=None):
        answers = {"source-outputs": outputs, "clients": self.CLIENTS if clients is None else clients, "sources": self.SOURCES if sources is None else sources}
        mic = wake.MicActivity(lambda *args: answers[args[1]])
        return mic.other_app_recording()

    def test_the_listeners_own_tagged_stream_is_not_active(self):
        self.assertFalse(self.check([source_output(1, 10, self.MIC, {"application.name": "pw-record", "voxcmd.tag": "wake"})]))

    def test_autostops_tagged_stream_is_not_active(self):
        self.assertFalse(self.check([source_output(1, 10, self.MIC, {"application.name": "pw-record", "voxcmd.tag": "autostop"})]))

    def test_no_streams_is_not_active(self):
        self.assertFalse(self.check([]))

    def test_firefox_or_zoom_counts(self):
        self.assertTrue(self.check([source_output(1, 11, self.MIC)]))
        self.assertTrue(self.check([source_output(1, 12, self.MIC)]))

    def test_an_untagged_pw_record_user_counts(self):
        self.assertTrue(self.check([source_output(1, 14, self.MIC, {"application.name": "pw-record"})]))

    def test_the_tag_is_on_the_command_lines_of_both_recorders(self):
        with open(wake.__file__) as wake_source, open(os.path.join(os.path.dirname(wake.__file__), "voxcmd-autostop")) as autostop_source:
            self.assertIn("VOICE_STREAM_TAG", wake_source.read())
            self.assertIn('voxcmd.tag = "autostop"', autostop_source.read())

    def test_voxtypes_recording_is_excluded_by_client_or_by_stream(self):
        self.assertFalse(self.check([source_output(1, 13, self.MIC)]))
        self.assertFalse(self.check([source_output(1, 99, self.MIC, {"application.process.binary": "voxtype"})]))

    def test_a_stream_on_a_monitor_is_excluded(self):
        self.assertFalse(self.check([source_output(1, 11, self.MONITOR)]))
        self.assertFalse(self.check([source_output(1, 11, 33)]))

    def test_a_corked_stream_is_not_capturing(self):
        self.assertFalse(self.check([source_output(1, 11, self.MIC, corked=True)]))

    def test_one_counting_stream_among_excluded_ones_is_enough(self):
        outputs = [source_output(1, 10, self.MIC, {"voxcmd.tag": "wake"}), source_output(2, 13, self.MIC), source_output(3, 11, self.MIC)]
        self.assertTrue(self.check(outputs))

    def test_a_missing_or_failing_pactl_is_not_active(self):
        self.assertFalse(wake.MicActivity(lambda *args: None).other_app_recording())
        self.assertFalse(wake.MicActivity(lambda *args: [{"nonsense": 1}]).other_app_recording())

    def test_the_real_reader_survives_a_missing_pactl_and_garbage(self):
        with tempfile.TemporaryDirectory() as tmp:
            old_path = os.environ["PATH"]
            try:
                os.environ["PATH"] = tmp
                self.assertIsNone(wake.pactl_json("list", "source-outputs"))
                stub = os.path.join(tmp, "pactl")
                write_stub(stub, "echo not json")
                self.assertIsNone(wake.pactl_json("list", "source-outputs"))
                write_stub(stub, "exit 1")
                self.assertIsNone(wake.pactl_json("list", "source-outputs"))
                write_stub(stub, "echo '[]'")
                self.assertEqual(wake.pactl_json("list", "source-outputs"), [])
            finally:
                os.environ["PATH"] = old_path


class PauseChecksTest(unittest.TestCase):
    def gate(self, **kwargs):
        return wake.PauseGate(Clock(), "/nonexistent", lambda: False, **kwargs)

    def test_the_checks_run_in_the_documented_order(self):
        gate = self.gate(other_app_recording=lambda: False)
        self.assertEqual([name for name, _ in gate.checks], ["voxtype_recording", "session_open", "media_playing", "mic_in_use"])

    def test_a_disabled_check_is_not_in_the_list(self):
        gate = self.gate(pause_for_media=False)
        self.assertEqual([name for name, _ in gate.checks], ["voxtype_recording", "session_open"])

    def test_a_disabled_check_never_runs_its_probe(self):
        asked = []
        gate = wake.PauseGate(Clock(), "/nonexistent", lambda: asked.append("media") or True, pause_for_media=False)
        self.assertFalse(gate.paused())
        self.assertEqual(asked, [])

    def test_the_reason_names_the_first_check_that_paused(self):
        gate = wake.PauseGate(Clock(), "/nonexistent", lambda: True, other_app_recording=lambda: True)
        self.assertTrue(gate.paused())
        self.assertEqual(gate.reason, "media_playing")
        gate.checks = [c for c in gate.checks if c[0] == "mic_in_use"]
        self.assertTrue(gate.paused())
        self.assertEqual(gate.reason, "mic_in_use")

    def test_nothing_pausing_listens_with_no_reason(self):
        gate = self.gate(other_app_recording=lambda: False)
        self.assertFalse(gate.paused())
        self.assertIsNone(gate.reason)

    def test_a_check_ahead_of_the_rest_can_force_listening(self):
        gate = wake.PauseGate(Clock(), "/nonexistent", lambda: True, other_app_recording=lambda: True)
        gate.checks.insert(0, ("always_listen", lambda: wake.LISTEN))
        self.assertFalse(gate.paused())
        self.assertIsNone(gate.reason)

    def test_a_check_after_a_pause_is_not_asked(self):
        asked = []
        gate = wake.PauseGate(Clock(), "/nonexistent", lambda: True, other_app_recording=lambda: asked.append(1) or True)
        gate.paused()
        self.assertEqual(asked, [])


class PauseGateTest(unittest.TestCase):
    def test_voxtype_recording_pauses_and_other_states_do_not(self):
        with tempfile.TemporaryDirectory() as tmp:
            state_path = os.path.join(tmp, "state")
            clock = Clock()
            gate = wake.PauseGate(clock, state_path, lambda: False)
            self.assertFalse(gate.paused())
            for state, expected in (("recording", True), ("transcribing", False), ("idle", False)):
                with open(state_path, "w") as f:
                    f.write(state + "\n")
                self.assertEqual(gate.paused(), expected, state)

    def test_media_is_asked_at_most_once_a_second(self):
        calls = []
        clock = Clock()
        gate = wake.PauseGate(clock, "/nonexistent", lambda: calls.append(1) or True)
        for _ in range(5):
            self.assertTrue(gate.paused())
            clock.now += 0.1
        self.assertEqual(len(calls), 1)
        clock.now += 1.0
        gate.paused()
        self.assertEqual(len(calls), 2)


class SessionPauseTest(unittest.TestCase):
    """A session is open while session.json names an owner whose pid and start time still match."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.session_path = os.path.join(self.tmp.name, "session.json")
        self.gate = wake.PauseGate(Clock(), "/nonexistent", lambda: False, self.session_path)

    def write_session(self, **state):
        with open(self.session_path, "w") as f:
            json.dump(state, f)

    def test_no_file_is_not_a_session(self):
        self.assertFalse(self.gate.paused())

    def test_a_live_owner_pauses(self):
        self.write_session(owner=os.getpid(), owner_start=self.gate.process_start_time(os.getpid()))
        self.assertTrue(self.gate.paused())

    def test_a_reused_pid_with_another_start_time_does_not(self):
        self.write_session(owner=os.getpid(), owner_start="1")
        self.assertFalse(self.gate.paused())

    def test_a_dead_owner_does_not(self):
        self.write_session(owner=2**22 + 12345, owner_start="123")
        self.assertFalse(self.gate.paused())

    def test_an_unreadable_file_does_not(self):
        with open(self.session_path, "w") as f:
            f.write("{")
        self.assertFalse(self.gate.paused())

    def test_a_session_closes_the_stream(self):
        gate = FakeGate()
        clock = Clock()
        listener = wake.Listener(
            settings(), ScriptedScorer([0.0] * 5), lambda: FakeSource(clock, [b"f"] * 5), gate, lambda: None,
            wake.Confirmation(lambda wav: wake.REJECTED, run_now), lambda state, reason: None, clock, clock.sleep, lambda message: None,
        )
        listener.step()
        source = listener.source
        gate.paused_now = True
        listener.step()
        self.assertTrue(source.closed)


def write_stub(path, body):
    with open(path, "w") as stub:
        stub.write("#!/bin/sh\n" + body)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


class StubbedCommandsTest(unittest.TestCase):
    """The real pw-record reader, playerctl check and listen call, against stubs: PATH holds nothing else."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bin = os.path.join(self.tmp.name, "bin")
        os.mkdir(self.bin)
        self.calls = os.path.join(self.tmp.name, "calls")
        self.pcm = os.path.join(self.tmp.name, "audio.pcm")
        with open(self.pcm, "wb") as pcm:
            pcm.write(b"\x01\x00" * wake.FRAME_SAMPLES * 6 + b"\x01")
        write_stub(os.path.join(self.bin, "pw-record"), f'echo "pw-record $*" >>"{self.calls}"\n/bin/cat "{self.pcm}"\n')
        write_stub(os.path.join(self.bin, "playerctl"), f'echo "playerctl $*" >>"{self.calls}"\nprintf "%b\\n" "$PLAYERCTL_ANSWER"\n')
        # _wake-confirm keeps a copy of the audio it got, notes where its stdin points, and exits $CONFIRM_EXIT.
        self.heard = os.path.join(self.tmp.name, "heard.wav")
        write_stub(
            os.path.join(self.bin, "voxcmd"),
            f'echo "voxcmd $*" >>"{self.calls}"\n'
            '[ "$1" = _wake-confirm ] || exit 0\n'
            f'echo "stdin $(/usr/bin/readlink /proc/$$/fd/0) timeout=$VOXCMD_WAKE_CONFIRM_TIMEOUT_SECS" >>"{self.calls}"\n'
            f'/bin/cat "$2" >"{self.heard}"\n'
            '[ -z "$CONFIRM_SLEEP" ] || /bin/sleep "$CONFIRM_SLEEP"\n'
            'exit "${CONFIRM_EXIT:-0}"\n',
        )
        saved = {k: os.environ.get(k) for k in ("PATH", "VOXCMD_WAKE_VOXCMD", "PLAYERCTL_ANSWER", "XDG_RUNTIME_DIR", "CONFIRM_EXIT", "CONFIRM_SLEEP")}
        self.addCleanup(lambda: [os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v) for k, v in saved.items()])
        os.environ["PATH"] = self.bin
        os.environ["VOXCMD_WAKE_VOXCMD"] = os.path.join(self.bin, "voxcmd")
        os.environ["XDG_RUNTIME_DIR"] = self.tmp.name
        os.environ["PLAYERCTL_ANSWER"] = "Paused"

    def recorded(self):
        with open(self.calls) as calls:
            return calls.read().splitlines()

    def run_listener(self, scores, stop_after):
        clock = Clock()
        states = []
        self.logs = []
        listener = wake.Listener(
            settings(),
            ScriptedScorer(scores),
            wake.PwRecordSource,
            wake.PauseGate(clock, os.path.join(self.tmp.name, "voxtype-state"), wake.playerctl_playing),
            wake.make_run_listen(lambda message: None),
            wake.Confirmation(wake.make_run_confirm(self.logs.append), run_now),
            lambda state, reason: states.append(state),
            clock,
            clock.sleep,
            lambda message: None,
        )
        for _ in range(stop_after):
            listener.step()
        listener.close_stream()
        return states

    def test_reads_80ms_frames_from_pw_record_and_runs_listen_once(self):
        states = self.run_listener([0.9, 0.95, 0.97, 0.1, 0.0, 0.0], 6)
        calls = self.recorded()
        self.assertIn('pw-record -P { voxcmd.tag = "wake" } --rate 16000 --channels 1 --format s16 --raw -', calls)
        self.assertEqual(calls.count("voxcmd _wake-confirm /dev/stdin"), 1)
        self.assertEqual(calls.count("voxcmd listen --start-only"), 1)
        self.assertLess(calls.index("voxcmd _wake-confirm /dev/stdin"), calls.index("voxcmd listen --start-only"))
        self.assertEqual(states[0], "armed")

    def test_the_confirmation_reads_the_audio_from_an_anonymous_memfd(self):
        self.run_listener([0.9, 0.95, 0.97, 0.0], 4)
        stdin_lines = [call for call in self.recorded() if call.startswith("stdin ")]
        self.assertEqual(len(stdin_lines), 1)
        self.assertTrue(stdin_lines[0].startswith("stdin /memfd:voxcmd-wake-audio"), stdin_lines[0])
        self.assertTrue(stdin_lines[0].endswith(f"timeout={wake.CONFIRM_TIMEOUT_SECS}"))
        with open(self.heard, "rb") as heard:
            rate, channels, width, audio = wav_frames(heard.read())
        self.assertEqual((rate, channels, width), (16000, 1, 2))
        self.assertEqual(audio, b"\x01\x00" * wake.FRAME_SAMPLES * 3)

    def test_a_rejected_confirmation_never_runs_listen(self):
        os.environ["CONFIRM_EXIT"] = "1"
        self.run_listener([0.9, 0.95, 0.97, 0.0, 0.0, 0.0], 6)
        self.assertEqual(self.recorded().count("voxcmd _wake-confirm /dev/stdin"), 1)
        self.assertNotIn("voxcmd listen --start-only", self.recorded())

    def test_a_failing_confirmation_is_logged_and_never_runs_listen(self):
        os.environ["CONFIRM_EXIT"] = "2"
        self.run_listener([0.9, 0.95, 0.97, 0.0, 0.0, 0.0], 6)
        self.assertNotIn("voxcmd listen --start-only", self.recorded())
        self.assertIn("confirm exit 2", self.logs)

    def test_a_confirmation_that_outlasts_its_cap_is_killed_as_a_failure(self):
        for attribute, value in (("CONFIRM_TIMEOUT_SECS", 0.2), ("CONFIRM_KILL_GRACE_SECS", 0.3)):
            self.addCleanup(setattr, wake, attribute, getattr(wake, attribute))
            setattr(wake, attribute, value)
        os.environ["CONFIRM_SLEEP"] = "20"
        logs = []
        started = time.monotonic()
        self.assertEqual(wake.make_run_confirm(logs.append)(wake.wav_bytes([b"\0\0"])), wake.CONFIRM_FAILED)
        self.assertLess(time.monotonic() - started, 5)
        self.assertEqual(logs, ["confirm timed out"])

    def test_a_missing_voxcmd_is_a_failure(self):
        os.environ["VOXCMD_WAKE_VOXCMD"] = os.path.join(self.tmp.name, "nonexistent")
        logs = []
        self.assertEqual(wake.make_run_confirm(logs.append)(wake.wav_bytes([b"\0\0"])), wake.CONFIRM_FAILED)
        self.assertTrue(logs[0].startswith("confirm could not run"))

    def test_the_real_worker_thread_hands_back_a_verdict(self):
        confirmation = wake.Confirmation(lambda wav: wake.REJECTED)
        confirmation.start(b"")
        deadline = time.monotonic() + 5
        verdict = None
        while verdict is None and time.monotonic() < deadline:
            verdict = confirmation.take_verdict()
            time.sleep(0.01)
        self.assertEqual(verdict, wake.REJECTED)
        self.assertFalse(confirmation.busy())

    def test_playing_media_never_starts_pw_record(self):
        os.environ["PLAYERCTL_ANSWER"] = "Playing"
        self.run_listener([], 3)
        self.assertFalse([call for call in self.recorded() if call.startswith("pw-record")])

    def test_any_playing_player_pauses_even_after_a_paused_one(self):
        os.environ["PLAYERCTL_ANSWER"] = "Paused\nPlaying"
        self.run_listener([], 3)
        self.assertFalse([call for call in self.recorded() if call.startswith("pw-record")])
        self.assertIn("playerctl --all-players status", self.recorded())


class FetchModelsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.source_dir = os.path.join(self.tmp.name, "release")
        self.target_dir = os.path.join(self.tmp.name, "models")
        os.mkdir(self.source_dir)
        os.mkdir(self.target_dir)
        self.hashes = {}
        for name in wake.MODEL_FILES:
            content = name.encode()
            with open(os.path.join(self.source_dir, name), "wb") as f:
                f.write(content)
            self.hashes[name] = hashlib.sha256(content).hexdigest()
        for attribute, value in (
            ("MODEL_RELEASE_URL", "file://" + self.source_dir + "/"),
            ("MODEL_SHA256", self.hashes),
        ):
            original = getattr(wake, attribute)
            setattr(wake, attribute, value)
            self.addCleanup(setattr, wake, attribute, original)
        self.notices = []
        self.settings = wake.Settings({"VOXCMD_WAKE_MODEL_DIR": self.target_dir})

    def fetch(self):
        wake.fetch_models(self.settings, lambda s, b: self.notices.append(b))

    def target(self, name):
        return os.path.join(self.target_dir, name)

    def test_downloads_missing_models_and_skips_verified_ones(self):
        with open(self.target(wake.MODEL_FILES[0]), "wb") as f:
            f.write(wake.MODEL_FILES[0].encode())
        self.fetch()
        for name in wake.MODEL_FILES:
            with open(self.target(name), "rb") as f:
                self.assertEqual(f.read(), name.encode())
        self.assertEqual(len(self.notices), 1)
        self.assertEqual([n for n in os.listdir(self.target_dir) if n.endswith(".part")], [])

    def test_a_download_with_the_wrong_hash_is_deleted_and_refused(self):
        with open(os.path.join(self.source_dir, wake.MODEL_FILES[1]), "wb") as f:
            f.write(b"tampered")
        with self.assertRaises(wake.ModelHashMismatch):
            self.fetch()
        self.assertEqual(os.listdir(self.target_dir), [wake.MODEL_FILES[0]])

    def test_a_present_file_with_the_wrong_hash_is_fetched_again(self):
        with open(self.target(wake.MODEL_FILES[1]), "wb") as f:
            f.write(b"corrupt")
        self.fetch()
        with open(self.target(wake.MODEL_FILES[1]), "rb") as f:
            self.assertEqual(f.read(), wake.MODEL_FILES[1].encode())

    def test_a_present_file_with_the_wrong_hash_is_not_used_to_start(self):
        self.fetch()
        # The packages stand in as present, so only the model files decide.
        for module in ("numpy", "openwakeword"):
            self.addCleanup(sys.modules.pop, module, None)
            sys.modules[module] = types.ModuleType(module)
        self.assertIsNone(wake.missing_setup(self.settings))
        with open(self.target(wake.MODEL_FILES[0]), "wb") as f:
            f.write(b"corrupt")
        self.assertIn("pinned release file", wake.missing_setup(self.settings))

    def test_only_the_feature_models_are_fetched(self):
        self.assertEqual(wake.MODEL_FILES, ("melspectrogram.onnx", "embedding_model.onnx"))
        self.fetch()
        self.assertEqual(sorted(os.listdir(self.target_dir)), sorted(wake.MODEL_FILES))

    def fake_packages(self):
        for module in ("numpy", "openwakeword"):
            self.addCleanup(sys.modules.pop, module, None)
            sys.modules[module] = types.ModuleType(module)

    def test_the_tracked_wake_model_is_the_pinned_one_and_is_checked_before_a_start(self):
        self.assertEqual(wake.file_sha256(wake.wake_model_path()), wake.WAKE_MODEL_SHA256)
        self.fetch()
        self.fake_packages()
        self.assertIsNone(wake.missing_setup(self.settings))
        self.addCleanup(setattr, wake, "WAKE_MODEL_SHA256", wake.WAKE_MODEL_SHA256)
        wake.WAKE_MODEL_SHA256 = "0" * 64
        self.assertIn("not the tracked model", wake.missing_setup(self.settings))

    def test_a_missing_wake_model_stops_a_start(self):
        self.fetch()
        self.fake_packages()
        self.addCleanup(setattr, wake, "SHARE_DIR", wake.SHARE_DIR)
        wake.SHARE_DIR = self.tmp.name
        self.assertIn("cortana.onnx is not in", wake.missing_setup(self.settings))

    def test_main_fetch_exits_non_zero_on_a_mismatch(self):
        with open(os.path.join(self.source_dir, wake.MODEL_FILES[0]), "wb") as f:
            f.write(b"tampered")
        saved = os.environ.get("VOXCMD_WAKE_MODEL_DIR")
        os.environ["VOXCMD_WAKE_MODEL_DIR"] = self.target_dir
        self.addCleanup(lambda: os.environ.pop("VOXCMD_WAKE_MODEL_DIR") if saved is None else os.environ.__setitem__("VOXCMD_WAKE_MODEL_DIR", saved))
        original_notify = wake.notify_error
        wake.notify_error = lambda summary, body: None
        self.addCleanup(setattr, wake, "notify_error", original_notify)
        self.assertEqual(wake.main(["--fetch-models"]), wake.EXIT_ERROR)
        self.assertEqual(os.listdir(self.target_dir), [])


class ModelTest(unittest.TestCase):
    """Needs python-openwakeword and the models in the default model dir; skipped without them."""

    def test_silence_scores_low(self):
        s = wake.Settings({})
        if wake.missing_setup(s):
            self.skipTest(wake.missing_setup(s))
        scorer = wake.load_scorer(s)
        for _ in range(20):
            self.assertLess(scorer.score(b"\x00\x00" * wake.FRAME_SAMPLES), 0.1)


if __name__ == "__main__":
    unittest.main(verbosity=1)
