"""Lifecycle tests for core/PolledCommand.qml: one result per run however exit, end of stdout, grace and timeout race.

Each scenario runs shell.qml in a headless qs with SCENARIO set and is judged here from the timed event list the shell
saves. The fake commands leave a `sleep N` child holding stdout open, as a status script with a background job would.

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


# Quickshell 0.3.2 ends a Process's stdout when the process exits, even if a child still holds the pipe, so no real
# command reaches the grace paths. The `sim_` scenarios run a copy of the component whose end of stdout is delayed by
# this many ms, which is what a version that waited for EOF would do.
EOF_DELAY_MS = 3000
HANDLER = """            onStreamFinished: {
                root.drained = true;
                root.settle();
            }"""
HELD_BACK = """            onStreamFinished: eof_delay.restart()"""
DELAY_TIMER = """    Timer {
        id: eof_delay
        interval: %d
        onTriggered: {
            root.drained = true;
            root.settle();
        }
    }

    Timer {
        id: timeout"""


def component_source(scenario):
    with open(SOURCE) as f:
        text = f.read()
    if not scenario.startswith("sim_"):
        return text
    delay = 1000 if scenario in ("sim_late_drain", "sim_rerun_from_handler", "sim_grace_off") else EOF_DELAY_MS
    if HANDLER not in text or text.count("    Timer {\n        id: timeout") != 1:
        raise SystemExit("PolledCommand.qml changed shape: update HANDLER in run.py")
    return text.replace(HANDLER, HELD_BACK).replace("    Timer {\n        id: timeout", DELAY_TIMER % delay)


def run_qs(scenario, state_home):
    """Runs the harness shell once; returns (event list or None, qs output)."""
    cfg = os.path.join(state_home, "cfg")
    os.makedirs(cfg)
    shutil.copy(os.path.join(HERE, "shell.qml"), cfg)
    with open(os.path.join(cfg, "PolledCommand.qml"), "w") as f:
        f.write(component_source(scenario))
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


def check_sim_grace(events):
    problems = []
    done = finished(events)
    # Exit at once, grace 300; the held-back end of stdout at 3 s must not deliver a second time.
    expect(problems, "finished count", len(done), 1)
    if done:
        between(problems, "finished", done[0]["t"], 280, 800)
    return problems


def check_sim_late_drain(events):
    problems = []
    done = finished(events)
    # First run forced at ~200 ms, its end of stdout at 1 s is a no-op, the second run at 1.5 s settles on its own.
    expect(problems, "finished", [e["out"] for e in done], ["hi\n", "second\n"])
    if len(done) == 2:
        between(problems, "first finished", done[0]["t"], 180, 700)
        between(problems, "second finished", done[1]["t"], 1500, 2300)
    expect(problems, "second run accepted", [e["accepted"] for e in events if e["kind"] == "run"], [True, True])
    return problems


def check_sim_rerun_from_handler(events):
    problems = []
    done = finished(events)
    expect(problems, "rerun accepted", [e["accepted"] for e in events if e["kind"] == "rerun"], [True])
    # The rerun's own end of stdout is held back 1 s too; the first run's late end arrives at 1 s, before it.
    expect(problems, "finished", [(e["out"], e["busy"]) for e in done], [("hi\n", False), ("second\n", False)])
    if len(done) == 2:
        between(problems, "second finished", done[1]["t"], 380, 900)
    return problems


def check_sim_timeout_then_grace(events):
    problems = []
    done = finished(events)
    expect(problems, "finished count", len(done), 1)
    if done:
        # Timeout kills at 300, grace 300 after the exit.
        between(problems, "finished", done[0]["t"], 580, 1200)
        expect(problems, "killed", done[0]["code"] != 0, True)
    return problems


def check_sim_timeout_before_grace(events):
    problems = []
    done = finished(events)
    expect(problems, "finished count", len(done), 1)
    if done:
        between(problems, "finished", done[0]["t"], 380, 900)
        expect(problems, "exit code", done[0]["code"], 0)
    return problems


def check_sim_grace_off(events):
    problems = []
    done = finished(events)
    expect(problems, "finished count", len(done), 1)
    if done:
        between(problems, "finished", done[0]["t"], 950, 1500)
    return problems


SCENARIOS = {
    "leaked": check_leaked,
    "rerun_from_handler": check_rerun_from_handler,
    "normal": check_normal,
    "timeout_running": check_timeout_running,
    "start_fail": check_start_fail,
    "sim_grace": check_sim_grace,
    "sim_late_drain": check_sim_late_drain,
    "sim_rerun_from_handler": check_sim_rerun_from_handler,
    "sim_timeout_then_grace": check_sim_timeout_then_grace,
    "sim_timeout_before_grace": check_sim_timeout_before_grace,
    "sim_grace_off": check_sim_grace_off,
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
