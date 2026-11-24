"""Tests the runner's per-step timeout and how it ends a step: the whole process group, grandchildren and orphans
included, KILL for a step that ignores TERM, the slot a killed step held, and Ctrl-C of the whole check. Each case runs
a small driver in a child process that hands made-up steps with tiny timeouts to runner.StepPool.
"""

import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
CHECK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DRIVER = """
import json, os, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import runner, scopes
spec = json.loads(sys.argv[2])
os.chdir(runner.REPO_DIR)
pool = runner.StepPool(spec["logs"], spec["jobs"])
runner.abort_on_signals(pool)
steps = [
    scopes.Step(step["name"], "tree", step["command"], serial_lane=step.get("lane", False),
                **({"timeout_secs": step["timeout"]} if "timeout" in step else {}))
    for step in spec["steps"]
]
pool.run([step for step in steps if step.serial_lane], [step for step in steps if not step.serial_lane])
print("failed:" + "".join(" " + name for name in sorted(pool.failed)))
"""

# Writes its pid to $SCRATCH/<name> and sleeps: a child of whatever shell runs it.
def sleeper(name):
    return f'sleep 300 & echo $! >"$SCRATCH/{name}"'


def process_alive(pid):
    try:
        with open(f"/proc/{pid}/stat", "rb") as handle:
            stat = handle.read()
    except OSError:
        return False
    return stat[stat.rindex(b")") + 2 :].split()[0] != b"Z"


class StepTimeoutTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.mkdtemp()
        self.logs = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.scratch, True)
        self.addCleanup(shutil.rmtree, self.logs, True)
        self.addCleanup(self.kill_recorded)
        self.env = {**os.environ, "SCRATCH": self.scratch, "XDG_RUNTIME_DIR": self.scratch}
        for name in ("CHECK_LOCK_HELD", "CHECK_NO_LOCK", "CHECK_HEAVY_SLOTS", "SANDBOX_REAL_XDG_RUNTIME_DIR"):
            self.env.pop(name, None)

    def recorded_pids(self, names):
        pids = []
        for name in names:
            with open(os.path.join(self.scratch, name)) as handle:
                pids.append(int(handle.read()))
        return pids

    def kill_recorded(self):
        """Kills and forgets the recorded processes, so a failed case leaves nothing behind for the next."""
        for name in os.listdir(self.scratch):
            path = os.path.join(self.scratch, name)
            try:
                with open(path) as handle:
                    os.kill(int(handle.read()), signal.SIGKILL)
            except (OSError, ValueError):
                pass
            os.remove(path)

    def driver(self, steps, jobs):
        spec = json.dumps({"logs": self.logs, "jobs": jobs, "steps": steps})
        return subprocess.Popen(
            (sys.executable, "-B", "-c", DRIVER, CHECK_DIR, spec),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=self.env,
        )

    def run_steps(self, steps, jobs=2):
        started = time.monotonic()
        process = self.driver(steps, jobs)
        output = process.communicate(timeout=60)[0].decode()
        return output, time.monotonic() - started

    def failed_line(self, output):
        return next(line for line in output.splitlines() if line.startswith("failed:"))

    def assert_all_gone(self, names):
        pids = self.recorded_pids(names)
        deadline = time.monotonic() + 2
        while any(process_alive(pid) for pid in pids) and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertEqual([pid for pid in pids if process_alive(pid)], [])

    def wait_for_files(self, names):
        deadline = time.monotonic() + 10
        while not all(os.path.exists(os.path.join(self.scratch, name)) for name in names):
            self.assertLess(time.monotonic(), deadline, "the step never started its children")
            time.sleep(0.05)
        # The pid is written after the file is created.
        time.sleep(0.1)

    # A child, a grandchild, and an orphan whose parent exits: it moves to init but stays in the step's group.
    HUNG = (
        f"{sleeper('child')}; sh -c '{sleeper('grandchild')}; wait' & "
        f"sh -c '{sleeper('orphan')}'; wait"
    )

    def test_a_hung_step_fails_and_its_grandchildren_and_orphans_are_killed(self):
        for jobs in (1, 2):
            with self.subTest(jobs=jobs):
                self.kill_recorded()
                output, took = self.run_steps(
                    [{"name": "hung", "command": self.HUNG, "timeout": 0.5}, {"name": "after", "command": "true"}],
                    jobs,
                )
                self.assertEqual(self.failed_line(output), "failed: hung")
                self.assertIn("check: hung timed out after 0.5s and was killed with its processes", output)
                self.assertIn("== after", output)
                self.assertLess(took, 10)
                self.assert_all_gone(("child", "grandchild", "orphan"))

    def test_a_step_that_ignores_term_gets_kill_after_the_grace_period(self):
        for jobs in (1, 2):
            with self.subTest(jobs=jobs):
                self.kill_recorded()
                command = f"trap '' TERM; {sleeper('deaf')}; sh -c '{sleeper('deaf-grandchild')}; wait' & wait"
                output, took = self.run_steps([{"name": "deaf", "command": command, "timeout": 0.3}], jobs)
                self.assertEqual(self.failed_line(output), "failed: deaf")
                self.assertIn("timed out after 0.3s", output)
                # The grace period passed before the KILL, and the KILL came.
                self.assertGreaterEqual(took, 2)
                self.assertLess(took, 10)
                self.assert_all_gone(("deaf", "deaf-grandchild"))

    def test_the_override_sets_the_limit_per_step(self):
        output, _ = self.run_steps(
            [
                {"name": "short-limit", "command": "sleep 1", "timeout": 0.2},
                {"name": "long-limit", "command": "sleep 1", "timeout": 5},
                {"name": "default-limit", "command": "sleep 1"},
            ]
        )
        self.assertEqual(self.failed_line(output), "failed: short-limit")
        self.assertIn("short-limit timed out after 0.2s", output)
        self.assertIn("== long-limit ok", output)
        self.assertIn("== default-limit ok", output)

    def test_the_default_limit_is_30_minutes(self):
        sys.path.insert(0, CHECK_DIR)
        import scopes

        self.assertEqual(scopes.Step("x", "tree", "true").timeout_secs, 30 * 60)

    def test_a_step_that_finishes_is_not_timed_out_and_does_not_wait_for_its_limit(self):
        for jobs in (1, 2):
            with self.subTest(jobs=jobs):
                self.kill_recorded()
                output, took = self.run_steps(
                    [
                        {"name": "quick", "command": "true", "timeout": 20},
                        {"name": "broken", "command": "exit 3", "timeout": 20},
                    ],
                    jobs,
                )
                self.assertEqual(self.failed_line(output), "failed: broken")
                self.assertIn("== quick", output)
                self.assertNotIn("timed out", output)
                self.assertLess(took, 10)

    def test_a_killed_step_frees_its_heavy_step_slot(self):
        if shutil.which("flock") is None:
            self.skipTest("the slot test needs flock")
        take = ". ./lib/check/lock.sh; CHECK_LOCK_WAIT_SECS=3 check_lock_take"
        output, _ = self.run_steps(
            [
                {"name": "holder", "command": f"{take} holder || exit 1; {sleeper('holder')}; wait", "lane": True, "timeout": 0.5},
                {"name": "next", "command": f"{take} next", "lane": True, "timeout": 10},
                {"name": "pooled", "command": "sleep 0.2", "timeout": 10},
            ],
            jobs=3,
        )
        self.assertEqual(self.failed_line(output), "failed: holder")
        self.assertIn("== next ok", output)
        self.assertIn("== pooled ok", output)
        self.assert_all_gone(("holder",))

    def test_interrupting_the_check_ends_every_step_group_and_removes_the_logs(self):
        for jobs in (1, 2):
            with self.subTest(jobs=jobs):
                self.kill_recorded()
                os.makedirs(self.logs, exist_ok=True)
                deaf = f"trap '' TERM; {sleeper('deaf')}; wait"
                steps = [{"name": "hung", "command": self.HUNG}]
                if jobs > 1:
                    steps.append({"name": "deaf", "command": deaf})
                process = self.driver(steps, jobs)
                self.wait_for_files(("child", "grandchild", "orphan") + (("deaf",) if jobs > 1 else ()))
                process.send_signal(signal.SIGINT)
                self.assertEqual(process.wait(timeout=10), 1)
                process.stdout.close()
                self.assert_all_gone(("child", "grandchild", "orphan") + (("deaf",) if jobs > 1 else ()))
                self.assertFalse(os.path.exists(self.logs))


if __name__ == "__main__":
    unittest.main()
