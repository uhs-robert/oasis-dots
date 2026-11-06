"""The board's write side: the write header check, the 409 on a stale page, racing writes, moves and renumbering."""

import os
import socket
import sys
import threading
import unittest

from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_server import Fixture, wait_until  # noqa: E402

from plans import parse, server, store  # noqa: E402

WRITE = {"Content-Type": "application/json", server.WRITE_HEADER: "1"}
# Agent edits go through this, so a test that wraps store.update to step in mid-write does not see them.
AGENT_UPDATE = store.update


class WriteTest(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture(self)
        self.repo = self.fixture.repo("web")

    def add(self, doc_id, rank, **keys):
        return self.fixture.add(self.repo, doc_id, rank, **keys)

    def post(self, action, body, headers=None):
        return self.fixture.request("POST", f"/api/{action}", body, {**WRITE, **(headers or {})})

    def key(self, path, key):
        return parse.load(path).keys[key]

    def agent_sets(self, path, **changes):
        AGENT_UPDATE(parse.load(path), changes)


class WriteHeaderTest(WriteTest):
    def test_a_write_without_the_board_header_or_from_another_origin_is_refused(self):
        path = self.add("demo", 10)
        self.fixture.start()
        body = {"path": path, "basis": {"status": "planned"}, "changes": {"status": "building"}}
        bad_headers = [
            {server.WRITE_HEADER: ""},
            {"Content-Type": "text/plain"},
            {"Origin": "http://evil.example"},
            {"Host": "evil.example"},
        ]
        for headers in bad_headers:
            status, _ = self.post("update", body, headers)
            self.assertEqual(status, 403, headers)
        self.assertEqual(self.key(path, "status"), "planned")
        status, _ = self.post("update", body, {"Origin": f"http://127.0.0.1:{self.fixture.port}"})
        self.assertEqual(status, 200)
        self.assertEqual(self.key(path, "status"), "building")

    def test_a_negative_content_length_is_refused_at_once(self):
        path = self.add("demo", 10)
        self.fixture.start()
        connection = socket.create_connection(("127.0.0.1", self.fixture.port), timeout=5)
        self.addCleanup(connection.close)
        connection.sendall(f"POST /api/update HTTP/1.1\r\nHost: 127.0.0.1:{self.fixture.port}\r\n"
                           f"Content-Type: application/json\r\n{server.WRITE_HEADER}: 1\r\nContent-Length: -1\r\n\r\n"
                           .encode())
        self.assertIn(b" 413 ", connection.recv(4096).split(b"\r\n")[0] + b" ")
        self.assertEqual(self.key(path, "status"), "planned")

    def test_the_board_writes_only_status_and_owner_and_only_valid_values(self):
        path = self.add("demo", 10)
        with open(path, encoding="utf-8") as handle:
            original = handle.read()
        self.fixture.start()
        refused = [
            {"basis": {"pr": "none"}, "changes": {"pr": 5}},
            {"basis": {"updated": "x"}, "changes": {"updated": "x"}},
            {"basis": {"status": "planned"}, "changes": {"status": "finished"}},
            {"basis": {"owner_session": "none"}, "changes": {"owner_session": "Not A Session"}},
            {"basis": {}, "changes": {"status": "building"}},
            {"basis": {"status": None}, "changes": {"status": "building"}},
        ]
        for body in refused:
            status, data = self.post("update", {"path": path, **body})
            self.assertEqual(status, 400, (body, data))
        status, _ = self.post("update", {"path": "/etc/passwd", "basis": {"status": "x"}, "changes": {"status": "done"}})
        self.assertEqual(status, 404)
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), original)

    def test_owner_edits_take_a_session_or_none(self):
        path = self.add("demo", 10)
        self.fixture.start()
        status, _ = self.post("update", {"path": path, "basis": {"owner_session": "none"},
                                         "changes": {"owner_session": "dotfiles-56"}})
        self.assertEqual(status, 200)
        status, _ = self.post("update", {"path": path, "basis": {"owner_session": "dotfiles-56"},
                                         "changes": {"owner_session": "none"}})
        self.assertEqual(status, 200)
        self.assertEqual(self.key(path, "owner_session"), "none")


    def test_an_owner_edit_clears_the_session_values(self):
        path = self.add("demo", 10, owner="me-1")
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text.replace("updated:", "owner_session_id: id-a\nowner_session_pid: 100\nupdated:"))
        self.fixture.start()
        status, _ = self.post("update", {"path": path, "basis": {"owner_session": "me-1"}, "changes": {"owner_session": "other-2"}})
        self.assertEqual(status, 200)
        self.assertEqual([self.key(path, key) for key in ("owner_session", "owner_session_id", "owner_session_pid")], ["other-2", "", ""])


