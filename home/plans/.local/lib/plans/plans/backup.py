"""`plans backup` and `plans restore`: encrypted restic snapshots of every repo's `.plans/` and `.logs/`.

Both folders are git-ignored, so this is their only copy. restic stores absolute paths, so a restore lands under
`<target>/<absolute path>`, and the repo of a restored file is the snapshot path minus its last part.
"""

import filecmp
import json
import os
import secrets
import shutil
import subprocess
import tempfile

from . import roots

REPO_ENV = "PLANS_BACKUP_REPO"
PASSWORD_FILE_ENV = "PLANS_BACKUP_PASSWORD_FILE"
DEFAULT_REPO = "rclone:gdrive:backups/plans"
BACKED_UP = (".plans", ".logs")
KEEP = ("--keep-hourly", "48", "--keep-daily", "30")


class BackupError(Exception):
    """A request the command cannot do or a restic call that failed."""


def repo_url():
    return os.environ.get(REPO_ENV) or DEFAULT_REPO


def password_file():
    if os.environ.get(PASSWORD_FILE_ENV):
        return os.environ[PASSWORD_FILE_ENV]
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "plans", "backup-password")


def restic_env():
    env = dict(os.environ)
    env["RESTIC_REPOSITORY"] = repo_url()
    env["RESTIC_PASSWORD_FILE"] = password_file()
    # A stray password in the caller's shell must not win over the file.
    env.pop("RESTIC_PASSWORD", None)
    env.pop("RESTIC_PASSWORD_COMMAND", None)
    return env


def run_restic(args, capture=False):
    try:
        result = subprocess.run(["restic", *args], env=restic_env(), capture_output=capture, text=True)
    except FileNotFoundError:
        raise BackupError("restic is not installed") from None
    if result.returncode != 0:
        detail = (result.stderr or "").strip()
        raise BackupError(f"restic {args[0]} failed (exit {result.returncode})" + (f": {detail}" if detail else ""))
    return result.stdout if capture else None


def check_password_file():
    path = password_file()
    try:
        mode = os.stat(path).st_mode
    except FileNotFoundError:
        raise BackupError(f"no password file at {path}; run `plans backup --init` first") from None
    if mode & 0o077:
        raise BackupError(f"{path} is readable by others; run chmod 600 on it")


def create_password_file():
    """Make the password file once. Never overwrites: losing the password loses every backup."""
    path = password_file()
    if os.path.exists(path):
        return False
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(secrets.token_urlsafe(32) + "\n")
    return True


def backup_paths(config=None):
    """Every existing `.plans/` and `.logs/` of the repos under the roots."""
    found = []
    for repo in roots.all_repos(config):
        for name in BACKED_UP:
            path = os.path.join(repo, name)
            if os.path.isdir(path):
                found.append(path)
    return found


def init(out):
    if create_password_file():
        out(f"wrote a new password to {password_file()}: copy it into the password manager now")
    check_password_file()
    run_restic(["init"])
    out(f"initialised {repo_url()}")


def backup(out, config=None):
    check_password_file()
    paths = backup_paths(config)
    if not paths:
        out("nothing to back up: no .plans/ or .logs/ under the roots")
        return
    run_restic(["backup", "--tag", "plans", *paths])
    # Group by host only: the paths change as repos come and go, and a path-based group would keep its last snapshot
    # for good.
    run_restic(["forget", "--prune", "--group-by", "host", *KEEP])
    out(f"backed up {len(paths)} folders")


def list_snapshots(out):
    check_password_file()
    snapshots = json.loads(run_restic(["snapshots", "--json"], capture=True) or "[]")
    if not snapshots:
        out("no snapshots")
    for snap in snapshots:
        repos = sorted({os.path.dirname(path) for path in snap.get("paths") or []})
        out("\t".join([snap["id"][:8], snap.get("time", "")[:19], snap.get("hostname", ""), f"{len(repos)} repos"]))


def under_roots(path, config=None):
    real = os.path.realpath(path)
    for root in roots.configured_roots(config):
        root = os.path.realpath(root)
        if real == root or real.startswith(root + os.sep):
            return True
    return False


