"""Drives features/desertfox/DesertfoxState.qml through the bridge host's life in a headless qs, then NowPlayingState.qml
against a fake bridge socket (bridge down then up, the subscriber cap, unmount).

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
import socket
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
    for rel in ("core/JsonStore.qml", "core/PolledFile.qml", "features/desertfox/DesertfoxState.qml", "features/desertfox/DesertfoxState.js", "features/desertfox/NowPlayingState.qml", "features/desertfox/NowPlaying.js"):
        os.makedirs(os.path.join(cfg, os.path.dirname(rel)), exist_ok=True)
        shutil.copy(os.path.join(CONFIG, rel), os.path.join(cfg, rel))
    for rel, name in (("features/windows", "WindowState"), ("features/voice", "VoxSessionState"), ("theme", "Theme"), ("core", "PowerSource")):
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

    def write_mount(self, on):
        with open(os.path.join(self.runtime, "mount.txt"), "w") as f:
            f.write("1\n" if on else "0\n")

    def write_ac(self, on):
        with open(os.path.join(self.runtime, "ac.txt"), "w") as f:
            f.write("1\n" if on else "0\n")

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

        # Nothing polls while Firefox is unfocused (the host's death goes unjudged), and focus gain reads everything at once.
        r.write_focus("0x2")
        check("unfocused: the chip is hidden", r.wait_for({"shown": "0"}))
        shutil.rmtree(r.dir)
        r.write_state(other.pid, other.start, mode_id="normal", label="NORMAL")
        check("unfocused, folder recreated: the chip stays hidden", r.hold(1.5, {"shown": "0"}))
        r.write_focus("0x1")
        check("focus gain: the new folder and file show at once", r.wait_for({"live": "1", "shown": "1", "chip": "NORMAL"}, timeout=1))

        r.write_focus("0x2")
        check("unfocused again: the chip is hidden", r.wait_for({"shown": "0"}))
        other.kill()
        check("unfocused, host killed: no probe judges it", r.hold(4, {"live": "1"}))
        r.write_focus("0x1")
        check("focus gain: the dead host is found at once", r.wait_for({"live": "0", "shown": "0"}, timeout=1))
    finally:
        r.stop()
        host.kill()
        other.kill()


class FakeBridge:
    """A stand-in for the bridge's socket: `mode` is "serve" (ack, one audible tab, stay open) or "refuse" (the cap
    refusal, then close). It records when each subscribe arrived and which subscribe connections are still open."""

    def __init__(self, path):
        self.path = path
        self.mode = "serve"
        self.subscribes = []
        self.open_subscribers = 0
        self.connections = []
        # Cleared to hold every `tabs` reply back, and to make it name a tab that is playing.
        self.tabs_release = threading.Event()
        self.tabs_release.set()
        self.lock = threading.Lock()
        self.server = None

    def up(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(self.path)
        self.server.listen(8)
        threading.Thread(target=self.accept, daemon=True).start()

    def down(self):
        if self.server:
            self.server.close()
            os.unlink(self.path)
            self.server = None

    def accept(self):
        server = self.server
        while True:
            try:
                connection, _ = server.accept()
            except OSError:
                return
            threading.Thread(target=self.serve, args=(connection,), daemon=True).start()

    def serve(self, connection):
        with connection:
            line = connection.makefile("rb").readline()
            try:
                verb = json.loads(line).get("verb")
            except ValueError:
                return
            if verb == "tabs":
                held = not self.tabs_release.is_set()
                self.tabs_release.wait(10)
                tabs = b'[{"tab_id": 9, "window_id": 1, "audible": true, "last_accessed": 1, "title": "Stale", "url": "u"}]' if held else b"[]"
                connection.sendall(b'{"ok": true, "tabs": ' + tabs + b'}\n')
                return
            if verb != "subscribe":
                return
            with self.lock:
                self.subscribes.append(time.time())
                refuse = self.mode == "refuse"
                if not refuse:
                    self.open_subscribers += 1
                    self.connections.append(connection)
            if refuse:
                connection.sendall(b'{"ok": false, "message": "too many subscribers"}\n')
                return
            try:
                connection.sendall(b'{"ok": true}\n{"event": "tab_audible", "tab_id": 4, "window_id": 1, "audible": true, "title": "Song", "url": "https://x", "seq": 1}\n')
                while connection.recv(1):
                    pass
            except OSError:
                pass
            finally:
                with self.lock:
                    self.open_subscribers -= 1
                    if connection in self.connections:
                        self.connections.remove(connection)

    def push(self, line):
        with self.lock:
            for connection in self.connections:
                connection.sendall(line.encode() + b"\n")

    def wait_subscribers(self, count, timeout=WAIT_S):
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self.lock:
                if self.open_subscribers == count:
                    return None
            time.sleep(0.05)
        return "wanted %d open subscribers, have %d" % (count, self.open_subscribers)


def now_playing_steps(r, problems):
    def check(name, result):
        print(("ok   " if result is None else "FAIL ") + name + ("" if result is None else "\n     " + result))
        if result is not None:
            problems.append(name)

    bridge = FakeBridge(os.path.join(r.dir, "bridge.sock"))
    os.makedirs(r.dir, exist_ok=True)
    try:
        r.start()
        r.write_mount(True)
        check("bridge down: the chip is empty and nothing streams", r.hold(1.5, {"streaming": "0", "now": ""}))
        bridge.up()
        check("bridge comes up: the module reconnects and shows the audible tab", r.wait_for({"streaming": "1", "now": "Song"}, timeout=12))
        r.write_mount(False)
        check("unmount: the subscriber connection closes", bridge.wait_subscribers(0))
        check("unmount: the chip empties", r.wait_for({"streaming": "0", "now": ""}))
        bridge.down()
        bridge.mode = "refuse"
        bridge.up()
        bridge.subscribes.clear()
        r.write_mount(True)
        time.sleep(6)
        stamps = list(bridge.subscribes)
        gaps = [b - a for a, b in zip(stamps, stamps[1:])]
        check("cap refusal: the retries slow down (%d asks in 6 s)" % len(stamps),
              None if 2 <= len(stamps) <= 4 and gaps and gaps[-1] > gaps[0] * 1.4 else "asks at %r" % [round(t - stamps[0], 1) for t in stamps])
        check("cap refusal: nothing shows", r.hold(0, {"streaming": "0", "now": ""}))
        bridge.mode = "serve"
        check("a place frees up: the next retry streams", r.wait_for({"streaming": "1", "now": "Song"}, timeout=12))
    finally:
        r.stop()
        bridge.down()


def power_and_stale_steps(r, problems):
    def check(name, result):
        print(("ok   " if result is None else "FAIL ") + name + ("" if result is None else "\n     " + result))
        if result is not None:
            problems.append(name)

    bridge = FakeBridge(os.path.join(r.dir, "bridge.sock"))
    os.makedirs(r.dir, exist_ok=True)
    try:
        r.write_ac(False)
        r.start()
        time.sleep(2.5)
        r.write_mount(True)
        time.sleep(3.5)
        bridge.up()
        time.sleep(4)
        check("battery: a down bridge is not retried", None if not bridge.subscribes else "%d asks on battery" % len(bridge.subscribes))
        r.write_ac(True)
        check("AC returns: the stream connects at once", r.wait_for({"streaming": "1", "now": "Song"}, timeout=3))
        r.write_ac(False)
        bridge.push('{"event": "tab_audible", "tab_id": 5, "window_id": 1, "audible": true, "title": "Next", "url": "u", "seq": 2}')
        check("battery: an open stream stays up and keeps delivering", r.wait_for({"streaming": "1", "now": "Next"}))
        r.write_ac(True)

        # A tab list that is still in flight when sharing goes off must not bring its tabs back.
        r.write_mount(False)
        check("stale reply: unmounted", r.wait_for({"streaming": "0"}))
        bridge.tabs_release.clear()
        r.write_mount(True)
        check("stale reply: streaming again with the tab list held back", r.wait_for({"streaming": "1", "now": "Song"}))
        bridge.push('{"event": "tabs_off", "seq": 3}')
        check("stale reply: tabs_off empties the chip", r.wait_for({"now": ""}))
        bridge.tabs_release.set()
        check("stale reply: the old tab list is dropped", r.hold(1.5, {"streaming": "1", "now": ""}))
    finally:
        r.stop()
        bridge.tabs_release.set()
        bridge.down()


def main():
    problems = []
    with tempfile.TemporaryDirectory() as root:
        r = Run(root)
        try:
            steps(r, problems)
        finally:
            r.stop()
    with tempfile.TemporaryDirectory() as root:
        r = Run(root)
        try:
            now_playing_steps(r, problems)
        finally:
            r.stop()
    with tempfile.TemporaryDirectory() as root:
        r = Run(root)
        try:
            power_and_stale_steps(r, problems)
        finally:
            r.stop()
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
