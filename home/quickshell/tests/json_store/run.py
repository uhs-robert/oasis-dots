"""Lifecycle tests for core/JsonStore.qml and the FileView write it relies on, run in a headless qs.

Each scenario gets a fresh XDG_STATE_HOME, runs shell.qml with SCENARIO set, and is judged here from the result file
the shell prints and from what happened on disk. A directory watch (inotify through ctypes) records how files arrived.

  python3 -B run.py [scenario...]
"""

import ctypes
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
STORE_SOURCE = os.path.join(HERE, "..", "..", ".config", "quickshell", "core", "JsonStore.qml")

IN_MOVED_FROM, IN_MOVED_TO, IN_CREATE, IN_CLOSE_WRITE = 0x40, 0x80, 0x100, 0x8
EVENT_HEAD = struct.Struct("iIII")


class Watch:
    """Records (time, mask, name) for every event in one directory until stop()."""

    def __init__(self, directory):
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        self.fd = libc.inotify_init1(os.O_NONBLOCK)
        libc.inotify_add_watch(self.fd, directory.encode(), IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_CLOSE_WRITE)
        self.events = []
        self.running = True
        self.thread = threading.Thread(target=self.loop, daemon=True)
        self.thread.start()

    def loop(self):
        while self.running:
            try:
                data = os.read(self.fd, 4096)
            except BlockingIOError:
                time.sleep(0.005)
                continue
            offset = 0
            while offset < len(data):
                _, mask, _, length = EVENT_HEAD.unpack_from(data, offset)
                name = data[offset + EVENT_HEAD.size : offset + EVENT_HEAD.size + length].rstrip(b"\0").decode()
                self.events.append((time.monotonic(), mask, name))
                offset += EVENT_HEAD.size + length

    def stop(self):
        self.running = False
        self.thread.join()
        os.close(self.fd)


def run_qs(scenario, state_home, prepare=None):
    """Runs the harness shell once; returns (result dict or None, qs output)."""
    cfg = os.path.join(state_home, "cfg")
    os.makedirs(cfg)
    shutil.copy(os.path.join(HERE, "shell.qml"), cfg)
    if os.path.exists(STORE_SOURCE):
        shutil.copy(STORE_SOURCE, cfg)
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update(
        QT_QPA_PLATFORM="offscreen",
        SCENARIO=scenario,
        XDG_STATE_HOME=os.path.join(state_home, "state"),
        XDG_RUNTIME_DIR=os.path.join(state_home, "run"),
        HOME=os.path.join(state_home, "home"),
    )
    for name in ("state", "run", "home"):
        os.makedirs(os.path.join(state_home, name), mode=0o700, exist_ok=True)
    proc = subprocess.run(["qs", "-p", cfg], env=env, capture_output=True, text=True, timeout=20)
    out = "qs exit code %d\n" % proc.returncode + proc.stdout + proc.stderr
    try:
        with open(os.path.join(state_home, "state", "result.json")) as f:
            return json.load(f), out
    except (FileNotFoundError, ValueError):
        return None, out


def scenario_atomic(state_home):
    store_dir = os.path.join(state_home, "state", "json_store")
    os.makedirs(store_dir)
    target = os.path.join(store_dir, "atomic.json")
    watch = Watch(store_dir)
    inodes = []

    def record_inode():
        while watch.running:
            try:
                inodes.append(os.stat(target).st_ino)
            except FileNotFoundError:
                pass
            time.sleep(0.02)

    sampler = threading.Thread(target=record_inode, daemon=True)
    sampler.start()
    result, out = run_qs("atomic", state_home)
    watch.stop()
    sampler.join()
    inodes.append(os.stat(target).st_ino)
    problems = []
    if result is None:
        return ["no result file:\n" + out]
    if result.get("saves") != 2 or result.get("failures"):
        problems.append("saved/saveFailed did not fire as expected: %r" % result)
    renamed_in = [e for e in watch.events if e[1] & IN_MOVED_TO and e[2] == "atomic.json"]
    sources = [e for e in watch.events if e[1] & IN_MOVED_FROM and e[2] != "atomic.json"]
    if not renamed_in or not sources:
        problems.append("second write was not a rename over the target (events: %r)" % watch.events)
    if len(set(inodes)) < 2:
        problems.append("target inode never changed (%r)" % sorted(set(inodes)))
    with open(target) as f:
        if f.read() != '{"n":2}':
            problems.append("target holds the wrong text")
    return problems


