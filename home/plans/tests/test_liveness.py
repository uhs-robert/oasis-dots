"""Owner liveness: the Claude-process test on real spawned processes and on a fake /proc, and the release write with
its races."""

import contextlib
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

    def test_an_interpreted_claude_counts_and_other_node_programs_do_not(self):
        cases = [(["node", "/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js", "--resume"], True),
                 (["/usr/bin/node", "--no-warnings", "/home/u/.npm-global/bin/claude"], True),
                 (["bun", "/home/u/.bun/install/global/node_modules/@anthropic-ai/claude-code/cli.js"], True),
                 (["node", "server.js", "claude"], False), (["node", "-e", "claude"], False),
                 (["node", "-r", "claude", "app.js"], False), (["node"], False)]
        for arguments, expected in cases:
            with self.subTest(arguments=arguments):
                with open(os.path.join(self.proc, str(DEAD_PID), "comm"), "w", encoding="utf-8") as handle:
                    handle.write(os.path.basename(arguments[0]) + "\n")
                with open(os.path.join(self.proc, str(DEAD_PID), "cmdline"), "wb") as handle:
                    handle.write("\0".join(arguments).encode() + b"\0")
                self.assertEqual(liveness.pid_runs_claude(DEAD_PID), expected)

    def test_a_native_claude_under_another_name_counts_by_its_executable(self):
        entry = os.path.join(self.proc, str(DEAD_PID))
        with open(os.path.join(entry, "comm"), "w", encoding="utf-8") as handle:
            handle.write("2.1.0\n")
        with open(os.path.join(entry, "cmdline"), "wb") as handle:
            handle.write(b"/home/u/.local/share/claude/versions/2.1.0\0--resume\0")
        self.assertFalse(liveness.pid_runs_claude(DEAD_PID))
        for executable, expected in (("/home/u/.local/share/claude/versions/2.1.0", True), ("/usr/bin/claudette", False),
                                     ("/home/u/notclaude/bin/2.1.0", False)):
            with self.subTest(executable=executable):
                with contextlib.suppress(FileNotFoundError):
                    os.unlink(os.path.join(entry, "exe"))
                os.symlink(executable, os.path.join(entry, "exe"))
                self.assertEqual(liveness.pid_runs_claude(DEAD_PID), expected)

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


OTHER_HOST = "nightshift.invalid"


def with_host(doc, host):
    return parse.Doc(doc.path, doc.text.replace("updated:", f"owner_host: {host}\nupdated:"))


class OwnerHostTest(ProcCase):
    """A pid means something only on the host that wrote it."""

    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(liveness.socket, "gethostname", return_value="Laptop")
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_a_doc_owned_on_another_host_is_alive_whatever_its_pid(self):
        for pid_line in (f"owner_session_pid: {DEAD_PID}\n", "owner_session_pid: 999999\n", ""):
            doc = with_host(doc_with(pid_line), OTHER_HOST)
            self.assertTrue(liveness.is_remote_owned(doc))
            self.assertTrue(liveness.owner_is_alive(doc), pid_line)

    def test_this_host_in_any_case_or_with_a_root_dot_keeps_the_pid_check(self):
        for host in ("Laptop", "laptop", "LAPTOP.", '""'):
            with self.subTest(host=host):
                dead = with_host(doc_with(f"owner_session_pid: {DEAD_PID}\n"), host)
                self.assertFalse(liveness.is_remote_owned(dead))
                self.assertFalse(liveness.owner_is_alive(dead))
                self.assertTrue(liveness.owner_is_alive(with_host(doc_with(f"owner_session_pid: {LIVE_PID}\n"), host)))

    def test_a_short_and_a_full_name_count_as_different_hosts(self):
        self.assertTrue(liveness.is_remote_owned(with_host(doc_with(""), "laptop.tail1234.ts.net")))

    def test_a_non_string_host_from_a_hand_edit_counts_as_another_host(self):
        doc = with_host(doc_with(f"owner_session_pid: {DEAD_PID}\n"), "5")
        self.assertEqual(doc.keys["owner_host"], 5)
        self.assertTrue(liveness.owner_is_alive(doc))


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

    def test_a_doc_owned_on_another_host_is_never_released(self):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(DOC.format(pid=DEAD_PID).replace("updated:", f"owner_host: {OTHER_HOST}\nupdated:"))
        doc = parse.load(self.path)
        self.assertEqual(liveness.release_dead_owners([doc]), ([doc], []))
        self.assertEqual(self.owner_values(), ("gone-1", "id-a", DEAD_PID))

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


