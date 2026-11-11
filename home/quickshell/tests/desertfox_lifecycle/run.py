"""Drives features/desertfox/DesertfoxState.qml through the bridge host's life in a headless qs.

The real files run beside stubs (stubs/) for the window focus and VoxSessionState's stat parser.
This script plays the bridge host and the compositor: it writes $XDG_RUNTIME_DIR/desertfox/state.json and focus.txt,
starts and kills a stand-in host process, and waits for the STATE lines the shell prints (see shell.qml). Each step names
what it guards; a step that fails to show its line within the timeout is reported with the last line seen.

  python3 -B run.py
"""

import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, "..", "..", ".config", "quickshell")
WAIT_S = 8


def copy_config(cfg):
    """The real files under test and the stubs, laid out as the `qs.` import paths expect."""
    for rel in ("core/JsonStore.qml", "core/PolledFile.qml", "features/desertfox/DesertfoxState.qml", "features/desertfox/DesertfoxState.js"):
        os.makedirs(os.path.join(cfg, os.path.dirname(rel)), exist_ok=True)
        shutil.copy(os.path.join(CONFIG, rel), os.path.join(cfg, rel))
    for rel, name in (("features/windows", "WindowState"), ("features/voice", "VoxSessionState"), ("theme", "Theme")):
        os.makedirs(os.path.join(cfg, rel), exist_ok=True)
        shutil.copy(os.path.join(HERE, "stubs", name + ".qml"), os.path.join(cfg, rel))
    shutil.copy(os.path.join(HERE, "shell.qml"), cfg)


def start_time(pid):
    with open("/proc/%d/stat" % pid) as f:
        text = f.read()
    return text[text.rindex(")") + 1:].split()[19]


class Host:
    """A stand-in for the bridge host: a process with a pid and a start time to put in the file."""

    def __init__(self):
        self.proc = subprocess.Popen(["sleep", "600"])
        self.pid = self.proc.pid
        self.start = start_time(self.pid)

    def kill(self):
        self.proc.kill()
        self.proc.wait()


