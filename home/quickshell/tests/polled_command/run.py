"""Pins how core/PolledCommand.qml behaves with Quickshell today, in a headless qs.

It guards one assumption: Quickshell ends a Process's stdout at the exit even when a child still holds the pipe, so
`finished` arrives at once. If an upgrade makes the read wait for that child's EOF, `busy` stays true, every later
`run()` is a no-op and polling freezes silently; the `leaked` scenario fails first.

Each scenario runs shell.qml with SCENARIO set and is judged here from the timed event list the shell saves.

  python3 -B run.py [scenario...]
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "..", "..", ".config", "quickshell", "core", "PolledCommand.qml")


def run_qs(scenario, state_home):
    """Runs the harness shell once; returns (event list or None, qs output)."""
    cfg = os.path.join(state_home, "cfg")
    os.makedirs(cfg)
    shutil.copy(os.path.join(HERE, "shell.qml"), cfg)
    shutil.copy(SOURCE, cfg)
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
    proc = subprocess.run(["qs", "-p", cfg], env=env, capture_output=True, text=True, timeout=30)
    out = "qs exit code %d\n" % proc.returncode + proc.stdout + proc.stderr
    try:
        with open(os.path.join(state_home, "state", "result.json")) as f:
            return json.load(f), out
    except (FileNotFoundError, ValueError):
        return None, out


def finished(events):
    return [e for e in events if e["kind"] == "finished"]


def between(problems, label, value, low, high):
    if not low <= value <= high:
        problems.append("%s: %d ms, want %d..%d" % (label, value, low, high))


def expect(problems, label, got, want):
    if got != want:
        problems.append("%s: got %r, want %r" % (label, got, want))


def check_leaked(events):
    problems = []
    done = finished(events)
    expect(problems, "finished", [(e["code"], e["out"]) for e in done], [(0, "hi\n"), (0, "second\n")])
    if done:
        between(problems, "first finished", done[0]["t"], 0, 250)
    expect(problems, "runs accepted", [e["accepted"] for e in events if e["kind"] == "run"], [True, True])
    return problems


def check_rerun_from_handler(events):
    problems = []
    done = finished(events)
    expect(problems, "rerun accepted", [e["accepted"] for e in events if e["kind"] == "rerun"], [True])
    expect(problems, "finished", [(e["code"], e["out"], e["busy"]) for e in done], [(0, "hi\n", False), (0, "second\n", False)])
    return problems


def check_normal(events):
    problems = []
    done = finished(events)
    expect(problems, "finished", [(e["code"], e["out"]) for e in done], [(3, "hi\n")] * 2)
    if done:
        between(problems, "first finished", done[0]["t"], 0, 250)
    return problems


def check_timeout_running(events):
    problems = []
    done = finished(events)
    expect(problems, "finished count", len(done), 1)
    if done:
        between(problems, "finished", done[0]["t"], 280, 1000)
        expect(problems, "output", done[0]["out"], "")
        expect(problems, "killed", done[0]["code"] != 0, True)
    return problems


def check_start_fail(events):
    problems = []
    expect(problems, "start_failed count", len([e for e in events if e["kind"] == "start_failed"]), 1)
    expect(problems, "finished", [(e["code"], e["out"]) for e in finished(events)], [(0, "after\n")])
    return problems


SCENARIOS = {
    "leaked": check_leaked,
    "rerun_from_handler": check_rerun_from_handler,
    "normal": check_normal,
    "timeout_running": check_timeout_running,
    "start_fail": check_start_fail,
}


def main():
    names = sys.argv[1:] or list(SCENARIOS)
    failed = 0
    for name in names:
        state_home = tempfile.mkdtemp(prefix="polled_command_")
        try:
            events, out = run_qs(name, state_home)
        finally:
            shutil.rmtree(state_home, ignore_errors=True)
        problems = ["no result saved"] if events is None else SCENARIOS[name](events)
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
