"""Owner liveness: the Claude-process test on real spawned processes and on a fake /proc, and the release write with
its races."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".local", "lib", "plans"))
from plans import liveness, parse, store  # noqa: E402

DOC = """---
id: demo
project: proj
kind: feature
status: building
owner_session: gone-1
rank: 10
depends_on: []
waiting_on: ""
issue: none
pr: none
branch: none
updated: "2026-11-01"
owner_session_id: id-a
owner_session_pid: {pid}
---
# demo

## Goal
"""
DEAD_PID = 100
LIVE_PID = 200


def fake_proc(directory, claude_pids=(), other_pids=()):
    """A /proc stand-in: `self`, and per pid a comm and a cmdline. Tests point liveness.PROC_ROOT at it, so no test
    judges a real pid it did not spawn."""
    os.makedirs(os.path.join(directory, "self"), exist_ok=True)
    for pids, name in ((claude_pids, "claude"), (other_pids, "sleep")):
        for pid in pids:
            os.makedirs(os.path.join(directory, str(pid)), exist_ok=True)
            with open(os.path.join(directory, str(pid), "comm"), "w", encoding="utf-8") as handle:
                handle.write(name + "\n")
            with open(os.path.join(directory, str(pid), "cmdline"), "wb") as handle:
                handle.write(f"/usr/bin/{name}\0--flag\0".encode())
    return directory


def doc_with(pid_line):
    return parse.Doc("/x/.plans/proj/demo.md", DOC.replace("owner_session_pid: {pid}\n", pid_line))


class RealProcessTest(unittest.TestCase):
    """The real /proc, with only processes this test spawns."""

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.claude = os.path.join(temp.name, "claude")
        shutil.copy(shutil.which("sleep"), self.claude)

    def spawn(self, program):
        process = subprocess.Popen([program, "30"])
        self.addCleanup(process.wait)
        self.addCleanup(process.kill)
        return process

    def test_a_running_claude_is_alive_and_dead_once_it_exits(self):
        process = self.spawn(self.claude)
        self.assertTrue(liveness.pid_runs_claude(process.pid))
        process.kill()
        process.wait()
        self.assertFalse(liveness.pid_runs_claude(process.pid))

    def test_a_pid_that_runs_another_program_is_dead(self):
        self.assertFalse(liveness.pid_runs_claude(self.spawn(shutil.which("sleep")).pid))


class ProcCase(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.proc = fake_proc(os.path.join(temp.name, "proc"), claude_pids=[LIVE_PID], other_pids=[DEAD_PID])
        patcher = mock.patch.object(liveness, "PROC_ROOT", self.proc)
        patcher.start()
        self.addCleanup(patcher.stop)


class FakeProcTest(ProcCase):
    def test_a_doc_without_a_pid_counts_as_alive(self):
        for pid_line in ("", 'owner_session_pid: ""\n', 'owner_session_pid: "abc"\n', "owner_session_pid: 0\n"):
            self.assertTrue(liveness.owner_is_alive(doc_with(pid_line)), pid_line)

    def test_the_stored_pid_decides(self):
        self.assertTrue(liveness.owner_is_alive(doc_with(f"owner_session_pid: {LIVE_PID}\n")))
        self.assertFalse(liveness.owner_is_alive(doc_with(f"owner_session_pid: {DEAD_PID}\n")))
        self.assertFalse(liveness.owner_is_alive(doc_with("owner_session_pid: 999999\n")))

    def test_claude_as_the_first_argument_alone_counts(self):
        with open(os.path.join(self.proc, str(DEAD_PID), "cmdline"), "wb") as handle:
            handle.write(b"/home/u/.local/bin/claude\0")
        self.assertTrue(liveness.pid_runs_claude(DEAD_PID))

    def test_a_missing_proc_counts_as_alive(self):
        with mock.patch.object(liveness, "PROC_ROOT", os.path.join(self.proc, "nowhere")):
            self.assertTrue(liveness.pid_runs_claude(DEAD_PID))

    @unittest.skipIf(os.geteuid() == 0, "root reads a file without read permission")
    def test_an_unreadable_proc_entry_counts_as_alive(self):
        os.chmod(os.path.join(self.proc, str(DEAD_PID), "comm"), 0)
        self.assertTrue(liveness.pid_runs_claude(DEAD_PID))

    def test_any_other_read_error_counts_as_alive(self):
        for error in (PermissionError(13, "denied"), OSError(5, "I/O error")):
            with mock.patch("builtins.open", side_effect=error):
                self.assertTrue(liveness.pid_runs_claude(DEAD_PID), error)

    def test_a_process_that_exits_mid_read_is_dead(self):
        with mock.patch("builtins.open", side_effect=ProcessLookupError(3, "no such process")):
            self.assertFalse(liveness.pid_runs_claude(LIVE_PID))


class ReleaseTest(ProcCase):
    def setUp(self):
        super().setUp()
        plans = os.path.join(os.path.dirname(self.proc), ".plans", "proj")
        os.makedirs(plans)
        self.path = os.path.join(plans, "demo.md")

    def write(self, pid):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(DOC.format(pid=pid))
        return parse.load(self.path)

    def owner_values(self):
        keys = parse.load(self.path).keys
        return keys["owner_session"], keys["owner_session_id"], keys["owner_session_pid"]

    def test_a_dead_owner_is_released_and_a_live_one_kept(self):
        docs, released = liveness.release_dead_owners([self.write(DEAD_PID)])
        self.assertEqual(self.owner_values(), ("none", "", ""))
        self.assertEqual(docs[0].keys["owner_session"], "none")
        self.assertEqual([(release.owner, release.pid) for release in released], [("gone-1", DEAD_PID)])
        live = self.write(LIVE_PID)
        docs, released = liveness.release_dead_owners([live])
        self.assertEqual((docs, released), ([live], []))
        self.assertEqual(self.owner_values(), ("gone-1", "id-a", LIVE_PID))

    def race(self, changes):
        """Release a dead-owned doc while `changes` land on disk between the liveness check and the write."""
        doc = self.write(DEAD_PID)
        real_check = liveness.owner_is_alive

        def check_then_race(checked):
            alive = real_check(checked)
            if not raced:
                raced.append(store.update(parse.load(self.path), changes))
            return alive

        raced = []
        with mock.patch.object(liveness, "owner_is_alive", check_then_race):
            docs, released = liveness.release_dead_owners([doc])
        self.assertEqual((docs, released), ([doc], []))
        return self.owner_values()

    def test_a_reclaim_between_check_and_write_wins(self):
        self.assertEqual(self.race({"owner_session": "new-2", "owner_session_id": "id-b", "owner_session_pid": LIVE_PID}),
                         ("new-2", "id-b", LIVE_PID))

    def test_the_same_name_with_a_new_pid_or_id_wins(self):
        self.assertEqual(self.race({"owner_session_pid": LIVE_PID}), ("gone-1", "id-a", LIVE_PID))
        self.assertEqual(self.race({"owner_session_id": "id-c"}), ("gone-1", "id-c", DEAD_PID))

    def test_the_owner_is_checked_again_under_the_lock(self):
        doc = self.write(DEAD_PID)
        verdicts = iter([False, True])
        with mock.patch.object(liveness, "owner_is_alive", lambda checked: next(verdicts)):
            self.assertEqual(liveness.release_dead_owners([doc]), ([doc], []))
        self.assertEqual(self.owner_values(), ("gone-1", "id-a", DEAD_PID))

    def test_a_vanished_unwritable_or_undecodable_doc_is_kept_quietly(self):
        doc = self.write(DEAD_PID)
        os.unlink(self.path)
        self.assertEqual(liveness.release_dead_owners([doc]), ([doc], []))
        doc = self.write(DEAD_PID)
        for error in (PermissionError(13, "denied"), UnicodeDecodeError("utf-8", b"\xff", 0, 1, "invalid start byte")):
            with mock.patch.object(store, "replace_atomically", side_effect=error):
                self.assertEqual(liveness.release_dead_owners([doc]), ([doc], []))
        self.assertEqual(self.owner_values(), ("gone-1", "id-a", DEAD_PID))


if __name__ == "__main__":
    unittest.main()