class TakeBackTest(ProcCase):
    def setUp(self):
        super().setUp()
        plans = os.path.join(os.path.dirname(self.proc), ".plans", "proj")
        os.makedirs(plans)
        self.path = os.path.join(plans, "demo.md")

    def write_free(self):
        text = DOC.format(pid='""').replace("owner_session: gone-1", "owner_session: none").replace("owner_session_id: id-a", 'owner_session_id: ""')
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(text.replace("updated:", "last_owner_session: gone-1\nlast_owner_session_id: id-a\nupdated:"))
        return parse.load(self.path)

    def test_a_claim_between_check_and_write_wins(self):
        doc = self.write_free()
        real_update = store.update

        def claim_first(read, changes, **kwargs):
            # Another session claims the doc under the same name first.
            real_update(parse.load(self.path), {"owner_session": "gone-1", "owner_session_id": "id-b", "owner_session_pid": 300})
            return real_update(read, changes, **kwargs)

        with mock.patch.object(store, "update", claim_first):
            self.assertEqual(liveness.take_back([doc], "id-a", LIVE_PID), [])
        keys = parse.load(self.path).keys
        self.assertEqual((keys["owner_session"], keys["owner_session_id"], keys["owner_session_pid"]), ("gone-1", "id-b", 300))

    def test_a_release_between_read_and_lock_is_retried(self):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(DOC.format(pid=DEAD_PID))
        doc = parse.load(self.path)
        real_update = store.update
        released = []

        def release_first(read, changes, **kwargs):
            if not released:
                released.append(read.path)
                liveness.release_dead_owners([parse.load(self.path)])
            return real_update(read, changes, **kwargs)

        with mock.patch.object(store, "update", release_first):
            self.assertEqual(len(liveness.take_back([doc], "id-a", LIVE_PID)), 1)
        keys = parse.load(self.path).keys
        self.assertEqual((keys["owner_session"], keys["owner_session_id"], keys["owner_session_pid"], keys["last_owner_session"]),
                         ("gone-1", "id-a", LIVE_PID, ""))

    def test_a_new_id_after_a_clear_goes_in_only_while_the_pid_still_names_this_session(self):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(DOC.format(pid=LIVE_PID))
        doc = parse.load(self.path)
        self.assertEqual(liveness.take_back([doc], "id-new", LIVE_PID), [])
        self.assertEqual(len(liveness.take_back([doc], "id-new", LIVE_PID, cleared=True)), 1)
        self.assertEqual(parse.load(self.path).keys["owner_session_id"], "id-new")
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(DOC.format(pid=LIVE_PID))
        doc = parse.load(self.path)
        real_update = store.update

        def resume_elsewhere_first(read, changes, **kwargs):
            real_update(parse.load(self.path), {"owner_session_pid": 300})
            return real_update(read, changes, **kwargs)

        with mock.patch.object(store, "update", resume_elsewhere_first):
            self.assertEqual(liveness.take_back([doc], "id-new", LIVE_PID, cleared=True), [])
        self.assertEqual(parse.load(self.path).keys["owner_session_id"], "id-a")

    def test_a_new_pid_goes_in_only_while_the_id_still_names_this_session(self):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(DOC.format(pid=DEAD_PID))
        doc = parse.load(self.path)
        real_update = store.update

        def handoff_first(read, changes, **kwargs):
            real_update(parse.load(self.path), {"owner_session_id": "id-b"})
            return real_update(read, changes, **kwargs)

        with mock.patch.object(store, "update", handoff_first):
            self.assertEqual(liveness.take_back([doc], "id-a", LIVE_PID), [])
        self.assertEqual(parse.load(self.path).keys["owner_session_pid"], DEAD_PID)