def store_run(name, state_home, seed=None, extra=None):
    """Runs a store scenario with an optional seed for store.json; returns (result, dir, problems so far)."""
    store_dir = os.path.join(state_home, "state", "json_store")
    os.makedirs(store_dir)
    if seed is not None:
        with open(os.path.join(store_dir, "store.json"), "w") as f:
            f.write(seed)
    if extra:
        extra(store_dir)
    result, out = run_qs(name, state_home)
    problems = [] if result is not None else ["no result file:\n" + out]
    return result, store_dir, problems


def read(store_dir, name="store.json"):
    with open(os.path.join(store_dir, name)) as f:
        return f.read()


def expect(problems, label, got, want):
    if got != want:
        problems.append("%s: got %r, want %r" % (label, got, want))


def scenario_firstrun(state_home):
    result, store_dir, problems = store_run("firstrun", state_home)
    if problems:
        return problems
    # The scenario's store lives in a directory that did not exist.
    expect(problems, "file written", json.loads(read(os.path.join(store_dir, "absent", "deeper"))), {"a": 1, "b": 0})
    expect(problems, "saved signals", result["saved_count"], 1)
    return problems


def scenario_no_write_before_set(state_home):
    result, store_dir, problems = store_run("no_write_before_set", state_home)
    if problems:
        return problems
    expect(problems, "dir created by a load", os.path.exists(os.path.join(store_dir, "absent")), False)
    expect(problems, "values", result["values"], {"a": 0, "b": 0})
    return problems


def scenario_echo(state_home):
    result, store_dir, problems = store_run("echo", state_home)
    if problems:
        return problems
    want = {"a": 8, "b": 8}
    expect(problems, "final values", result["values"], want)
    expect(problems, "final disk", json.loads(read(store_dir)), want)
    expect(problems, "loaded() only for the missing file at start", result["loaded_count"], 1)
    expect(problems, "failures", result["failures"], [])
    return problems


def scenario_immediate(state_home):
    result, store_dir, problems = store_run("immediate", state_home)
    if problems:
        return problems
    expect(problems, "final values", result["values"], {"a": 5, "b": 0})
    expect(problems, "final disk", json.loads(read(store_dir)), {"a": 5, "b": 0})
    expect(problems, "loaded() churn from echoes", result["loaded_count"], 1)
    return problems


def scenario_immediate_spaced(state_home):
    result, store_dir, problems = store_run("immediate_spaced", state_home)
    if problems:
        return problems
    expect(problems, "final disk", json.loads(read(store_dir)), {"a": 5, "b": 0})
    expect(problems, "one write per set", result["saved_count"], 5)
    expect(problems, "loaded() churn from echoes", result["loaded_count"], 1)
    expect(problems, "dirty/writing cleared", (result["dirty"], result["writing"]), (False, False))
    return problems


def scenario_early_set(state_home):
    result, store_dir, problems = store_run("early_set", state_home, seed='{"a":5,"x":1,"pins":[1]}')
    if problems:
        return problems
    expect(problems, "disk: set key wins, the rest kept", json.loads(read(store_dir)), {"x": 1, "pins": [1], "a": 5, "b": 7})
    expect(problems, "values", result["values"], {"a": 5, "b": 7})
    expect(problems, "dirty/writing cleared", (result["dirty"], result["writing"]), (False, False))
    return problems


def scenario_early_set_debounced(state_home):
    result, store_dir, problems = store_run("early_set_debounced", state_home, seed='{"a":5,"x":1}')
    if problems:
        return problems
    expect(problems, "disk", json.loads(read(store_dir)), {"x": 1, "a": 5, "b": 7})
    expect(problems, "dirty/writing cleared", (result["dirty"], result["writing"]), (False, False))
    return problems


