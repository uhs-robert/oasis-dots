"""Bar editor runtime tests: BarSettings storage and the editor's lifecycle, in a headless qs.

Each scenario gets a fresh XDG_STATE_HOME and a copy of the real Quickshell config whose shell.qml is the harness, so the
real singletons are under test. A scenario is judged here from the result file the shell writes and from what is on disk.

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
QS_DIR = os.path.join(HERE, "..", "..", ".config", "quickshell")


IN_MOVED_TO, IN_CLOSE_WRITE = 0x80, 0x8
EVENT_HEAD = struct.Struct("iIII")


class Watch:
    """Counts the times each name in one directory was written or renamed into place until stop()."""

    def __init__(self, directory):
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        self.fd = libc.inotify_init1(os.O_NONBLOCK)
        libc.inotify_add_watch(self.fd, directory.encode(), IN_MOVED_TO | IN_CLOSE_WRITE)
        self.names = []
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
                _, _, _, length = EVENT_HEAD.unpack_from(data, offset)
                self.names.append(data[offset + EVENT_HEAD.size : offset + EVENT_HEAD.size + length].rstrip(b"\0").decode())
                offset += EVENT_HEAD.size + length

    def stop(self):
        self.running = False
        self.thread.join()
        os.close(self.fd)


def run_qs(scenario, root, seed=None):
    """Runs the harness shell once; returns (result dict or None, qs output)."""
    cfg = os.path.join(root, "cfg")
    shutil.copytree(QS_DIR, cfg, symlinks=False, ignore=shutil.ignore_patterns("sounds", "assets", "*.wav", "*.ogg"))
    shutil.copy(os.path.join(HERE, "shell.qml"), os.path.join(cfg, "shell.qml"))
    state = os.path.join(root, "state")
    for name in ("state", "run", "home"):
        os.makedirs(os.path.join(root, name), mode=0o700, exist_ok=True)
    bars_dir = os.path.join(state, "quickshell")
    os.makedirs(bars_dir, exist_ok=True)
    if seed is not None:
        with open(os.path.join(bars_dir, "bars.json"), "w") as f:
            f.write(seed)
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update(
        QT_QPA_PLATFORM="offscreen",
        SCENARIO=scenario,
        XDG_STATE_HOME=state,
        XDG_RUNTIME_DIR=os.path.join(root, "run"),
        HOME=os.path.join(root, "home"),
    )
    proc = subprocess.run(["qs", "-p", cfg], env=env, capture_output=True, text=True, timeout=30)
    out = "qs exit code %d\n" % proc.returncode + proc.stdout + proc.stderr
    try:
        with open(os.path.join(state, "result.json")) as f:
            return json.load(f), out
    except (FileNotFoundError, ValueError):
        return None, out


def bars_file(root):
    with open(os.path.join(root, "state", "quickshell", "bars.json")) as f:
        return json.load(f)


def first_order(state):
    order = state["shared"]["order"]
    return int(order[0][1:]) if order else 0


def check_monotonic(problems, observed):
    """The state BarSettings holds never goes back to an older set: an echo of an old write must not replace a newer one."""
    for before, after in zip(observed, observed[1:]):
        if after < before:
            problems.append("state went back from set %d to set %d (sequence %r)" % (before, after, observed))
            return


def scenario_rapid(name, count):
    def run(root):
        result, out = run_qs(name, root)
        if result is None:
            return ["no result file:\n" + out]
        problems = []
        check_monotonic(problems, result["observed"])
        if result["final_k"] != count:
            problems.append("final in-memory set is %r, want %d" % (result["final_k"], count))
        on_disk = first_order(bars_file(root))
        if on_disk != count:
            problems.append("final file holds set %r, want %d" % (on_disk, count))
        return problems

    return run


def scenario_visual_rapid(root):
    """Forty edge moves 2 ms apart: the state only ever steps forward through them and the file ends on the last."""
    result, out = run_qs("visual_rapid", root)
    if result is None:
        return ["no result file:\n" + out]
    problems = []
    # Key i is h, j, k, l in turn: left, bottom, top, right.
    want = [["left", "bottom", "top", "right"][i % 4] for i in range(40)]
    if result["edges_seen"] != want:
        problems.append("edges seen %r, want %r" % (result["edges_seen"], want))
    on_disk = bars_file(root)["shared"].get("position")
    if on_disk != want[-1] or result["final_edge"] != want[-1]:
        problems.append("final edge: memory %r, file %r, want %r" % (result["final_edge"], on_disk, want[-1]))
    return problems


def scenario_ipc(root):
    """open, state, toggle and close through `qs ipc`, the way a key bind or the shadow drives the editor."""
    cfg = os.path.join(root, "cfg")
    shutil.copytree(QS_DIR, cfg, symlinks=False, ignore=shutil.ignore_patterns("sounds", "assets", "*.wav", "*.ogg"))
    shutil.copy(os.path.join(HERE, "shell.qml"), os.path.join(cfg, "shell.qml"))
    for name in ("state", "run", "home"):
        os.makedirs(os.path.join(root, name), mode=0o700, exist_ok=True)
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update(QT_QPA_PLATFORM="offscreen", SCENARIO="ipc", XDG_STATE_HOME=os.path.join(root, "state"), XDG_RUNTIME_DIR=os.path.join(root, "run"), HOME=os.path.join(root, "home"))
    proc = subprocess.Popen(["qs", "-p", cfg], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def call(*args):
        done = subprocess.run(["qs", "-p", cfg, "ipc", "call", "bareditor", *args], env=env, capture_output=True, text=True, timeout=10)
        return done.stdout.strip()

    problems = []
    try:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and not call("state").startswith("{"):
            time.sleep(0.2)
        time.sleep(0.4)
        state = lambda: json.loads(call("state"))
        if state()["active"]:
            problems.append("open before any call")
        if call("open", "B") != "ok" or state()["focus_screen"] != "B" or state()["mode"] != "normal":
            problems.append("open B: %r" % state())
        if call("close") != "ok" or state()["active"] or state()["focus_screen"] != "":
            problems.append("close left it open or owning the keyboard: %r" % state())
        if call("toggle") != "open" or not state()["active"]:
            problems.append("toggle did not open")
        if state()["focus_screen"] != "B":
            problems.append("toggle should open on the focused monitor B: %r" % state())
        if call("toggle") != "closed" or state()["active"]:
            problems.append("toggle did not close")
        if call("open", "C") != "ok" or state()["focus_screen"] != "A":
            problems.append("open on a monitor with no bar should land on the first with one: %r" % state())
        call("close")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
    return problems


def scenario_no_import_cycle(root):
    """The bar does not import the editor, which imports the bar: Bar.qml publishes through features/bar/BarItems."""
    bar_dir = os.path.join(QS_DIR, "features", "bar")
    problems = []
    for dirpath, _, names in os.walk(bar_dir):
        for name in names:
            if not name.endswith(".qml"):
                continue
            with open(os.path.join(dirpath, name)) as f:
                if "qs.features.bar_editor" in f.read():
                    problems.append("%s imports qs.features.bar_editor" % os.path.join(dirpath, name))
    return problems


def scenario_external(root):
    result, out = run_qs("external", root)
    if result is None:
        return ["no result file:\n" + out]
    problems = []
    if 50 not in result["observed"]:
        problems.append("the outside edit was never adopted (sequence %r)" % result["observed"])
    if result["final_k"] != 60 or first_order(bars_file(root)) != 60:
        problems.append("the set after the outside edit did not win: memory %r, file %r" % (result["final_k"], first_order(bars_file(root))))
    return problems


def scenario_coalesce(root):
    """A burst of 60 sets 1 ms apart is a few writes, not 60: the bar editor writes per key press."""
    bars_dir = os.path.join(root, "state", "quickshell")
    os.makedirs(bars_dir)
    watch = Watch(bars_dir)
    result, out = run_qs("rapid_1ms", root)
    watch.stop()
    if result is None:
        return ["no result file:\n" + out]
    writes = watch.names.count("bars.json")
    problems = []
    if writes > 20:
        problems.append("%d writes of bars.json for 60 sets in 60 ms, want a handful" % writes)
    if first_order(bars_file(root)) != 60:
        problems.append("final file does not hold the last set")
    return problems


def scenario_migrate(root):
    """A state file from before the media module is migrated once and stamped; a missing file is never written by a load."""
    seed = json.dumps({"shared": {"place": {}, "order": []}, "monitors": {"M": {"left": ["workspaces"], "center": [], "right": []}}, "positions": {}})
    result, out = run_qs("idle", root, seed=seed)
    if result is None:
        return ["no result file:\n" + out]
    problems = []
    on_disk = bars_file(root)
    if on_disk.get("cava_migrated") is not True:
        problems.append("migrated file was not stamped: %r" % on_disk)
    if on_disk["monitors"]["M"]["left"] != ["workspaces", "media"]:
        problems.append("media not added after workspaces: %r" % on_disk["monitors"]["M"]["left"])
    return problems


def scenario_missing_untouched(root):
    result, out = run_qs("idle", root)
    if result is None:
        return ["no result file:\n" + out]
    if os.path.exists(os.path.join(root, "state", "quickshell", "bars.json")):
        return ["a load of a missing bars.json created the file"]
    return []


def scenario_editor(name):
    """A scenario whose shell records [label, got, want] checks; every one must match."""

    def run(root):
        result, out = run_qs(name, root)
        if result is None:
            return ["no result file:\n" + out]
        problems = ["%s: got %r, want %r" % (label, got, want) for label, got, want in result["checks"] if got != want]
        if not result["checks"]:
            problems.append("the scenario recorded no checks:\n" + out)
        return problems

    return run


SCENARIOS = {
    "rapid_1ms": scenario_rapid("rapid_1ms", 60),
    "rapid_5ms": scenario_rapid("rapid_5ms", 60),
    "rapid_20ms": scenario_rapid("rapid_20ms", 40),
    "external": scenario_external,
    "visual_rapid": scenario_visual_rapid,
    "ipc": scenario_ipc,
    "editor_keys": scenario_editor("editor_keys"),
    "editor_ownership": scenario_editor("editor_ownership"),
    "editor_popups": scenario_editor("editor_popups"),
    "editor_hint_keys": scenario_editor("editor_hint_keys"),
    "editor_hidden_add": scenario_editor("editor_hidden_add"),
    "editor_hidden_empty": scenario_editor("editor_hidden_empty"),
    "editor_module_compact": scenario_editor("editor_module_compact"),
    "editor_rule_compact": scenario_editor("editor_rule_compact"),
    "editor_hint_edge": scenario_editor("editor_hint_edge"),
    "editor_monitor_map": scenario_editor("editor_monitor_map"),
    "editor_pick_redo": scenario_editor("editor_pick_redo"),
    "no_import_cycle": scenario_no_import_cycle,
    "editor_monitors": scenario_editor("editor_monitors"),
    "editor_undo_own": scenario_editor("editor_undo_own"),
    "coalesce": scenario_coalesce,
    "migrate": scenario_migrate,
    "missing_untouched": scenario_missing_untouched,
}


def main():
    names = sys.argv[1:] or list(SCENARIOS)
    failed = 0
    for name in names:
        root = tempfile.mkdtemp(prefix="bar_editor_")
        try:
            problems = SCENARIOS[name](root)
        finally:
            shutil.rmtree(root, ignore_errors=True)
        print(("FAIL " if problems else "ok   ") + name)
        for problem in problems:
            print("     " + problem)
        failed += bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
