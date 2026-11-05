"""The one safe write path for plan docs, shared by the CLI and the board.

A writer keeps the Doc it read. `update` then locks the `.plans/` directory, reads the file again and refuses with
Conflict if another writer changed a key that this write also changes. Writes to different keys both land. The lock
sits on the directory and not on the doc, because `os.replace` swaps the doc's inode: a second writer would lock the
old inode and miss the first one.
"""

import contextlib
import datetime
import fcntl
import os
import tempfile

from . import parse

# The key every write sets, so it never counts as a conflict.
UPDATED = "updated"


class Vanished(Exception):
    def __init__(self, path):
        self.path = path
        super().__init__(f"{path}: deleted since it was read")


class Conflict(Exception):
    def __init__(self, path, keys):
        self.path = path
        self.keys = keys
        super().__init__(f"{path}: changed since it was read: {', '.join(keys)}")


def today():
    return datetime.date.today().isoformat()


def plans_dir_of(path):
    """The `.plans/` directory above a doc, or the doc's own directory outside that layout."""
    directory = os.path.dirname(os.path.abspath(path))
    probe = directory
    while probe != os.path.dirname(probe):
        if os.path.basename(probe) == ".plans":
            return probe
        probe = os.path.dirname(probe)
    return directory


@contextlib.contextmanager
def locked(directory):
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def update(doc, changes, date=None):
    """Apply `changes` (key -> value, parse.BODY for the body) to the doc on disk and return the new Doc. `doc` is the
    copy the caller read and based its changes on. Raises Conflict (file untouched) when a changed key differs on disk
    from `doc`, and parse.ParseError when the file on disk left the subset."""
    with locked(plans_dir_of(doc.path)):
        try:
            fresh = parse.load(doc.path)
        except FileNotFoundError:
            raise Vanished(doc.path) from None
        conflicting = [key for key in changes if key != UPDATED and fresh.value(key) != doc.value(key)]
        if conflicting:
            raise Conflict(doc.path, conflicting)
        updated = parse.Doc(doc.path, fresh.render({**changes, UPDATED: date or today()}))
        # A value with a line break renders as broken front matter, so the check runs on the result, for every caller.
        if updated.errors:
            raise parse.ParseError(doc.path, updated.errors)
        replace_atomically(doc.path, updated.text)
    return updated


def create(path, text, check_under_lock=None):
    """Write a new doc, or raise FileExistsError rather than overwrite one. The temp file is hard-linked into place.
    A link fails when the name exists, so even a writer outside the lock is never overwritten. `check_under_lock` runs
    while the lock is held and raises to refuse the write."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with locked(plans_dir_of(path)):
        if check_under_lock:
            check_under_lock()
        temp = write_temp(path, text)
        try:
            os.chmod(temp, 0o666 & ~current_umask())
            os.link(temp, path)
        finally:
            os.unlink(temp)
        fsync_dir(os.path.dirname(path))


def replace_atomically(path, text):
    temp = write_temp(path, text)
    try:
        os.chmod(temp, os.stat(path).st_mode & 0o7777)
        os.replace(temp, path)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temp)
        raise
    fsync_dir(os.path.dirname(path))


def write_temp(path, text):
    """A fsynced temp file beside `path`. Its name starts with a dot and ends in .tmp, so no `*.md` glob sees it."""
    directory = os.path.dirname(path)
    fd, temp = tempfile.mkstemp(dir=directory, prefix="." + os.path.basename(path) + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
    except BaseException:
        os.unlink(temp)
        raise
    return temp


def current_umask():
    # Python reads the umask only by setting it. Without this, the 0600 mode of mkstemp outlives the link.
    mask = os.umask(0)
    os.umask(mask)
    return mask


def fsync_dir(directory):
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