def scenario_early_replace(state_home):
    result, store_dir, problems = store_run("early_replace", state_home, seed='{"old":{"count":2}}')
    if problems:
        return problems
    expect(problems, "disk keeps the entries it had not read", json.loads(read(store_dir)), {"old": {"count": 2}, "new": 1})
    return problems


def scenario_early_set_missing(state_home):
    result, store_dir, problems = store_run("early_set_missing", state_home)
    if problems:
        return problems
    expect(problems, "disk", json.loads(read(store_dir)), {"a": 0, "b": 7})
    return problems


def scenario_corrupt(state_home):
    result, store_dir, problems = store_run("corrupt", state_home, seed="{")
    if problems:
        return problems
    expect(problems, "values keep defaults", result["values"], {"a": 0, "b": 0})
    expect(problems, "file untouched", read(store_dir), "{")
    expect(problems, "loaded() for a corrupt file", result["loaded_count"], 0)
    return problems


def scenario_corrupt_then_set(state_home):
    result, store_dir, problems = store_run("corrupt_then_set", state_home, seed="[1,2]")
    if problems:
        return problems
    expect(problems, "disk after a set", json.loads(read(store_dir)), {"a": 5, "b": 0})
    return problems


def scenario_external_idle(state_home):
    result, store_dir, problems = store_run("external_idle", state_home, seed='{"a":1,"b":1,"x":9}')
    if problems:
        return problems
    expect(problems, "values follow the edit", result["values"], {"a": 2, "b": 1})
    expect(problems, "extras never exposed", result["raw"].get("x"), 9)
    expect(problems, "loaded() count (start + edit)", result["loaded_count"], 2)
    return problems


def scenario_external_dirty(state_home):
    result, store_dir, problems = store_run("external_dirty", state_home, seed='{"a":1,"b":1,"x":9}')
    if problems:
        return problems
    expect(problems, "values: local value wins", result["values"], {"a": 2, "b": 7})
    expect(problems, "disk: our write, extras from the last load", json.loads(read(store_dir)), {"x": 9, "a": 2, "b": 7})
    return problems


def scenario_unknown_keys(state_home):
    result, store_dir, problems = store_run("unknown_keys", state_home, seed='{"pins":[1],"week_start":"monday"}')
    if problems:
        return problems
    expect(problems, "values hide extras", result["values"], {"week_start": "sunday"})
    expect(problems, "disk keeps extras", json.loads(read(store_dir)), {"pins": [1], "week_start": "sunday"})
    return problems


def scenario_dropped_known(state_home):
    result, store_dir, problems = store_run("dropped_known", state_home, seed='{"a":5,"b":6,"x":1}')
    if problems:
        return problems
    expect(problems, "disk: b stays deleted, x kept", json.loads(read(store_dir)), {"x": 1, "a": 1})
    return problems


def scenario_after_save(state_home):
    result, store_dir, problems = store_run("after_save", state_home)
    if problems:
        return problems
    log = read(store_dir, "after.log").splitlines()
    # "reload" is returned once, then cleared; the argv sees the new file, so the write finished first; the outside
    # edit at the end runs nothing.
    expect(problems, "after_save log", log, ['reload {"a":1,"b":0}', 'apply {"a":2,"b":0}'])
    expect(problems, "after_save_done", result["after_log"], ["done 0", "done 0"])
    return problems


def scenario_revert(state_home):
    result, store_dir, problems = store_run("revert", state_home)
    if problems:
        return problems
    expect(problems, "values follow a revert to our last write", result["values"], {"a": 1, "b": 0})
    return problems


def scenario_recreate(state_home):
    result, store_dir, problems = store_run("recreate", state_home)
    if problems:
        return problems
    expect(problems, "values follow the recreated file", result["values"], {"a": 1, "b": 0})
    return problems


