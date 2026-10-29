#!/usr/bin/env python3
"""The check runner behind lib/check.sh, whose header documents the command; the steps and scopes are in scopes.py.

Callers parse the output (ship-batch, lib/check/tests/scope.sh reading --plan), so its lines, exit
codes and environment variables match the shell runner this replaced. Run it with `python3 -B`, as the shim does:
lib/check/ must never get a __pycache__.
"""

import fnmatch
import glob
import locale
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True

CHECK_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(os.path.dirname(CHECK_DIR))
sys.path.insert(0, CHECK_DIR)
import passed  # noqa: E402
import scopes  # noqa: E402

USAGE = "usage: lib/check.sh [--plan] [--changed <base> | --paths-from <file|->] [--only <step>[,<step>...]]"
SHELL_GROUP_NAMES = ("plain", "sourcing", "agent")
FAILURE_TAIL_LINES = 25


class UsageError(Exception):
    pass


class Options:
    def __init__(self, argv):
        self.plan = False
        self.changed_base = ""
        self.paths_from = ""
        self.only = []
        args = list(argv)
        while args:
            arg = args.pop(0)
            if arg == "--plan":
                self.plan = True
            elif arg in ("--changed", "--paths-from") and args:
                # An empty value counts as not given, as the shell's `[ -n ]` tests did.
                setattr(self, "changed_base" if arg == "--changed" else "paths_from", args.pop(0))
            elif arg == "--only" and args:
                names = [name for name in args.pop(0).split(",") if name]
                if not names:
                    raise UsageError
                self.only.extend(names)
            else:
                raise UsageError

    def unknown_steps(self):
        known = {step.name for step in scopes.STEPS}
        return [name for name in self.only if name not in known]


def env_set(name):
    return bool(os.environ.get(name))


def runs_in_part(step):
    """Whether this run runs only part of step, so its pass would vouch for more than ran. VOXCMD_ONLY_SECTIONS
    reaches the voxcmd suites (home/voxcmd/tests/lib.sh) through the environment and runs only the sections it names;
    the Rust crate's step never reads it."""
    return step.scope in scopes.VOXCMD_SUITE_SCOPES and env_set("VOXCMD_ONLY_SECTIONS")