class Run:
    def __init__(self, root):
        self.runtime = os.path.join(root, "run")
        self.dir = os.path.join(self.runtime, "desertfox")
        os.makedirs(self.runtime, mode=0o700)
        self.last = ""
        self.lines = []
        self.cond = threading.Condition()
        self.proc = None
        self.root = root

    def write_focus(self, address):
        with open(os.path.join(self.runtime, "focus.txt"), "w") as f:
            f.write(address + "\n")

    def write_state(self, host_pid, host_start, mode_id="insert", label="INSERT", private=False):
        os.makedirs(self.dir, exist_ok=True)
        # A private window has no ids, as the bridge host writes it.
        firefox = {"private": True} if private else {"window_id": 1, "private": False}
        mode = {"id": mode_id, "label": label} if private else {"id": mode_id, "label": label, "tab_id": 1}
        text = json.dumps({"version": 2, "seq": int(time.time() * 1000) % 100000, "host": {"pid": host_pid, "start": host_start}, "firefox": firefox, "mode": mode})
        tmp = os.path.join(self.dir, ".tmp")
        with open(tmp, "w") as f:
            f.write(text)
        os.rename(tmp, os.path.join(self.dir, "state.json"))

    def start(self):
        cfg = os.path.join(self.root, "cfg")
        os.makedirs(cfg)
        copy_config(cfg)
        env = {k: v for k, v in os.environ.items() if k not in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE")}
        env.update(QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=self.runtime, XDG_STATE_HOME=os.path.join(self.root, "state"), HOME=os.path.join(self.root, "home"))
        os.makedirs(env["HOME"])
        self.proc = subprocess.Popen(["qs", "-p", cfg], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        for line in self.proc.stdout:
            with self.cond:
                self.lines.append(line.rstrip())
                m = re.search(r"STATE (.*)", line)
                if m:
                    self.last = m.group(1)
                self.cond.notify_all()

    def fields(self):
        return dict(kv.split("=", 1) if "=" in kv else (kv, "") for kv in self.last.split())

    def wait_for(self, want, timeout=WAIT_S):
        """Waits until every key in `want` holds in the latest STATE line; returns None, or the reason."""
        deadline = time.time() + timeout
        with self.cond:
            while True:
                got = self.fields()
                if got and all(got.get(k) == v for k, v in want.items()):
                    return None
                left = deadline - time.time()
                if left <= 0:
                    return "wanted %r, last STATE %r" % (want, self.last)
                self.cond.wait(left)

    def hold(self, seconds, want):
        """The state must stay as `want` for the whole time."""
        time.sleep(seconds)
        got = self.fields()
        bad = {k: got.get(k) for k, v in want.items() if got.get(k) != v}
        return "after %.1f s: wanted %r, got %r (%s)" % (seconds, want, bad, self.last) if bad else None

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def steps(r, problems):
    def check(name, result):
        print(("ok   " if result is None else "FAIL ") + name + ("" if result is None else "\n     " + result))
        if result is not None:
            problems.append(name)

    host = Host()
    other = Host()
    try:
        # Firefox is already the focused window when the shell starts, as after a full restart: no focus event follows.
        r.write_focus("0x1")
        # The host's folder does not exist yet, as before the host's first use.
        r.start()
        check("startup: nothing shows without a file", r.wait_for({"live": "0", "shown": "0"}))
        r.write_state(host.pid, host.start)
        check("folder made after start: the chip shows with Firefox focused from the start", r.wait_for({"live": "1", "shown": "1", "chip": "INSERT"}))

        r.write_state(host.pid, host.start, mode_id="normal", label="NORMAL")
        check("a mode change updates the chip", r.wait_for({"chip": "NORMAL"}))

        r.write_state(host.pid, host.start, mode_id="insert", label="INSERT", private=True)
        check("private window: the id-free file still shows its mode", r.wait_for({"live": "1", "shown": "1", "chip": "INSERT"}))
        r.write_state(host.pid, host.start, mode_id="hint", label="HINT")
        check("hint mode: the chip hides although the file has a label", r.wait_for({"live": "1", "shown": "1", "chip": ""}))
        r.write_state(host.pid, host.start)

        r.write_focus("0x2")
        check("liveness gate: focus on another window hides the chip", r.wait_for({"live": "1", "shown": "0", "chip": ""}))
        r.write_focus("0x1")
        check("liveness gate: refocus shows it again", r.wait_for({"shown": "1", "chip": "INSERT"}))

        r.write_state(host.pid, "1")
        check("reused pid: the pid with another start time is not a live host", r.wait_for({"live": "0", "shown": "0"}))
        r.write_state(host.pid, host.start)
        check("a file naming the real start time is live again", r.wait_for({"live": "1", "shown": "1"}))

        # Folder delete and recreate: the watch on the old folder is gone, the once-a-second probe must re-arm it.
        shutil.rmtree(r.dir)
        check("folder deleted: nothing shows", r.wait_for({"live": "0", "shown": "0"}))
        time.sleep(2.5)
        r.write_state(host.pid, host.start)
        check("folder recreated: the new file shows", r.wait_for({"live": "1", "shown": "1"}))

        host.kill()
        check("dead pid: the file of a killed host stops showing", r.wait_for({"live": "0", "shown": "0"}, timeout=10))
        r.write_state(host.pid, host.start, mode_id="normal", label="NORMAL")
        check("dead pid: a rewrite naming the same host stays hidden", r.hold(4, {"live": "0", "shown": "0"}))
        r.write_state(other.pid, other.start)
        check("dead pid: a file from a new host shows again", r.wait_for({"live": "1", "shown": "1", "chip": "INSERT"}))
    finally:
        r.stop()
        host.kill()
        other.kill()


def main():
    problems = []
    with tempfile.TemporaryDirectory() as root:
        r = Run(root)
        try:
            steps(r, problems)
        finally:
            r.stop()
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