class OwnerEditRaceTest(WriteTest):
    def test_a_claim_the_board_read_after_the_page_refuses_the_owner_edit(self):
        path = self.add("demo", 10, owner="me-1")
        self.fixture.start()
        shown = next(doc for doc in self.fixture.board_json()["repos"][0]["docs"] if doc["path"] == path)
        self.agent_sets(path, owner_session_id="id-a", owner_session_pid=100)

        def board_saw_the_claim():
            return any(doc.get("owner_session_id") == "id-a" for doc in self.fixture.board_json()["repos"][0]["docs"])

        self.assertTrue(wait_until(board_saw_the_claim))
        basis = {key: shown[key] for key in ("owner_session", "owner_session_id", "owner_session_pid")}
        status, _ = self.post("update", {"path": path, "basis": basis, "changes": {"owner_session": "other-2"}})
        self.assertEqual(status, 409)
        self.assertEqual([self.key(path, key) for key in ("owner_session", "owner_session_id")], ["me-1", "id-a"])

    def test_an_owner_edit_on_a_doc_without_values_lands(self):
        path = self.add("demo", 10, owner="me-1")
        self.fixture.start()
        basis = {"owner_session": "me-1", "owner_session_id": "", "owner_session_pid": ""}
        status, _ = self.post("update", {"path": path, "basis": basis, "changes": {"owner_session": "other-2"}})
        self.assertEqual(status, 200)
        self.assertEqual(self.key(path, "owner_session"), "other-2")

    def test_a_save_under_the_same_name_keeps_the_values(self):
        path = self.add("demo", 10, owner="me-1")
        self.agent_sets(path, owner_session_id="id-a", owner_session_pid=100)
        self.fixture.start()
        status, _ = self.post("update", {"path": path, "basis": {"owner_session": "me-1"}, "changes": {"owner_session": "me-1"}})
        self.assertEqual(status, 200)
        self.assertEqual([self.key(path, key) for key in ("owner_session_id", "owner_session_pid")], ["id-a", 100])

    def test_a_claim_during_an_owner_edit_refuses_the_edit(self):
        path = self.add("demo", 10, owner="me-1")
        self.fixture.start()

        def claim_then_write(doc, changes):
            # The owner re-claims after the board read the doc and before the board's write takes the lock.
            AGENT_UPDATE(parse.load(path), {"owner_session_id": "id-a", "owner_session_pid": 100})
            return AGENT_UPDATE(doc, changes)

        with mock.patch.object(server.store, "update", claim_then_write):
            status, _ = self.post("update", {"path": path, "basis": {"owner_session": "me-1"}, "changes": {"owner_session": "other-2"}})
        self.assertEqual(status, 409)
        self.assertEqual([self.key(path, key) for key in ("owner_session", "owner_session_id")], ["me-1", "id-a"])