def job_count():
    """CHECK_JOBS, default half the cores, clamped to [1, 4] even when set."""
    wanted = os.environ.get("CHECK_JOBS", "")
    if not wanted:
        try:
            cores = int(subprocess.run(("nproc",), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout)
        except (OSError, ValueError):
            cores = 2
        wanted = str(cores // 2)
    try:
        jobs = int(wanted)
    except ValueError:
        # The shell's `[ "$jobs" -le 4 ] || jobs=4` took a non-number as too many.
        jobs = 4
    return max(1, min(jobs, 4))


def lower_priority():
    """What lib/check/lock.sh's check_lower_priority does for the shell: nice 19 and the idle IO class, inherited by
    every step. Done before any thread starts, since both are per thread on Linux and a new thread copies its
    creator's."""
    try:
        os.setpriority(os.PRIO_PROCESS, 0, 19)
    except OSError:
        pass
    if shutil.which("ionice"):
        subprocess.run(
            ("ionice", "-c", "3", "-p", str(os.getpid())), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )


def read_lines(data):
    """The lines of data as `while read` sees them, keeping a final line with no newline."""
    lines = data.split(b"\n")
    if lines[-1] == b"":
        lines.pop()
    return [os.fsdecode(line) for line in lines]


def git_lines(*args):
    """git's stdout lines, or None when it fails; its stderr is dropped."""
    result = subprocess.run(("git", *args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    return read_lines(result.stdout) if result.returncode == 0 else None


class ChangeSet:
    """What this run is scoped to: the scopes the changed paths reach ("all" for a full run), the changed paths, and
    whether any was deleted."""

    def __init__(self, reached, changed, any_deleted, label):
        self.reached = reached
        self.changed = changed
        self.any_deleted = any_deleted
        self.label = label

    @classmethod
    def from_options(cls, options):
        full = env_set("CHECK_FULL")
        if options.paths_from and not full:
            return cls.from_path_list(options.paths_from)
        if options.changed_base and not full:
            change_set = cls.from_diff(options.changed_base)
            if change_set:
                return change_set
            print(f"check: cannot diff against {options.changed_base}, running everything", file=sys.stderr)
        return cls({"all"}, set(), False, "full")

    @classmethod
    def from_path_list(cls, source):
        """A path list is trusted as given (no untracked files added); a listed path that is gone counts as deleted."""
        if source == "-":
            data = sys.stdin.buffer.read()
        else:
            with open(source, "rb") as handle:
                data = handle.read()
        changed = {path for path in read_lines(data) if path}
        any_deleted = any(not os.path.lexists(path) for path in changed)
        return cls(reached_by(changed), changed, any_deleted, f"scoped to {len(changed)} listed files")

    @classmethod
    def from_diff(cls, base):
        """None when base is no commit or git cannot diff against it."""
        verified = subprocess.run(
            ("git", "rev-parse", "--verify", "-q", base + "^{commit}"), stdout=subprocess.DEVNULL, check=False
        )
        if verified.returncode != 0:
            return None
        changed_lines = git_lines("diff", "--name-only", "--no-renames", base, "--")
        untracked = git_lines("ls-files", "-o", "--exclude-standard") if changed_lines is not None else None
        if untracked is None:
            return None
        changed = set(changed_lines) | set(untracked)
        any_deleted = bool(git_lines("diff", "--name-only", "--no-renames", "--diff-filter=D", base, "--"))
        return cls(reached_by(changed), changed, any_deleted, f"scoped to {len(changed)} files changed since {base}")


def reached_by(paths):
    reached = set()
    for path in paths:
        reached.update(scopes.path_scopes(path).split())
    return reached


def sorted_like_shell(names):
    """In the order the shell sorts a glob's matches or `sort` its lines: the locale's collation."""
    return sorted(names, key=locale.strxfrm)


def expand_glob(pattern):
    """A shell glob's matches, or the pattern itself as the shell leaves it when nothing matches."""
    if not glob.has_magic(pattern):
        return [pattern]
    return sorted_like_shell(glob.glob(pattern)) or [pattern]


def agent_shell_files():
    """Tracked *.sh plus extension-less files with a sh/bash shebang. Paths git quotes name no file and so drop out."""
    excludes = [":!:" + path for path in scopes.AGENT_SHELL_EXCLUDES]
    shebang = re.compile(scopes.AGENT_SHEBANG)
    found = []
    for path in git_lines("ls-files", "--", *scopes.AGENT_SHELL_ROOTS, *excludes) or []:
        if not os.path.isfile(path) or os.path.islink(path):
            continue
        name = path.rsplit("/", 1)[-1]
        if fnmatch.fnmatchcase(name, "*.sh"):
            found.append(path)
        elif not fnmatch.fnmatchcase(name, "*.*"):
            with open(path, "rb") as handle:
                first_line = os.fsdecode(handle.readline().rstrip(b"\n"))
            if shebang.search(first_line):
                found.append(path)
    return found


class ShellLists:
    """The shell files per group: every member (whole), the members shellcheck lints this run (lint) and those shfmt
    checks (fmt). Scoped, shfmt sees only changed files, and shellcheck lints a group whole when any member changed,
    since a member can source another."""

    def __init__(self, change_set):
        self.whole = {
            group: [file for pattern in patterns for file in expand_glob(pattern)]
            for group, patterns in scopes.SHELL_GROUPS.items()
        }
        self.whole["agent"] = agent_shell_files()
        if "all" in change_set.reached:
            self.lint = dict(self.whole)
            self.fmt = dict(self.whole)
            return
        self.fmt = {
            group: [file for file in files if file in change_set.changed] for group, files in self.whole.items()
        }
        # A sourced file is read by shellcheck only when it is on the same command line, and a deleted file is in no
        # group any more yet a member that sourced it now fails: so any member changed, or any deletion, lints a group.
        self.lint = {
            group: files if self.fmt[group] or change_set.any_deleted else [] for group, files in self.whole.items()
        }

    def write(self, logs):
        """The lists the shellcheck and shfmt steps read from $CHECK_LOGS."""
        for group in SHELL_GROUP_NAMES:
            for suffix, lists in ((".list", self.lint), (".fmt.list", self.fmt)):
                with open(os.path.join(logs, group + suffix), "wb") as handle:
                    handle.write(b"".join(os.fsencode(file) + b"\n" for file in lists[group]))


def step_in_scope(step, change_set, shell_lists):
    """The cheap always-run steps, or one a changed path reaches."""
    if "all" in change_set.reached or step.scope == "tree":
        return True
    if step.scope == "shell":
        lists = shell_lists.fmt if step.name == "shfmt" else shell_lists.lint
        return any(lists[group] for group in SHELL_GROUP_NAMES)
    return step.scope in change_set.reached


missing_tool_cache = {}


def missing_tool(step):
    """The skip line of a step whose optional tool is missing, or ""."""
    if step.name not in missing_tool_cache:
        missing = any(shutil.which(tool) is None for tool in step.needs) or (
            step.probe and subprocess.run(("sh", "-c", step.probe), check=False).returncode != 0
        )
        missing_tool_cache[step.name] = f"skip: {step.skip_reason}" if missing else ""
    return missing_tool_cache[step.name]


def write_out(data, stream=None):
    stream = stream or sys.stdout
    stream.flush()
    stream.buffer.write(data)
    stream.buffer.flush()


def print_out(text, stream=None):
    write_out(text.encode() + b"\n", stream)


def git_output(*args):
    """git's stdout, or None when it fails; its stderr goes through."""
    result = subprocess.run(("git", *args), stdout=subprocess.PIPE, check=False)
    return result.stdout if result.returncode == 0 else None


def clean_head_tree():
    """HEAD's tree when nothing is modified or untracked (ignored files aside), else None."""
    status = git_output("status", "--porcelain")
    head_tree = git_output("rev-parse", "HEAD^{tree}")
    if status or head_tree is None:
        return None
    return head_tree.decode().strip()


def process_stat(pid):
    """The fields of /proc/<pid>/stat after the command name (state first, then the parent's pid), or None once the
    process is gone. The name may hold spaces and parentheses, so the fields count from its last closing one."""
    try:
        with open(f"/proc/{pid}/stat", "rb") as handle:
            stat = handle.read()
    except OSError:
        return None
    return stat[stat.rindex(b")") + 2 :].split()


def descendant_pids():
    """Every live process below this one: a step's shell may have children of its own."""
    children = {}
    for entry in os.listdir("/proc"):
        fields = process_stat(entry) if entry.isdigit() else None
        if fields and fields[0] != b"Z":
            children.setdefault(int(fields[1]), []).append(int(entry))
    found, pending = [], [os.getpid()]
    while pending:
        for child in children.get(pending.pop(), []):
            found.append(child)
            pending.append(child)
    return found


class StepPool:
    """Runs the steps. A failing step's log is kept for the tail printed at the end."""

    def __init__(self, logs, jobs):
        self.logs = logs
        self.jobs = jobs
        self.env = {**os.environ, "CHECK_LOGS": logs, "CHECK_JOBS": str(jobs), "PWD": REPO_DIR}
        # Held to print a step's block whole and to start a step, so a stop sees every step that started.
        self.lock = threading.RLock()
        self.stopping = False
        self.failed = set()

    def log_path(self, step):
        return os.path.join(self.logs, step.name + ".log")

    def start(self, step, live):
        """The step's process and its open log, or None once the run is being stopped. A live step's output comes
        through a pipe, and its stdin is the check's; otherwise both are files, as xargs gave the shell runner's."""
        with self.lock:
            if self.stopping:
                return None
            log = open(self.log_path(step), "wb")
            # close_fds keeps lock.sh's slot descriptor (fd 7), and any other, from the steps.
            process = subprocess.Popen(
                ("sh", "-c", step.command),
                stdin=None if live else subprocess.DEVNULL,
                stdout=subprocess.PIPE if live else log,
                stderr=subprocess.STDOUT,
                env=self.env,
            )
            return process, log

    def run_live(self, step):
        """One step at a time: its output shows as it comes, and goes to its log too."""
        print_out(f"== {step.name}")
        started = self.start(step, live=True)
        if started is None:
            return
        process, log = started
        with log:
            while chunk := os.read(process.stdout.fileno(), 65536):
                write_out(chunk)
                log.write(chunk)
            process.stdout.close()
            if process.wait() != 0:
                self.failed.add(step.name)

    def run_buffered(self, step):
        """One of several at once: its output is buffered in its log, so parallel steps never interleave."""
        started_at = int(time.time())
        started = self.start(step, live=False)
        if started is None:
            return
        process, log = started
        with log:
            status = process.wait()
        took = int(time.time()) - started_at
        with self.lock:
            if self.stopping:
                return
            if status != 0:
                self.failed.add(step.name)
                print_out(f"== {step.name} FAILED ({took}s)")
                with open(self.log_path(step), "rb") as log:
                    write_out(log.read())
            else:
                print_out(f"== {step.name} ok ({took}s)")

    def run(self, lane_steps, other_steps):
        """The serial-lane steps one after another in a lane of their own, the rest in a pool of the remaining jobs."""
        if self.jobs <= 1:
            for step in lane_steps + other_steps:
                self.run_live(step)
            return
        threads = []
        pool_size = self.jobs
        if lane_steps:
            pool_size -= 1
            threads.append(threading.Thread(target=lambda: [self.run_buffered(step) for step in lane_steps]))
        queue = list(other_steps)
        queue_lock = threading.Lock()

        def pool_worker():
            while True:
                with queue_lock:
                    if not queue:
                        return
                    step = queue.pop(0)
                self.run_buffered(step)

        threads.extend(threading.Thread(target=pool_worker) for _ in range(min(pool_size, len(other_steps))))
        for thread in threads:
            thread.daemon = True
            thread.start()
        for thread in threads:
            thread.join()

    def abort(self):
        """Ends every running step, its children included, removes the temp dir and exits 1: TERM, then KILL for
        whatever is left after a grace period. The steps share this process group, as GNU timeout
        needs to reach them, so a TERM sent to this process alone would otherwise leave them running. The lock is held
        to the end, so no step starts and no log is opened behind the removal."""
        with self.lock:
            self.stopping = True
            signalled = set()
            deadline = time.monotonic() + 2
            while True:
                # Again each round, for what a step's TERM trap starts.
                for pid in set(descendant_pids()) - signalled:
                    signalled.add(pid)
                    send_signal(pid, signal.SIGTERM)
                if not alive(signalled) or time.monotonic() > deadline:
                    break
                time.sleep(0.05)
            for pid in alive(signalled):
                send_signal(pid, signal.SIGKILL)
            shutil.rmtree(self.logs, ignore_errors=True)
            os._exit(1)


def send_signal(pid, signum):
    try:
        os.kill(pid, signum)
    except OSError:
        pass


def alive(pids):
    """Those of pids still running (not gone, not a zombie)."""
    return [pid for pid in pids if (fields := process_stat(pid)) and fields[0] != b"Z"]


def tail(data, count):
    """tail -n count: a last line with no newline counts as a line."""
    lines = data.split(b"\n")
    ends_with_newline = lines[-1] == b""
    if ends_with_newline:
        lines.pop()
    return b"\n".join(lines[-count:]) + (b"\n" if ends_with_newline and lines else b"")


def ignoring_git_errors(action, *args):
    """Runs a passed.py action as `lib/check/passed.sh ... || true` did: git has printed its own error."""
    try:
        return action(*args)
    except passed.GitError:
        return False
    except (passed.DirtyTree, OSError) as error:
        print(error if isinstance(error, passed.DirtyTree) else f"check-passed: {error}", file=sys.stderr)
        return False


def name_list(names):
    """Names as the summary line lists them: each after a space."""
    return "".join(" " + name for name in names)


def summary_line(label, ran, skipped_by_scope, skipped_by_request):
    """The line callers parse for what ran (lib/check/tests/scope.sh, ship-batch's and the hooks' readers)."""
    line = f"check: {label}; ran:{name_list(ran)};"
    line += f" skipped by scope:{name_list(skipped_by_scope) or ' none'}"
    if skipped_by_request:
        line += f"; skipped by request:{name_list(skipped_by_request)}"
    return line


def print_failures(failed, pool):
    print_out("FAILED:" + name_list(step.name for step in failed), sys.stderr)
    for step in failed:
        with open(pool.log_path(step), "rb") as log:
            last_lines = tail(log.read(), FAILURE_TAIL_LINES)
        write_out(f"\n== {step.name} (last {FAILURE_TAIL_LINES} lines)\n".encode() + last_lines, sys.stderr)


def run(options, logs, pool):
    change_set = ChangeSet.from_options(options)
    shell_lists = ShellLists(change_set)

    # HEAD's tree if the working tree is clean before the run and still is after it: only then does a pass vouch for
    # that tree.
    tree_before = None if options.plan else clean_head_tree()

    skip_steps = f" {os.environ.get('CHECK_SKIP_STEPS', '')} "
    ran, skipped_by_scope, skipped_by_request, skip_lines = [], [], [], set()
    for step in scopes.STEPS:
        # A step --only leaves out is not skipped, it is outside the run, so no summary list names it.
        if options.only and step.name not in options.only:
            continue
        if f" {step.name} " in skip_steps:
            skipped_by_request.append(step.name)
            continue
        if not step_in_scope(step, change_set, shell_lists):
            skipped_by_scope.append(step.name)
            continue
        # The plan is the same on a machine without the tools, so the scope test does not depend on them.
        missing = "" if options.plan else missing_tool(step)
        if missing:
            skip_lines.add(missing)
            continue
        ran.append(step)

    for line in sorted_like_shell(skip_lines):
        print_out(line)
    ran_names = [step.name for step in ran]
    label = change_set.label
    if options.only:
        label = "only " + ",".join(options.only) + ("" if label == "full" else ", " + label)
    print_out(summary_line(label, ran_names, skipped_by_scope, skipped_by_request))

    if options.plan:
        for group in SHELL_GROUP_NAMES:
            for file in shell_lists.lint[group]:
                print_out(f"shellcheck {group}: {file}")
        return 0

    shell_lists.write(logs)
    pool.run([step for step in ran if step.serial_lane], [step for step in ran if not step.serial_lane])

    failed = [step for step in ran if step.name in pool.failed]
    if failed:
        print_failures(failed, pool)
    ran_in_part = [step.name for step in ran if runs_in_part(step)]
    if ran_in_part:
        print_out(f"check: VOXCMD_ONLY_SECTIONS is set, so no pass is recorded for{name_list(ran_in_part)}")
    if failed:
        return 1

    # --paths-from checks a list someone chose and --only the steps someone chose, which vouch for no tree; neither
    # does a step that ran in part.
    if not options.paths_from and not options.only and not ran_in_part and tree_before:
        if clean_head_tree() == tree_before:
            if options.changed_base:
                ignoring_git_errors(passed.record_changed, options.changed_base)
            # Inductive: a base that passed, plus a scoped pass over everything changed since, vouches for the tree, as
            # does a run that reached every step.
            if ("all" in change_set.reached and not skipped_by_request) or (
                options.changed_base and ignoring_git_errors(passed.passed_somewhere, options.changed_base)
            ):
                ignoring_git_errors(passed.record)

    print_out("All checks passed")
    return 0


def main(argv):
    try:
        options = Options(argv)
    except UsageError:
        print(USAGE, file=sys.stderr)
        return 2
    unknown = options.unknown_steps()
    if unknown:
        steps = " ".join(step.name for step in scopes.STEPS)
        print(f"check: unknown step {', '.join(repr(name) for name in unknown)}; steps: {steps}", file=sys.stderr)
        return 2
    try:
        locale.setlocale(locale.LC_COLLATE, "")
    except locale.Error:
        # A locale the environment names but the host lacks: the shell warned and sorted in C order, so do the same.
        pass
    os.chdir(REPO_DIR)
    if not options.plan:
        lower_priority()
    logs = tempfile.mkdtemp()
    pool = StepPool(logs, job_count())

    def abort_on_signal(signum, frame):
        pool.abort()

    for signum in (signal.SIGINT, signal.SIGTERM):
        # A signal ignored when the check started (INT in a background job) stays ignored, as it did for the shell.
        if signal.getsignal(signum) is not signal.SIG_IGN:
            signal.signal(signum, abort_on_signal)
    try:
        return run(options, logs, pool)
    except BrokenPipeError:
        # The reader of the output is gone (`| head`): end quietly, as the shell did on SIGPIPE.
        pool.abort()
    except OSError as error:
        print(f"check: {error}", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(logs, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
