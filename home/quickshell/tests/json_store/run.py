"""Lifecycle tests for core/JsonStore.qml and the FileView write it relies on, run in a headless qs.

Each scenario gets a fresh XDG_STATE_HOME, runs shell.qml with SCENARIO set, and is judged here from the RESULT line
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
    """Runs the harness shell once; returns (RESULT dict or None, qs output)."""
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
    out = proc.stdout + proc.stderr
    for line in out.splitlines():
        if "RESULT " in line:
            return json.loads(line.split("RESULT ", 1)[1]), out
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
        return ["no RESULT line:\n" + out]
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


SCENARIOS = {"atomic": scenario_atomic}


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
