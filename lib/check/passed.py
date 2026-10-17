#!/usr/bin/env python3
"""Remembers what passed `lib/check.sh`, across every worktree of the repository: whole trees, and single steps by the
content of the files they read.

  lib/check/passed.sh record           files HEAD's tree as passed (refuses a dirty tree)
  lib/check/passed.sh record-changed <base>  files HEAD's tree as passing `check.sh --changed <base>` (refuses a dirty tree)
  lib/check/passed.sh is-passed [rev]  exit 0 when the tree of rev passed; without rev it is HEAD's, and nothing
                                       tracked may be modified
  lib/check/passed.sh passed-somewhere [rev]  exit 0 when the tree of rev passed in any checkout, with or without
                                       repos/; only the symlinks into repos/ are then unverified for this one
  lib/check/passed.sh passed-since <base> [rev]  exit 0 when the tree of rev passed anywhere, or passed
                                       `check.sh --changed <base>`: what a PR needs
  lib/check/passed.sh step-record <step> <key>     files a step as passed for the input key check.sh computed
  lib/check/passed.sh step-is-passed <step> <key>  exit 0 when it was

The caller vouches for what it records: check.sh records a tree once every step passed for that tree's content, or a
scoped pass on top of a recorded base; ship-batch records the same inductive case.

lib/check/passed.sh is a shim around this file. Branches cut before the port still run the shell version against the
same record files, so the line formats and limits here must stay byte-compatible with it. The functions work on the
current directory's repository; main() first moves to its top level, as the shell version did.
"""

import os
import subprocess
import sys

KEEP_ENTRIES = 200
KEEP_STEP_ENTRIES = 2000

USAGE = (
    "usage: lib/check/passed.sh record | record-changed <base> | is-passed [rev] | passed-somewhere [rev] | "
    "passed-since <base> [rev] | step-record <step> <key> | step-is-passed <step> <key>"
)
DIRTY_MESSAGE = "check-passed: uncommitted tracked changes, so the pass is not HEAD's tree"


class GitError(Exception):
    """A git command failed; git has already printed its own message to stderr."""


class DirtyTree(Exception):
    """HEAD's tree cannot be filed: something tracked is modified."""


def git(*args):
    result = subprocess.run(("git", *args), stdout=subprocess.PIPE, check=False)
    if result.returncode != 0:
        raise GitError(args)
    return result.stdout.decode("utf-8", "surrogateescape").rstrip("\n")


def tree_of(rev):
    return git("rev-parse", rev + "^{tree}")


def record_dir():
    return git("rev-parse", "--git-common-dir")


def trees_file():
    return os.path.join(record_dir(), "claude-check-passed-trees")


def steps_file():
    return os.path.join(record_dir(), "claude-check-passed-steps")


def coverage():
    """Only a checkout with repos/ clones verified the symlinks into them (lib/check/steps/symlinks.sh skips those
    links otherwise), so a pass from a worktree does not vouch for the main checkout."""
    # find does not descend into a starting point that is a symlink, so the shell version counted a linked repos/ as
    # empty; kept so both versions file the same coverage.
    if os.path.islink("repos"):
        return "no-repos"
    try:
        with os.scandir("repos") as entries:
            return "with-repos" if next(entries, None) is not None else "no-repos"
    except OSError:
        return "no-repos"


def is_clean():
    return git("status", "--porcelain", "--untracked-files=no") == ""


def read_lines(path):
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError:
        return []
    lines = data.split(b"\n")
    if lines[-1] == b"":
        lines.pop()
    return lines


def has_line(path, text):
    return os.fsencode(text) in read_lines(path)


def replace_file(path, lines):
    """Written beside the target and renamed over it. A concurrent writer's entry can be lost to the rename, which
    only means that pass is checked again."""
    tmp_path = f"{path}.tmp{os.getpid()}"
    with open(tmp_path, "wb") as handle:
        handle.write(b"".join(line + b"\n" for line in lines))
    os.replace(tmp_path, path)


def add_tree_entry(entry):
    path = trees_file()
    wanted = os.fsencode(entry)
    lines = [line for line in read_lines(path) if line != wanted]
    lines.append(wanted)
    replace_file(path, lines[-KEEP_ENTRIES:])


def tree_passed_anywhere(tree):
    path = trees_file()
    return has_line(path, f"{tree} with-repos") or has_line(path, f"{tree} no-repos")


def is_passed(rev="HEAD"):
    """A with-repos pass covers any checkout; a no-repos pass covers only another without repos."""
    if rev == "HEAD" and not is_clean():
        return False
    tree = tree_of(rev)
    path = trees_file()
    if has_line(path, f"{tree} with-repos"):
        return True
    return coverage() == "no-repos" and has_line(path, f"{tree} no-repos")


def passed_somewhere(rev="HEAD"):
    return tree_passed_anywhere(tree_of(rev))


def passed_since(base, rev="HEAD"):
    tree = tree_of(rev)
    base_tree = tree_of(base)
    return tree_passed_anywhere(tree) or has_line(trees_file(), f"{tree} changed-since {base_tree}")


def record():
    """Raises DirtyTree when something tracked is modified."""
    if not is_clean():
        raise DirtyTree(DIRTY_MESSAGE)
    add_tree_entry(f"{tree_of('HEAD')} {coverage()}")


def record_changed(base):
    if not is_clean():
        raise DirtyTree(DIRTY_MESSAGE)
    add_tree_entry(f"{tree_of('HEAD')} changed-since {tree_of(base)}")


def step_is_passed(step, key):
    return has_line(steps_file(), f"{step} {key}")


def step_record(step, key):
    """One line in one write on an O_APPEND descriptor: concurrent recorders never tear a line. The trim's rename may
    drop a concurrent line, which is safe."""
    path = steps_file()
    line = os.fsencode(f"{step} {key}\n")
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        os.write(fd, line)
    finally:
        os.close(fd)
    lines = read_lines(path)
    if len(lines) > KEEP_STEP_ENTRIES:
        replace_file(path, lines[-(KEEP_STEP_ENTRIES // 2) :])


def main(argv):
    """Returns the exit status: 0 yes, 1 no or failed, 2 usage."""
    try:
        os.chdir(git("rev-parse", "--show-toplevel"))
        command = argv[0] if argv else ""
        rest = argv[1:]
        # The shell's ${2:-HEAD}: an empty revision is HEAD too.
        optional_rev = [rest[0]] if rest and rest[0] else []
        if command == "is-passed":
            return int(not is_passed(*optional_rev))
        if command == "passed-somewhere":
            return int(not passed_somewhere(*optional_rev))
        if command == "passed-since":
            if len(rest) < 1:
                return 2
            return int(not passed_since(rest[0], *([rest[1]] if len(rest) > 1 and rest[1] else [])))
        if command == "record":
            record()
            return 0
        if command == "record-changed":
            if len(rest) < 1:
                return 2
            record_changed(rest[0])
            return 0
        if command == "step-is-passed":
            if len(rest) < 2:
                return 2
            return int(not step_is_passed(rest[0], rest[1]))
        if command == "step-record":
            if len(rest) < 2:
                return 2
            step_record(rest[0], rest[1])
            return 0
        print(USAGE, file=sys.stderr)
        return 2
    except DirtyTree as error:
        print(error, file=sys.stderr)
        return 1
    except GitError:
        return 1
    except OSError as error:
        print(f"check-passed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