class ConflictTest(WriteTest):
    def test_an_agent_edit_after_the_page_read_refuses_the_write(self):
        path = self.add("demo", 10)
        self.fixture.start()
        shown = next(doc for doc in self.fixture.board_json()["repos"][0]["docs"] if doc["path"] == path)
        self.agent_sets(path, status="review")
        # The watcher may or may not have read the agent's edit by now. Either way the basis is what the page showed.
        status, data = self.post("update", {"path": path, "basis": {"status": shown["status"]},
                                            "changes": {"status": "building"}})
        self.assertEqual(status, 409)
        self.assertEqual(data["keys"], ["status"])
        self.assertEqual(self.key(path, "status"), "review")

    def test_an_agent_edit_to_another_key_does_not_block_the_write(self):
        path = self.add("demo", 10)
        self.fixture.start()
        self.agent_sets(path, waiting_on="owner: pick")
        status, _ = self.post("update", {"path": path, "basis": {"status": "planned"}, "changes": {"status": "building"}})
        self.assertEqual(status, 200)
        self.assertEqual(self.key(path, "status"), "building")
        self.assertEqual(self.key(path, "waiting_on"), "owner: pick")

    def test_two_writes_at_once_land_one_and_refuse_the_other(self):
        path = self.add("demo", 10)
        self.fixture.start()
        barrier = threading.Barrier(2)
        results = {}

        def write(target):
            barrier.wait()
            results[target] = self.post("update", {"path": path, "basis": {"status": "planned"},
                                                   "changes": {"status": target}})

        for _ in range(10):
            self.agent_sets(path, status="planned")
            results.clear()
            writers = [threading.Thread(target=write, args=(target,)) for target in ("building", "review")]
            for writer in writers:
                writer.start()
            for writer in writers:
                writer.join(10)
            codes = sorted(status for status, _ in results.values())
            self.assertEqual(codes, [200, 409])
            winner = next(target for target, (status, _) in results.items() if status == 200)
            loser = next(data for status, data in results.values() if status == 409)
            self.assertEqual(loser["keys"], ["status"])
            self.assertEqual(self.key(path, "status"), winner)

    def test_a_deleted_doc_is_gone_not_written(self):
        path = self.add("demo", 10)
        self.fixture.start()
        os.unlink(path)
        status, _ = self.post("update", {"path": path, "basis": {"status": "planned"}, "changes": {"status": "done"}})
        self.assertIn(status, (404, 410))
        self.assertFalse(os.path.exists(path))