def snapshot_folders(snapshot):
    output = run_restic(["snapshots", "--json", snapshot], capture=True)
    snaps = json.loads(output or "[]")
    if not snaps:
        raise BackupError(f"no snapshot {snapshot}")
    folders = [p for p in snaps[-1].get("paths") or [] if os.path.basename(p) in BACKED_UP]
    return sorted(folders)


def pick_folders(folders, repo, config):
    """The snapshot folders to restore, as (folder, skip reason or None). An explicit --repo outside the roots is
    refused outright, since a restore writes into it."""
    if repo:
        wanted = os.path.realpath(os.path.expanduser(repo)) if os.sep in repo else repo
        if os.sep in repo and not under_roots(wanted, config):
            raise BackupError(f"{wanted} is not under the roots; refusing")
        folders = [f for f in folders
                   if os.path.dirname(f) == wanted or os.path.basename(os.path.dirname(f)) == repo]
        if not folders:
            raise BackupError(f"the snapshot holds no .plans/ or .logs/ for {repo}")
    picked = []
    for folder in folders:
        repo_dir = os.path.dirname(folder)
        if not under_roots(repo_dir, config):
            picked.append((folder, "not under the roots"))
        elif not os.path.isdir(repo_dir):
            picked.append((folder, "repo is not cloned here"))
        else:
            picked.append((folder, None))
    return picked


def restored_files(target, folder):
    top = os.path.join(target, folder.lstrip(os.sep))
    for base, dirs, files in os.walk(top):
        for name in sorted(files):
            path = os.path.join(base, name)
            if os.path.islink(path):
                continue
            yield os.path.relpath(path, top)


def restore(snapshot, repo, apply, out, config=None):
    """Restore into a temp folder, report the files that differ and, with `apply`, copy them over. It never deletes a
    file the snapshot lacks. Returns True when every folder was handled."""
    check_password_file()
    picked = pick_folders(snapshot_folders(snapshot), repo, config)
    usable = [folder for folder, reason in picked if reason is None]
    clean = True
    for folder, reason in picked:
        if reason:
            clean = False
            out(f"skipped {folder}: {reason}")
    if not usable:
        return False
    target = tempfile.mkdtemp(prefix="plans-restore-")
    try:
        include = [arg for folder in usable for arg in ("--include", folder)]
        run_restic(["restore", snapshot, "--target", target, *include])
        changed = 0
        for folder in usable:
            for rel in restored_files(target, folder):
                state = compare(os.path.join(target, folder.lstrip(os.sep), rel), os.path.join(folder, rel))
                if state == "same":
                    continue
                changed += 1
                out(f"{state}\t{os.path.join(folder, rel)}")
                if apply:
                    copy_in(os.path.join(target, folder.lstrip(os.sep), rel), folder, rel)
        verb = "restored" if apply else "differ (run again with --apply to restore)"
        out(f"{changed} files {verb}")
    finally:
        shutil.rmtree(target, ignore_errors=True)
    return clean


def compare(restored, current):
    if os.path.islink(current) or not os.path.exists(current):
        return "new" if not os.path.lexists(current) else "differs"
    return "same" if filecmp.cmp(restored, current, shallow=False) else "differs"


def copy_in(source, folder, rel):
    """Copy one file over its current one, through a temp name so a crash never leaves half a plan doc. The
    destination must stay inside the folder, whatever the snapshot holds."""
    dest = os.path.join(folder, rel)
    base = os.path.realpath(folder)
    parent = os.path.realpath(os.path.dirname(dest))
    if parent != base and not parent.startswith(base + os.sep):
        raise BackupError(f"{dest} leaves {folder}; refusing")
    if os.path.islink(dest):
        os.unlink(dest)
    os.makedirs(parent, exist_ok=True)
    temp = os.path.join(parent, f".{os.path.basename(dest)}.restore-tmp")
    shutil.copy2(source, temp)
    os.replace(temp, dest)


def notify_failure(message):
    """Best effort desktop notification: a headless run has no notifier and must still exit with its error."""
    try:
        subprocess.run(["notify-send", "-u", "critical", "plans backup failed", message], timeout=10)
    except (OSError, subprocess.SubprocessError):
        pass