def scenario_undo_to_earlier_write(state_home):
    result, store_dir, problems = store_run("undo_to_earlier_write", state_home)
    if problems:
        return problems
    expect(problems, "values follow a revert to an earlier write", result["values"], {"a": 1, "b": 0})
    return problems


def scenario_same_value(state_home):
    result, store_dir, problems = store_run("same_value", state_home)
    if problems:
        return problems
    expect(problems, "values", result["values"], {"a": 2, "b": 0})
    expect(problems, "disk after the set that follows an unchanged one", json.loads(read(store_dir)), {"a": 2, "b": 0})
    expect(problems, "saved signals", result["saved_count"], 3)
    expect(problems, "dirty/writing cleared", (result["dirty"], result["writing"]), (False, False))
    return problems


def scenario_external_burst(state_home):
    result, store_dir, problems = store_run("external_burst", state_home, seed='{"a":0,"b":0}')
    if problems:
        return problems
    expect(problems, "values follow the last of two quick edits", result["values"], {"a": 2, "b": 0})
    return problems


def scenario_set_from_loaded(state_home):
    result, store_dir, problems = store_run("set_from_loaded", state_home, seed='{"a":1,"b":0}')
    if problems:
        return problems
    expect(problems, "disk: the edit plus the set made on loading it", json.loads(read(store_dir)), {"a": 4, "b": 9})
    expect(problems, "saved signals", result["saved_count"], 2)
    expect(problems, "dirty/writing cleared", (result["dirty"], result["writing"]), (False, False))
    return problems


def scenario_after_save_inflight(state_home):
    result, store_dir, problems = store_run("after_save_inflight", state_home)
    if problems:
        return problems
    # The reload flag was set with the second set, so the second write's argv must be the one that took it. The first
    # entry is the directory-making write.
    expect(problems, "after_save kinds in write order", read(store_dir, "after.log").splitlines(), ["apply", "apply", "reload"])
    expect(problems, "after_save_done", result["after_log"], ["done 0"] * 3)
    return problems


def scenario_write_fails(state_home):
    def make_blocker(store_dir):
        open(os.path.join(store_dir, "blocker"), "w").close()

    result, store_dir, problems = store_run("write_fails", state_home, extra=make_blocker)
    if problems:
        return problems
    expect(problems, "save_failed count", len(result["failures"]), 1)
    expect(problems, "saved_count", result["saved_count"], 0)
    expect(problems, "after_save skipped", result["after_log"], [])
    expect(problems, "values stay in memory", result["values"], {"a": 1, "b": 0})
    expect(problems, "dirty/writing cleared", (result["dirty"], result["writing"]), (False, False))
    return problems


def failed_write_with_newer_edit(name, state_home):
    def make_blocker(store_dir):
        open(os.path.join(store_dir, "blocker"), "w").close()

    result, store_dir, problems = store_run(name, state_home, extra=make_blocker)
    if problems:
        return problems
    # The path stays unwritable, so the newer edit cannot reach the disk; what shows it was not dropped is a second
    # attempt (second save_failed). No third one: the failed content is not retried, so the store ends clean.
    expect(problems, "save_failed count (failed write + attempt for the newer edit)", len(result["failures"]), 2)
    expect(problems, "values stay in memory", result["values"], {"a": 2, "b": 0})
    expect(problems, "dirty/writing cleared", (result["dirty"], result["writing"]), (False, False))
    return problems


def scenario_edit_during_failed_write(state_home):
    return failed_write_with_newer_edit("edit_during_failed_write", state_home)


def scenario_edit_during_failed_flush(state_home):
    return failed_write_with_newer_edit("edit_during_failed_flush", state_home)