class MoveTest(WriteTest):
    def move(self, path, status, rank, shown_status="planned", above=None, below=None):
        return self.post("move", {"path": path, "basis": {"status": shown_status, "rank": rank}, "status": status,
                                  "above": above, "below": below})

    def test_a_drop_between_two_cards_takes_the_midpoint(self):
        first, second, moved = self.add("first", 10, status="building"), self.add("second", 20, status="building"), \
            self.add("moved", 50)
        self.fixture.start()
        status, data = self.move(moved, "building", 50, above=first, below=second)
        self.assertEqual((status, data), (200, {"renumbered": 0, "skipped": [], "uncertain": []}))
        self.assertEqual((self.key(moved, "status"), self.key(moved, "rank")), ("building", 15))

    def test_a_drop_at_either_end_or_into_an_empty_column(self):
        only = self.add("only", 30, status="review")
        moved = self.add("moved", 50)
        self.fixture.start()
        self.assertEqual(self.move(moved, "review", 50, below=only)[0], 200)
        self.assertEqual(self.key(moved, "rank"), 20)
        self.assertEqual(self.move(moved, "review", 20, shown_status="review", above=only)[0], 200)
        self.assertEqual(self.key(moved, "rank"), 40)
        self.assertEqual(self.move(moved, "parked", 40, shown_status="review")[0], 200)
        self.assertEqual((self.key(moved, "status"), self.key(moved, "rank")), ("parked", 40))

    def test_no_gap_renumbers_the_repo_in_steps_of_ten(self):
        paths = {doc_id: self.add(doc_id, rank) for doc_id, rank in (("a", 1), ("b", 2), ("c", 3), ("d", 4))}
        self.fixture.start()
        status, data = self.move(paths["d"], "planned", 4, above=paths["a"], below=paths["b"])
        self.assertEqual(status, 200)
        self.assertEqual(data["skipped"], [])
        self.assertEqual({doc_id: self.key(path, "rank") for doc_id, path in paths.items()},
                         {"a": 10, "d": 20, "b": 30, "c": 40})

    def test_a_stale_moved_card_refuses_the_whole_move(self):
        paths = {doc_id: self.add(doc_id, rank) for doc_id, rank in (("a", 1), ("b", 2), ("c", 3))}
        self.fixture.start()
        self.agent_sets(paths["c"], rank=7)
        status, data = self.move(paths["c"], "planned", 3, above=paths["a"], below=paths["b"])
        self.assertEqual(status, 409)
        self.assertEqual(data["keys"], ["rank"])
        self.assertEqual([self.key(paths[doc_id], "rank") for doc_id in "abc"], [1, 2, 7])

    def test_an_agent_edit_mid_renumber_keeps_the_agent_edit(self):
        """While the renumber writes one doc at a time, an agent re-ranks one doc and edits the status of another.
        The re-ranked doc keeps the agent's rank and is reported as skipped. The status edit lands beside the new
        rank. No doc loses an edit."""
        paths = {doc_id: self.add(doc_id, rank) for doc_id, rank in (("a", 1), ("b", 2), ("c", 3), ("d", 4))}
        self.fixture.start()
        real_update = store.update
        calls = []

        def update_with_agent_in_between(doc, changes, date=None):
            calls.append(doc.path)
            if len(calls) == 2:
                self.agent_sets(paths["c"], rank=99)
                self.agent_sets(paths["b"], status="review")
            return real_update(doc, changes, date)

        with mock.patch.object(store, "update", update_with_agent_in_between):
            status, data = self.move(paths["d"], "planned", 4, above=paths["a"], below=paths["b"])
        self.assertEqual(status, 200)
        self.assertEqual([skip["id"] for skip in data["skipped"]], ["c"])
        self.assertEqual(self.key(paths["c"], "rank"), 99)
        self.assertEqual((self.key(paths["b"], "rank"), self.key(paths["b"], "status")), (30, "review"))
        self.assertEqual((self.key(paths["a"], "rank"), self.key(paths["d"], "rank")), (10, 20))

    def test_a_failed_write_answers_json_and_says_it_may_have_landed(self):
        path = self.add("demo", 10)
        self.fixture.start()
        with mock.patch.object(store, "replace_atomically", side_effect=OSError(28, "No space left on device")):
            status, data = self.post("update", {"path": path, "basis": {"status": "planned"},
                                                "changes": {"status": "building"}})
        self.assertEqual(status, 500)
        self.assertTrue(data["maybe_applied"])

    def test_a_renumber_write_that_fails_is_uncertain_not_skipped(self):
        paths = {doc_id: self.add(doc_id, rank) for doc_id, rank in (("a", 1), ("b", 2), ("c", 3), ("d", 4))}
        self.fixture.start()
        real_replace = store.replace_atomically

        def fail_for_c(path, text):
            if path == paths["c"]:
                raise OSError(5, "Input/output error")
            return real_replace(path, text)

        with mock.patch.object(store, "replace_atomically", fail_for_c):
            status, data = self.move(paths["d"], "planned", 4, above=paths["a"], below=paths["b"])
        self.assertEqual(status, 200)
        self.assertEqual(data["skipped"], [])
        self.assertEqual([doc["id"] for doc in data["uncertain"]], ["c"])

    def test_a_neighbour_that_left_refuses_the_move(self):
        moved, gone = self.add("moved", 10), self.add("gone", 20)
        self.fixture.start()
        os.unlink(gone)
        status, _ = self.move(moved, "planned", 10, above=gone)
        self.assertEqual(status, 409)
        self.assertEqual(self.key(moved, "rank"), 10)

    def test_an_agent_rank_edit_refuses_a_drop_that_lands_on_the_shown_rank(self):
        """The page showed rank 15 and the drop lands on 15 again, so the rank looks unchanged. The agent's 50 must
        still refuse the move."""
        first, second = self.add("first", 10, status="building"), self.add("second", 20, status="building")
        moved = self.add("moved", 15)
        self.fixture.start()
        self.agent_sets(moved, rank=50)
        status, data = self.move(moved, "building", 15, above=first, below=second)
        self.assertEqual((status, data.get("keys")), (409, ["rank"]))
        self.assertEqual((self.key(moved, "status"), self.key(moved, "rank")), ("planned", 50))

    def test_neighbours_an_agent_reordered_refuse_the_move(self):
        first, second = self.add("first", 10, status="building"), self.add("second", 11, status="building")
        third = self.add("third", 30, status="building")
        moved = self.add("moved", 50)
        self.fixture.start()
        self.agent_sets(first, rank=40)
        self.agent_sets(second, rank=35)
        status, _ = self.move(moved, "building", 50, above=first, below=second)
        self.assertEqual(status, 409)
        self.assertEqual([self.key(path, "rank") for path in (first, second, third, moved)], [40, 35, 30, 50])

    def test_rank_between(self):
        cases = [((None, 30), 20), ((None, 5), 2), ((None, 0), None), ((10, None), 20), ((10, 20), 15), ((10, 11), None),
                 ((10, 10), None)]
        for (above, below), expected in cases:
            self.assertEqual(server.rank_between(above, below), expected, (above, below))


