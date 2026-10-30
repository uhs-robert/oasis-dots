"""Lifecycle checks for core/RestartingStream.qml in a headless qs.

Each scenario runs shell.qml with SCENARIO set against a stub stream and probe (shell commands in a work dir) and is
judged here from the timed event list the shell saves, the qs log (warnings) and the probe log. Delays are scaled
down: initial 200 ms, so a counted quick failure doubles it to 400 ms.

  python3 -B run.py [scenario...]
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "..", "..", ".config", "quickshell", "core", "RestartingStream.qml")
# Scenarios that start with the probed tool missing.
ABSENT_AT_START = {"missing_then_installed", "probe_in_flight"}


def run_qs(scenario, root_dir):
    """Runs the harness shell once; returns (event list or None, qs output, probe count)."""
    cfg = os.path.join(root_dir, "cfg")
    work = os.path.join(root_dir, "work")
    os.makedirs(cfg)
    os.makedirs(work)
    if scenario not in ABSENT_AT_START:
        open(os.path.join(work, "present"), "w").close()
    shutil.copy(os.path.join(HERE, "shell.qml"), cfg)
    shutil.copy(SOURCE, cfg)
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update(
        QT_QPA_PLATFORM="offscreen",
        SCENARIO=scenario,
        WORK=work,
        XDG_STATE_HOME=os.path.join(root_dir, "state"),
        XDG_RUNTIME_DIR=os.path.join(root_dir, "run"),
        HOME=os.path.join(root_dir, "home"),
    )
    for name in ("state", "run", "home"):
        os.makedirs(os.path.join(root_dir, name), mode=0o700, exist_ok=True)
    proc = subprocess.run(["qs", "-p", cfg], env=env, capture_output=True, text=True, timeout=30)
    out = "qs exit code %d\n" % proc.returncode + proc.stdout + proc.stderr
    try:
        with open(os.path.join(work, "probes")) as f:
            probes = len(f.read().split())
    except FileNotFoundError:
        probes = 0
    try:
        with open(os.path.join(root_dir, "state", "result.json")) as f:
            return json.load(f), out, probes
    except (FileNotFoundError, ValueError):
        return None, out, probes


class Run:
    def __init__(self, events, out, probes):
        self.events = events
        self.probes = probes
        self.quick_warnings = out.count("TEST-WARN-QUICK")
        self.missing_warnings = out.count("TEST-WARN-MISSING")
        self.ups = [e["t"] for e in events if e["kind"] == "line" and e["text"] == "up"]
        self.exits = [e for e in events if e["kind"] == "exited"]
        self.actions = {e["name"]: e["t"] for e in reversed(events) if e["kind"] == "action"}
        self.end = [e for e in events if e["kind"] == "end"][0]


def expect(problems, label, got, want):
    if got != want:
        problems.append("%s: got %r, want %r" % (label, got, want))


def between(problems, label, value, low, high):
    if not low <= value <= high:
        problems.append("%s: %d ms, want %d..%d" % (label, value, low, high))


def check_planned(r):
    p = []
    expect(p, "starts", len(r.ups), 2)
    expect(p, "exit delays", [e["delay"] for e in r.exits], [200])
    expect(p, "quick-failure warnings", r.quick_warnings, 0)
    if len(r.ups) == 2:
        # The restart waits out the 200 ms delay after the exit, which follows the kill; the upper bound only catches
        # a stuck restart.
        between(p, "restart after the planned exit", r.ups[1] - r.actions["kill"], 140, 1500)
    return p


def check_unplanned(r):
    p = []
    expect(p, "exit delays", [e["delay"] for e in r.exits], [400])
    expect(p, "quick-failure warnings", r.quick_warnings, 1)
    expect(p, "starts", len(r.ups), 2)
    return p


def check_stale_mark(r):
    p = []
    expect(p, "exit delays", [e["delay"] for e in r.exits], [400])
    expect(p, "quick-failure warnings", r.quick_warnings, 1)
    return p


def check_mark_after_exit(r):
    p = []
    expect(p, "exit delays", [e["delay"] for e in r.exits], [400, 800])
    expect(p, "quick-failure warnings", r.quick_warnings, 1)
    return p


def check_repeated_marks(r):
    p = []
    expect(p, "exit delays", [e["delay"] for e in r.exits], [200, 400])
    expect(p, "quick-failure warnings", r.quick_warnings, 1)
    return p


def check_missing_then_installed(r):
    p = []
    expect(p, "missing warnings", r.missing_warnings, 1)
    expect(p, "starts", len(r.ups), 1)
    if r.ups:
        between(p, "start after install", r.ups[0] - r.actions["present"], 50, 1500)
    expect(p, "available at end", r.end["available"], True)
    expect(p, "probed at least 3 times", r.probes >= 3, True)
    return p


def check_probe_in_flight(r):
    p = []
    # Probes take 500 ms against a 100 ms timer: unguarded there would be about 13.
    between(p, "probe runs", r.probes, 2, 3)
    expect(p, "missing warnings", r.missing_warnings, 1)
    expect(p, "starts", len(r.ups), 0)
    return p


def check_removed_then_back(r):
    p = []
    expect(p, "starts", len(r.ups), 2)
    if len(r.ups) == 2:
        # Never before the tool is back; the upper bound allows slow re-probes and process starts.
        between(p, "start after reinstall", r.ups[1] - r.actions["present"], 0, 2500)
    expect(p, "exits", len(r.exits), 1)
    expect(p, "available at end", r.end["available"], True)
    expect(p, "probed at the restart", r.probes >= 3, True)
    return p


def check_probe_flips_while_running(r):
    p = []
    expect(p, "starts", len(r.ups), 1)
    expect(p, "exits", len(r.exits), 1)
    if r.exits:
        between(p, "the running stream lived until the kill", r.exits[0]["t"] - r.actions["kill"], 0, 1000)
    expect(p, "available at end", r.end["available"], False)
    expect(p, "running at end", r.end["running"], False)
    return p


def check_wanted_off_in_backoff(r):
    p = []
    expect(p, "starts", len(r.ups), 1)
    expect(p, "running at end", r.end["running"], False)
    return p


def check_wanted_flap_in_backoff(r):
    p = []
    expect(p, "starts", len(r.ups), 2)
    if len(r.ups) == 2 and r.exits:
        # Never before the flap, and before the backoff that follows the exit would have fired on its own.
        backoff_ends = r.exits[0]["t"] + r.exits[0]["delay"] - r.actions["wanted_true"]
        between(p, "start at the flap, not after the backoff", r.ups[1] - r.actions["wanted_true"], 0, backoff_ends)
    return p


def check_stop_leaves_nothing(r):
    p = []
    expect(p, "starts", len(r.ups), 1)
    expect(p, "process alive after stop", [e["alive"] for e in r.events if e["kind"] == "alive"], [False])
    expect(p, "running at end", r.end["running"], False)
    return p


SCENARIOS = {
    "planned": check_planned,
    "unplanned": check_unplanned,
    "stale_mark": check_stale_mark,
    "mark_after_exit": check_mark_after_exit,
    "repeated_marks": check_repeated_marks,
    "missing_then_installed": check_missing_then_installed,
    "probe_in_flight": check_probe_in_flight,
    "removed_then_back": check_removed_then_back,
    "probe_flips_while_running": check_probe_flips_while_running,
    "wanted_off_in_backoff": check_wanted_off_in_backoff,
    "wanted_flap_in_backoff": check_wanted_flap_in_backoff,
    "stop_leaves_nothing": check_stop_leaves_nothing,
}


def main():
    names = sys.argv[1:] or list(SCENARIOS)
    failed = 0
    for name in names:
        root_dir = tempfile.mkdtemp(prefix="restarting_stream_")
        try:
            events, out, probes = run_qs(name, root_dir)
        finally:
            shutil.rmtree(root_dir, ignore_errors=True)
        problems = ["no result saved"] if events is None else SCENARIOS[name](Run(events, out, probes))
        print(("FAIL " if problems else "ok   ") + name)
        for problem in problems:
            print("     " + problem)
        if problems:
            print("     events: " + json.dumps(events))
            print("     " + out.replace("\n", "\n     "))
        failed += bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
