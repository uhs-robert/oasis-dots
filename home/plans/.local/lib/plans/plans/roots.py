"""Which repos `plans` reads: the main checkout of the current repo, or every repo under the configured roots (--all)."""

import os
import subprocess

SCAN_DEPTH = 3


class NotInRepo(Exception):
    pass


def main_checkout(cwd="."):
    """The main checkout of the repo around `cwd`. A worktree has no `.plans/` (it is git-ignored), so this goes through
    the common git dir. Its parent is the main checkout, except in a submodule: there the common dir is
    `.git/modules/<name>`, and its `core.worktree` names the checkout."""
    common = git_common_dir(cwd)
    worktree = subprocess.run(["git", "--git-dir", common, "config", "--get", "core.worktree"], capture_output=True, text=True)
    if worktree.returncode == 0 and worktree.stdout.strip():
        return os.path.normpath(os.path.join(common, worktree.stdout.strip()))
    return os.path.dirname(common)


def git_common_dir(cwd):
    result = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise NotInRepo(f"{os.path.abspath(cwd)} is not inside a git repo")
    return result.stdout.strip()


def config_file():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "plans", "roots")


def configured_roots(path=None):
    """The directories in the roots file, one per line. Blank lines and `#` comments are skipped. Without the file, the
    roots are the developer checkouts and the dotfiles repo."""
    path = path or config_file()
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except FileNotFoundError:
        return default_roots()
    return [os.path.expanduser(line.strip()) for line in lines if line.strip() and not line.strip().startswith("#")]


def default_roots():
    # $GITHUB_DIR has the default of lib/common/distro.sh. The installer links ~/.local/share/dotfiles/repos to
    # repos/ in the dotfiles checkout, so the link's target leads back to the repo.
    found = [os.environ.get("GITHUB_DIR") or os.path.expanduser("~/Development")]
    dotfiles_repos = os.path.expanduser("~/.local/share/dotfiles/repos")
    if os.path.isdir(dotfiles_repos):
        try:
            found.append(main_checkout(os.path.dirname(os.path.realpath(dotfiles_repos))))
        except NotInRepo:
            pass
    return found


def repos_under(root, depth=SCAN_DEPTH):
    """The git repos at or under `root`. A root that is a repo is one repo. Otherwise the walk goes `depth` levels
    down and stops descending at each repo. Only a `.git` directory counts: a worktree's `.git` file points at a main
    checkout, which holds the docs."""
    if not os.path.isdir(root):
        return []
    if os.path.isdir(os.path.join(root, ".git")):
        return [os.path.abspath(root)]
    found = []
    if depth == 0:
        return found
    try:
        entries = sorted(os.scandir(root), key=lambda entry: entry.name)
    except OSError:
        return found
    for entry in entries:
        if entry.is_dir(follow_symlinks=False):
            found += repos_under(entry.path, depth - 1)
    return found


def all_repos(config=None):
    seen = []
    for root in configured_roots(config):
        for repo in repos_under(root):
            real = os.path.realpath(repo)
            if real not in seen:
                seen.append(real)
    return seen