class OpenTest(WriteTest):
    def test_open_runs_the_editor_in_the_hyprland_terminal(self):
        path = self.add("demo", 10)
        state = os.path.join(self.fixture.temp.name, "state")
        launcher = os.path.join(state, server.HYPR_TERMINAL)
        os.makedirs(os.path.dirname(launcher))
        with open(launcher, "w", encoding="utf-8") as handle:
            handle.write("#!/bin/sh\n")
        os.chmod(launcher, 0o755)
        self.fixture.start()
        with mock.patch.dict(os.environ, {"XDG_STATE_HOME": state, "EDITOR": "vim -u NONE", "VISUAL": ""}), \
                mock.patch.object(server.subprocess, "Popen") as popen:
            status, _ = self.post("open", {"path": path})
        self.assertEqual(status, 200)
        self.assertEqual(popen.call_args.args[0], [launcher, "-e", "vim", "-u", "NONE", path])

    def test_open_reaches_the_doc_behind_an_error_card(self):
        path = self.add("demo", 10)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text.replace("kind: feature", "kind: yes"))
        self.fixture.start()
        with mock.patch.dict(os.environ, {"TERMINAL": "term", "XDG_STATE_HOME": self.fixture.temp.name}), \
                mock.patch.object(server.subprocess, "Popen") as popen:
            status, _ = self.post("open", {"path": path})
            repo_status, _ = self.post("open", {"path": self.repo})
        self.assertEqual(status, 200)
        self.assertEqual(popen.call_args.args[0][-1], path)
        self.assertEqual(repo_status, 404)

    def test_a_bad_editor_or_terminal_is_a_refusal_not_a_dropped_connection(self):
        path = self.add("demo", 10)
        self.fixture.start()
        broken = [{"EDITOR": "vim 'unbalanced", "VISUAL": "", "TERMINAL": "term"},
                  {"EDITOR": "vim", "VISUAL": "", "TERMINAL": "/nonexistent/terminal"}]
        for environment in broken:
            with mock.patch.dict(os.environ, {**environment, "XDG_STATE_HOME": self.fixture.temp.name}):
                status, data = self.post("open", {"path": path})
            self.assertEqual(status, 500, environment)
            self.assertIn("error", data)

    def test_open_without_a_terminal_says_so(self):
        path = self.add("demo", 10)
        self.fixture.start()
        environment = {"XDG_STATE_HOME": self.fixture.temp.name, "TERMINAL": ""}
        with mock.patch.dict(os.environ, environment), mock.patch.object(server.subprocess, "Popen") as popen:
            status, data = self.post("open", {"path": path})
        self.assertEqual(status, 501)
        self.assertIn("TERMINAL", data["error"])
        popen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
