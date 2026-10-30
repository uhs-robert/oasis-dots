"""Pins how core/PolledFile.qml reads, fails, follows a path change and keeps time, in a headless qs.

It guards the FileView behaviour the component relies on: a missing file arrives as `load_failed` (FileNotFound)
without a line in the qs log, and a changed path reads the new file, also with blockLoading. Each scenario runs
shell.qml with SCENARIO set and is judged here from the timed event list the shell saves.

FileView reads a file once by itself when its path is first set, so every scenario starts with one read that is not
the component's doing. The shell starts its clock at that read (t = 0) and holds the plan back until it arrives, so
slow startup cannot put it inside the plan. A timer's own first tick may follow it, so reads before STARTUP_MS are
startup too; the checks see the events after that, except interval_start, which also needs to know that the tick came.

  python3 -B run.py [scenario...]
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

STARTUP_MS = 100
HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "..", "..", ".config", "quickshell", "core", "PolledFile.qml")


def run_qs(scenario, state_home):
    """Runs the harness shell once; returns (event list or None, qs output)."""
    cfg = os.path.join(state_home, "cfg")
    data = os.path.join(state_home, "data")
    os.makedirs(cfg)
    os.makedirs(data)
    for name, text in (("a.txt", "alpha\n"), ("b.txt", "beta\n")):
        with open(os.path.join(data, name), "w") as f:
            f.write(text)
    shutil.copy(os.path.join(HERE, "shell.qml"), cfg)
    shutil.copy(SOURCE, cfg)
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update(
        QT_QPA_PLATFORM="offscreen",
        SCENARIO=scenario,
        DATA=data,
        XDG_STATE_HOME=os.path.join(state_home, "state"),
        XDG_RUNTIME_DIR=os.path.join(state_home, "run"),
        HOME=os.path.join(state_home, "home"),
    )
    for name in ("state", "run", "home"):
        os.makedirs(os.path.join(state_home, name), mode=0o700, exist_ok=True)
    proc = subprocess.run(["qs", "-p", cfg], env=env, capture_output=True, text=True, timeout=30)
    out = "qs exit code %d\n" % proc.returncode + proc.stdout + proc.stderr
    try:
        with open(os.path.join(state_home, "state", "result.json")) as f:
            return json.load(f), out
    except (FileNotFoundError, ValueError):
        return None, out


def after_startup(events):
    return [e for e in events if e["t"] >= STARTUP_MS]


def expect(problems, label, got, want):
    if got != want:
        problems.append("%s: got %r, want %r" % (label, got, want))


def reads(events):
    """(kind, file) per read, with the text for a load."""
    return [(e["kind"], e["path"], e.get("text")) for e in events]


def check_loaded(events, out):
    problems = []
    events = after_startup(events)
    expect(problems, "reads", reads(events), [("loaded", "a.txt", "alpha\n")])
    return problems


def check_missing(events, out):
    problems = []
    events = after_startup(events)
    expect(problems, "reads", [(e["kind"], e["not_found"]) for e in events], [("load_failed", True)])
    # The read that fails is expected here, so the log must stay quiet about it. Only lines about the file or its
    # FileView count: qs logs unrelated warnings in some environments (e.g. the IPC server failing to start).
    for line in out.splitlines():
        if "missing.txt" in line or "FileView" in line:
            problems.append("qs log mentions the read: %r" % line.strip())
    return problems


def check_path_change(events, out):
    problems = []
    # A path change may itself start a read, so only the last read after each poll is judged: the file is the new one.
    expect(problems, "last read", reads(events)[-1], ("loaded", "a.txt", "alpha\n"))
    by_path = {}
    for e in events:
        by_path.setdefault(e["path"], []).append(e)
    expect(problems, "b.txt texts", sorted({e.get("text") for e in by_path.get("b.txt", [])}), ["beta\n"])
    expect(problems, "a.txt texts", sorted({e.get("text") for e in by_path.get("a.txt", [])}), ["alpha\n"])
    expect(problems, "missing kinds", sorted({e["kind"] for e in by_path.get("missing.txt", [])}), ["load_failed"])
    # No read of a file may carry another file's text or a stale outcome.
    for e in events:
        if e["kind"] == "loaded" and e["path"] == "b.txt" and e["text"] != "beta\n":
            problems.append("stale read for b.txt: %r" % e)
    # Each explicit poll (500, 900, 1300 ms) must have produced a read of the then-current path.
    for low, high, name in ((500, 700, "b.txt"), (900, 1100, "missing.txt"), (1300, 1600, "a.txt")):
        if not [e for e in events if low <= e["t"] < high and e["path"] == name]:
            problems.append("no read of %s between %d and %d ms" % (name, low, high))
    return problems


def check_disabled(events, out):
    problems = []
    expect(problems, "reads", [(e["kind"], e["t"] >= 450) for e in after_startup(events)], [("loaded", True)])
    return problems


def check_enabled_late(events, out):
    problems = []
    times = [e["t"] for e in after_startup(events)]
    # Enabled at 400 with run_on_start: ticks near 400, 500, 600; disabled at 650: a tick at 700 would make a fourth,
    # so the count shows none after (a late read of the 600 tick must not fail it).
    expect(problems, "count", len(times), 3)
    if times:
        expect(problems, "none before enable", min(times) >= 380, True)
    return problems


def check_interval_start(events, out):
    problems = []
    # The tick at 0 may or may not be told apart from the startup read; what shows is the ticks after it.
    times = [e["t"] for e in after_startup(events)]
    expect(problems, "count", len(times), 3)  # 200, 400, 600
    expect(problems, "read at start", bool([e for e in events if e["t"] < STARTUP_MS]), True)
    for earlier, later in zip(times, times[1:]):
        if not 150 <= later - earlier <= 380:
            problems.append("gap %d ms, want 150..380" % (later - earlier))
    return problems


def check_interval_no_start(events, out):
    problems = []
    times = [e["t"] for e in after_startup(events)]
    expect(problems, "count", len(times), 3)  # 200, 400, 600
    if times:
        expect(problems, "first after one interval", times[0] >= 170, True)
    return problems


def check_no_interval(events, out):
    events = after_startup(events)
    return [] if not events else ["unexpected reads: %r" % events]


SCENARIOS = {
    "loaded": check_loaded,
    "loaded_blocking": check_loaded,
    "missing": check_missing,
    "missing_blocking": check_missing,
    "path_change": check_path_change,
    "path_change_blocking": check_path_change,
    "disabled": check_disabled,
    "enabled_late": check_enabled_late,
    "interval_start": check_interval_start,
    "interval_no_start": check_interval_no_start,
    "no_interval": check_no_interval,
}


def main():
    names = sys.argv[1:] or list(SCENARIOS)
    failed = 0
    for name in names:
        state_home = tempfile.mkdtemp(prefix="polled_file_")
        try:
            events, out = run_qs(name, state_home)
        finally:
            shutil.rmtree(state_home, ignore_errors=True)
        problems = ["no result saved"] if events is None else SCENARIOS[name](events, out)
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