class TakeBackHostTest(ProcCase):
    """A take-back is a claim, so it writes this host, and it never touches a doc another host owns."""

    write_free = TakeBackTest.write_free

    def setUp(self):
        super().setUp()
        plans = os.path.join(os.path.dirname(self.proc), ".plans", "proj")
        os.makedirs(plans)
        self.path = os.path.join(plans, "demo.md")
        patcher = mock.patch.object(liveness.socket, "gethostname", return_value="laptop")
        patcher.start()
        self.addCleanup(patcher.stop)

    def write_owned(self, pid, host):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(DOC.format(pid=pid).replace("updated:", f"owner_host: {host}\nupdated:"))
        return parse.load(self.path)

    def test_a_doc_owned_on_another_host_is_left_alone_even_when_the_id_or_pid_matches(self):
        for session_id, pid, cleared in (("id-a", LIVE_PID, False), ("id-new", LIVE_PID, True)):
            with self.subTest(session_id=session_id, cleared=cleared):
                doc = self.write_owned(LIVE_PID if cleared else DEAD_PID, OTHER_HOST)
                before = doc.text
                self.assertEqual(liveness.take_back([doc], session_id, pid, cleared=cleared), [])
                with open(self.path, encoding="utf-8") as handle:
                    self.assertEqual(handle.read(), before)

    def test_each_take_back_writes_this_host(self):
        doc = self.write_free()
        liveness.take_back([doc], "id-a", LIVE_PID)
        self.assertEqual(parse.load(self.path).keys["owner_host"], "laptop")
        doc = self.write_owned(DEAD_PID, '""')
        liveness.take_back([doc], "id-a", LIVE_PID)
        self.assertEqual(parse.load(self.path).keys["owner_host"], "laptop")
        doc = self.write_owned(LIVE_PID, '""')
        liveness.take_back([doc], "id-new", LIVE_PID, cleared=True)
        self.assertEqual(parse.load(self.path).keys["owner_host"], "laptop")


class OwnClaudePidTest(ProcCase):
    def stat(self, pid, parent):
        os.makedirs(os.path.join(self.proc, str(pid)), exist_ok=True)
        with open(os.path.join(self.proc, str(pid), "stat"), "w", encoding="utf-8") as handle:
            handle.write(f"{pid} (sh -c x) S {parent} 1 1\n")

    def test_claude_pid_stands_in_when_no_ancestor_runs_claude(self):
        self.assertEqual(liveness.own_claude_pid({"CLAUDE_PID": str(LIVE_PID)}), LIVE_PID)

    def test_the_nearest_claude_ancestor_wins_over_an_inherited_claude_pid(self):
        # A nested `claude` started from a Bash call inherits the outer session's $CLAUDE_PID.
        fake_proc(self.proc, claude_pids=[201])
        self.stat(500, LIVE_PID)
        with mock.patch.object(os, "getppid", return_value=500):
            self.assertEqual(liveness.own_claude_pid({"CLAUDE_PID": "201"}), LIVE_PID)

    def test_the_nearest_claude_ancestor_stands_in(self):
        self.stat(500, 501)
        self.stat(501, LIVE_PID)
        with mock.patch.object(os, "getppid", return_value=500):
            self.assertEqual(liveness.own_claude_pid({"CLAUDE_PID": str(DEAD_PID)}), LIVE_PID)
            self.assertEqual(liveness.own_claude_pid({}), LIVE_PID)
        self.stat(502, 1)
        with mock.patch.object(os, "getppid", return_value=502):
            self.assertIsNone(liveness.own_claude_pid({}))

    def test_an_unsure_proc_gives_no_pid(self):
        with mock.patch.object(liveness, "PROC_ROOT", os.path.join(self.proc, "nowhere")):
            self.assertIsNone(liveness.own_claude_pid({"CLAUDE_PID": str(LIVE_PID)}))


if __name__ == "__main__":
    unittest.main()