def scenario_same_values_after_failed_write(state_home):
    # The store's directory exists but is read-only for the first set; the shell reopens it before the second.
    store_dir = os.path.join(state_home, "state", "json_store")

    def lock(directory):
        os.chmod(directory, 0o500)

    result, store_dir, problems = store_run("same_values_after_failed_write", state_home, extra=lock)
    os.chmod(store_dir, 0o700)
    if problems:
        return problems
    expect(problems, "save_failed count (the first set only)", len(result["failures"]), 1)
    expect(problems, "saved after the same values were set again", result["saved_count"], 1)
    on_disk = read(store_dir) if os.path.exists(os.path.join(store_dir, "store.json")) else None
    expect(problems, "disk", on_disk and json.loads(on_disk), {"a": 1, "b": 0})
    expect(problems, "dirty/writing cleared", (result["dirty"], result["writing"]), (False, False))
    return problems


def scenario_watch_after_first_write(state_home):
    result, store_dir, problems = store_run("watch_after_first_write", state_home)
    if problems:
        return problems
    expect(problems, "an edit after the first save reaches the store", result["values"], {"a": 4, "b": 0})
    return problems


def untouched(problems, store_dir, expected_names, text):
    """A read-only store leaves the file as given and creates nothing beside it (no tmp file, no directory)."""
    expect(problems, "directory listing", sorted(os.listdir(store_dir)), sorted(expected_names))
    if text is not None:
        expect(problems, "file untouched", read(store_dir), text)


def scenario_ro_set_attempts(state_home):
    result, store_dir, problems = store_run("ro_set_attempts", state_home, seed='{"a":1,"b":0,"x":3}')
    if problems:
        return problems
    # The outside edit at 500 ms is the last write to the file.
    untouched(problems, store_dir, ["store.json"], '{"a":2,"b":1}')
    expect(problems, "values follow the file", result["values"], {"a": 2, "b": 1})
    expect(problems, "saved signals", result["saved_count"], 0)
    expect(problems, "dirty/writing", (result["dirty"], result["writing"]), (False, False))
    return problems


def scenario_ro_missing(state_home):
    result, store_dir, problems = store_run("ro_missing", state_home)
    if problems:
        return problems
    untouched(problems, store_dir, [], None)
    expect(problems, "values", result["values"], {"a": 0, "b": 0})
    expect(problems, "saved signals", result["saved_count"], 0)
    expect(problems, "dirty/writing", (result["dirty"], result["writing"]), (False, False))
    return problems


def scenario_ro_corrupt(state_home):
    problems = []
    for seed in ["{", "[1,2]", "5", "null", "", '"text"']:
        sub = tempfile.mkdtemp(prefix="json_store_")
        try:
            result, store_dir, found = store_run("ro_corrupt", sub, seed=seed)
            if found:
                return found
            label = "seed %r: " % seed
            expect(problems, label + "values are the defaults", result["values"], {"a": 0, "b": 0})
            expect(problems, label + "loaded() once", result["loaded_count"], 1)
            untouched(problems, store_dir, ["store.json"], seed)
        finally:
            shutil.rmtree(sub, ignore_errors=True)
    return problems


def scenario_ro_corrupt_later(state_home):
    result, store_dir, problems = store_run("ro_corrupt_later", state_home, seed='{"a":1,"b":1}')
    if problems:
        return problems
    # Good, corrupt, good, list: each one a load, ending on the defaults.
    expect(problems, "values after the list", result["values"], {"a": 0, "b": 0})
    expect(problems, "loaded() count", result["loaded_count"], 4)
    untouched(problems, store_dir, ["store.json"], "[1,2]")
    return problems


def scenario_ro_file_appears(state_home):
    result, store_dir, problems = store_run("ro_file_appears", state_home)
    if problems:
        return problems
    expect(problems, "values", result["values"], {"a": 5, "b": 6})
    untouched(problems, store_dir, ["store.json"], '{"a":5,"b":6}')
    return problems


def scenario_ro_dir_appears(state_home):
    result, store_dir, problems = store_run("ro_dir_appears", state_home)
    if problems:
        return problems
    # The edit at 700 ms is seen only if rearm() re-armed the watch for the new directory.
    expect(problems, "values", result["values"], {"a": 7, "b": 8})
    untouched(problems, os.path.join(store_dir, "late"), ["store.json"], None)
    return problems


