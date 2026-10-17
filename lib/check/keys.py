"""The keys lib/check.sh records step passes under: a hash of the step's name and of every file it reads, taken from a
snapshot of the working tree.

Branches cut before the Python port still run the shell runner against the same record files, and a pass either one
records must be honoured by the other, so the key input is built byte for byte as the shell built it: classify_tree's
lines are `" <scopes> \t<ls-tree line>"`, where an unscoped path leaves two spaces, and ls-tree's quoting of unusual
paths is kept. lib/check/tests/test_keys.py pins the bytes to goldens taken from the shell version.
"""

import fnmatch
import os
import shutil
import subprocess
from typing import NamedTuple

import scopes


def path_scopes(path):
    """The scopes a change to path reaches, as the space-separated string the key input embeds (the shell runner's
    $scopes: additive scopes first, then the first PATH_SCOPES match's with a leading space)."""
    found = " ".join(scope for pattern, scope in scopes.ADDITIVE_SCOPES if fnmatch.fnmatchcase(path, pattern))
    for pattern, reached in scopes.PATH_SCOPES:
        if fnmatch.fnmatchcase(path, pattern):
            if reached:
                found += " " + reached
            break
    return found


def git_output(*args, env=None):
    """git's stdout, or None when it fails; its stderr goes through."""
    result = subprocess.run(("git", *args), stdout=subprocess.PIPE, env=env, check=False)
    return result.stdout if result.returncode == 0 else None


def snapshot_tree(logs):
    """The content the steps read: the tracked and untracked (not ignored) files as they are in the working tree,
    written as a tree through a scratch index in logs, so neither the real index nor HEAD moves. None when git fails."""
    index = os.path.join(logs, "snapshot.index")
    if not os.path.exists(index):
        real_index = git_output("rev-parse", "--git-path", "index")
        try:
            if real_index is not None:
                shutil.copyfile(os.fsdecode(real_index.rstrip(b"\n")), index)
        except OSError:
            # No real index yet: `git add` builds one from scratch.
            pass
    env = {**os.environ, "GIT_INDEX_FILE": index}
    added = subprocess.run(
        ("git", "add", "-A", "."), env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False
    )
    if added.returncode != 0:
        return None
    tree = git_output("write-tree", env=env)
    return None if tree is None else tree.decode().strip()


class TreeEntry(NamedTuple):
    scope_column: bytes
    # The key input's line: the scope column, a tab, the ls-tree line and a newline.
    classified: bytes
    path: str


def classify_tree(tree):
    """Each file of tree with the scopes its path reaches."""
    listing = subprocess.run(
        ("git", "-c", "core.quotePath=false", "ls-tree", "-r", "--full-tree", tree), stdout=subprocess.PIPE, check=False
    ).stdout
    entries = []
    for line in listing.split(b"\n")[:-1]:
        path = os.fsdecode(line.split(b"\t", 1)[-1])
        scope_column = b" " + os.fsencode(path_scopes(path)) + b" "
        entries.append(TreeEntry(scope_column, scope_column + b"\t" + line + b"\n", path))
    return entries


def hash_object(data):
    result = subprocess.run(("git", "hash-object", "--stdin"), input=data, stdout=subprocess.PIPE, check=False)
    return result.stdout.decode().strip() if result.returncode == 0 else None


def step_key(step, entries, tree, coverage, shell_lists):
    """The key step's pass is recorded under, from the classified entries of tree. shell_lists maps each shell group to
    the files a shell step lints (the run's lists, or the whole groups). None when a listed file is not in the tree (an
    ignored file, say), since its content would go unkeyed."""
    parts = [f"check-step-key 1 {step.name}\n".encode()]
    if step.scope == "tree":
        # symlinks skips the links into a repos/ that is not set up, and git-diff-check compares with HEAD.
        parts.append(f"{tree} {coverage}\n".encode())
        if step.name == "git-diff-check":
            parts.append(git_output("rev-parse", "HEAD^{tree}") or b"")
        if step.name == "ignored-integrations":
            # The snapshot leaves ignored files out, and they are what this step looks for.
            ignored = git_output(
                "ls-files", "--others", "--ignored", "--exclude-standard", "--", "home/voxcmd/.config/voxcmd"
            )
            if ignored is None:
                return None
            parts.append(ignored)
    elif step.scope == "shell":
        for group, files in shell_lists.items():
            parts.append(f"group {group}\n".encode())
            wanted = {path for path in files if path}
            for entry in entries:
                if entry.path in wanted:
                    parts.append(entry.classified)
                    wanted.discard(entry.path)
            if wanted:
                return None
        # Every step reads the "all" files too: a change there reaches it.
        parts.extend(entry.classified for entry in entries if b" all " in entry.scope_column)
    else:
        # The column is space-padded, so a padded scope matches a whole word only.
        scope = f" {step.scope} ".encode()
        parts.extend(
            entry.classified for entry in entries if scope in entry.scope_column or b" all " in entry.scope_column
        )
    return hash_object(b"".join(parts))
