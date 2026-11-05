"""The safe write path: stale reads, writes to different keys, racing processes and a crash mid-write."""

import glob
import multiprocessing
import os
import sys
import tempfile
import unittest

from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".local", "lib", "plans"))
from plans import parse, store  # noqa: E402

ORIGINAL = """---
id: demo
project: proj
kind: feature
status: planned
owner_session: none
rank: 10
depends_on: []
waiting_on: ""
issue: none
pr: none
branch: none
updated: "2026-11-01"
---
# demo

## Goal

Body text.
"""
DATE = "2026-11-05"
# Real processes, forked so they share the test's imports. Each round starts new ones.
FORK = multiprocessing.get_context("fork")
RACERS = 8
ROUNDS = 15


def race_writer(path, changes, barrier, results):
    doc = parse.load(path)
    barrier.wait()
    try:
        store.update(doc, changes, DATE)
        results.put(("ok", changes))
    except store.Conflict as error:
        results.put(("conflict", error.keys))


def watch_file(path, allowed, stop, bad):
    """Read the doc over and over while the writers race, and record any text that is no complete state."""
    while not stop.is_set():
        with open(path, encoding="utf-8", newline="") as handle:
            text = handle.read()
        if not allowed(text):
            bad.put(text)
            return


class StoreTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.temp.name, ".plans", "proj", "demo.md")
        os.makedirs(os.path.dirname(self.path))
        self.reset()

    def tearDown(self):
        self.temp.cleanup()

    def reset(self):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(ORIGINAL)

    def contents(self):
        with open(self.path, "rb") as handle:
            return handle.read()

    def leftovers(self):
        return glob.glob(os.path.join(os.path.dirname(self.path), ".*.tmp"))

    def test_lock_is_on_the_plans_dir(self):
        self.assertEqual(store.plans_dir_of(self.path), os.path.join(self.temp.name, ".plans"))

    def test_stale_read_of_a_changed_key_is_refused(self):
        stale, fresh = parse.load(self.path), parse.load(self.path)
        store.update(fresh, {"status": "building"}, "2026-11-04")
        before = self.contents()
        with self.assertRaises(store.Conflict) as caught:
            store.update(stale, {"status": "review", "pr": 5})
        self.assertEqual(caught.exception.keys, ["status"])
        self.assertEqual(self.contents(), before)
        self.assertEqual(self.leftovers(), [])

    def test_stale_body_edit_is_refused(self):
        stale, fresh = parse.load(self.path), parse.load(self.path)
        store.update(fresh, {parse.BODY: "# demo\n\nOne edit.\n"})
        before = self.contents()
        with self.assertRaises(store.Conflict) as caught:
            store.update(stale, {parse.BODY: "# demo\n\nAnother edit.\n"})
        self.assertEqual(caught.exception.keys, [parse.BODY])
        self.assertEqual(self.contents(), before)

    def test_writes_to_different_keys_from_one_read_all_land(self):
        first, second, third = (parse.load(self.path) for _ in range(3))
        store.update(first, {"status": "building"}, "2026-11-06")
        store.update(second, {"waiting_on": "owner: colour"}, "2026-11-07")
        # `updated` changed twice since this read, and this write names it too. It still never conflicts.
        store.update(third, {parse.BODY: "# demo\n\nNew body.\n", "updated": "2000-01-01"}, "2026-11-08")
        doc = parse.load(self.path)
        self.assertEqual(doc.keys["status"], "building")
        self.assertEqual(doc.keys["waiting_on"], "owner: colour")
        self.assertEqual(doc.keys["updated"], "2026-11-08")
        self.assertEqual(doc.body, "# demo\n\nNew body.\n")

    def test_write_keeps_the_file_mode(self):
        os.chmod(self.path, 0o640)
        store.update(parse.load(self.path), {"status": "building"})
        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o640)

    def test_crash_after_the_temp_file_is_written(self):
        doc = parse.load(self.path)
        with mock.patch.object(store.os, "replace", side_effect=RuntimeError("crash")):
            with self.assertRaises(RuntimeError):
                store.update(doc, {"status": "building"})
        self.assertEqual(self.contents(), ORIGINAL.encode())
        self.assertEqual(self.leftovers(), [])

    def test_crash_while_writing_the_temp_file(self):
        doc = parse.load(self.path)
        with mock.patch.object(store.os, "fsync", side_effect=OSError("disk")):
            with self.assertRaises(OSError):
                store.update(doc, {"status": "building"})
        self.assertEqual(self.contents(), ORIGINAL.encode())
        self.assertEqual(self.leftovers(), [])

    def test_create_never_overwrites(self):
        new = os.path.join(self.temp.name, ".plans", "fresh", "new.md")
        store.create(new, "first\n")
        with self.assertRaises(FileExistsError):
            store.create(new, "second\n")
        with open(new) as handle:
            self.assertEqual(handle.read(), "first\n")
        self.assertEqual(glob.glob(os.path.join(os.path.dirname(new), ".*.tmp")), [])

    def race(self, change_sets, allowed):
        """Start one writer per change set from the same read, with a reader watching, and return their results."""
        barrier, results, bad, stop = FORK.Barrier(len(change_sets)), FORK.Queue(), FORK.Queue(), FORK.Event()
        watcher = FORK.Process(target=watch_file, args=(self.path, allowed, stop, bad))
        watcher.start()
        writers = [FORK.Process(target=race_writer, args=(self.path, changes, barrier, results)) for changes in change_sets]
        for writer in writers:
            writer.start()
        outcomes = [results.get(timeout=30) for _ in writers]
        for writer in writers:
            writer.join(timeout=30)
            self.assertEqual(writer.exitcode, 0)
        stop.set()
        watcher.join(timeout=30)
        self.assertTrue(bad.empty(), "the reader saw a mixed or partial file")
        return outcomes

    def test_racing_writes_to_one_key_leave_one_complete_write(self):
        original = parse.Doc(self.path, ORIGINAL)
        change_sets = [{"status": "building", "owner_session": f"racer-{n}"} for n in range(RACERS)]
        complete = {ORIGINAL} | {original.render({**changes, "updated": DATE}) for changes in change_sets}
        for _ in range(ROUNDS):
            self.reset()
            outcomes = self.race(change_sets, lambda text: text in complete)
            winners = [changes for result, changes in outcomes if result == "ok"]
            self.assertEqual(len(winners), 1, outcomes)
            self.assertTrue(all(keys == ["status", "owner_session"] for result, keys in outcomes if result == "conflict"))
            self.assertEqual(self.contents().decode(), original.render({**winners[0], "updated": DATE}))
            self.assertEqual(self.leftovers(), [])

    def test_racing_writes_to_different_keys_all_land(self):
        change_sets = [
            {"status": "building"}, {"waiting_on": "owner: colour"}, {"branch": "feat/x"}, {"pr": 12}, {"issue": 7},
            {"depends_on": ["a", "b"]}, {"rank": 30}, {parse.BODY: "# demo\n\nRaced body.\n"},
        ]
        original = parse.Doc(self.path, ORIGINAL)

        def is_complete_subset(text):
            # Any subset of the writes may have landed, but each key is wholly old or wholly new.
            doc = parse.Doc(self.path, text)
            return not doc.errors and all(doc.value(key) in (original.value(key), value)
                                          for changes in change_sets for key, value in changes.items())

        for _ in range(ROUNDS):
            self.reset()
            outcomes = self.race(change_sets, is_complete_subset)
            self.assertEqual([result for result, _ in outcomes], ["ok"] * len(change_sets))
            everything = {key: value for changes in change_sets for key, value in changes.items()}
            self.assertEqual(self.contents().decode(), original.render({**everything, "updated": DATE}))


if __name__ == "__main__":
    unittest.main()