def scenario_ro_delete_recreate(state_home):
    result, store_dir, problems = store_run("ro_delete_recreate", state_home, seed='{"a":1,"b":1}')
    if problems:
        return problems
    expect(problems, "values", result["values"], {"a": 3, "b": 3})
    # start, deleted, recreated, deleted, recreated with the same text as before the second delete
    expect(problems, "loaded() count", result["loaded_count"], 5)
    untouched(problems, store_dir, ["store.json"], '{"a":3,"b":3}')
    return problems


def burst_scenario(name, state_home):
    result, store_dir, problems = store_run(name, state_home, seed='{"a":0,"b":0}')
    if problems:
        return problems
    expect(problems, "values: last rewrite wins", result["values"], {"a": 40, "b": 0})
    untouched(problems, store_dir, ["store.json"], '{"a":40,"b":0}')
    return problems


def scenario_ro_burst_rename(state_home):
    return burst_scenario("ro_burst_rename", state_home)


def scenario_ro_burst_inplace(state_home):
    return burst_scenario("ro_burst_inplace", state_home)


def scenario_ro_array_root(state_home):
    result, store_dir, problems = store_run("ro_array_root", state_home, seed="[]")
    if problems:
        return problems
    # [] at start, two entries, an object (the defaults), one entry.
    expect(problems, "values", result["values"], {"entries": ["w"]})
    expect(problems, "loaded() count", result["loaded_count"], 4)
    untouched(problems, store_dir, ["store.json"], '[{"id":"w"}]')
    return problems


SCENARIOS = {
    "atomic": scenario_atomic,
    "firstrun": scenario_firstrun,
    "no_write_before_set": scenario_no_write_before_set,
    "echo": scenario_echo,
    "immediate": scenario_immediate,
    "immediate_spaced": scenario_immediate_spaced,
    "early_set": scenario_early_set,
    "early_set_debounced": scenario_early_set_debounced,
    "early_replace": scenario_early_replace,
    "early_set_missing": scenario_early_set_missing,
    "corrupt": scenario_corrupt,
    "corrupt_then_set": scenario_corrupt_then_set,
    "external_idle": scenario_external_idle,
    "external_dirty": scenario_external_dirty,
    "unknown_keys": scenario_unknown_keys,
    "dropped_known": scenario_dropped_known,
    "after_save": scenario_after_save,
    "revert": scenario_revert,
    "recreate": scenario_recreate,
    "undo_to_earlier_write": scenario_undo_to_earlier_write,
    "same_value": scenario_same_value,
    "external_burst": scenario_external_burst,
    "set_from_loaded": scenario_set_from_loaded,
    "after_save_inflight": scenario_after_save_inflight,
    "write_fails": scenario_write_fails,
    "edit_during_failed_write": scenario_edit_during_failed_write,
    "edit_during_failed_flush": scenario_edit_during_failed_flush,
    "same_values_after_failed_write": scenario_same_values_after_failed_write,
    "watch_after_first_write": scenario_watch_after_first_write,
    "ro_set_attempts": scenario_ro_set_attempts,
    "ro_missing": scenario_ro_missing,
    "ro_corrupt": scenario_ro_corrupt,
    "ro_corrupt_later": scenario_ro_corrupt_later,
    "ro_file_appears": scenario_ro_file_appears,
    "ro_dir_appears": scenario_ro_dir_appears,
    "ro_delete_recreate": scenario_ro_delete_recreate,
    "ro_burst_rename": scenario_ro_burst_rename,
    "ro_burst_inplace": scenario_ro_burst_inplace,
    "ro_array_root": scenario_ro_array_root,
}


def main():
    names = sys.argv[1:] or list(SCENARIOS)
    failed = 0
    for name in names:
        state_home = tempfile.mkdtemp(prefix="json_store_")
        try:
            problems = SCENARIOS[name](state_home)
        finally:
            shutil.rmtree(state_home, ignore_errors=True)
        print(("FAIL " if problems else "ok   ") + name)
        for problem in problems:
            print("     " + problem)
        failed += bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
