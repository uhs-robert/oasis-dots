"""Tell a live owner session from a dead one, and free the docs a dead one holds.

Liveness rests on the stored owner_session_pid alone. Claude Code's own session files would say more, but their format
is internal and undocumented. Every doubt counts as alive, because a wrong release hands live work to another session,
while a wrong keep only leaves a doc owned as it was before this check.
"""

import os

from typing import NamedTuple

from . import parse, store, validate

PROC_ROOT = "/proc"
CLAUDE_NAME = "claude"


class OwnerAlive(Exception):
    """Raised under the store lock to cancel a release, when the owner on disk turns out to be alive."""


class Release(NamedTuple):
    doc: object
    owner: str
    pid: int


def owner_is_alive(doc):
    """False only when the doc stores an owner_session_pid and that pid runs no Claude process."""
    pid = doc.keys.get(validate.OWNER_SESSION_PID)
    if not isinstance(pid, int) or pid <= 0:
        return True
    return pid_runs_claude(pid)


def pid_runs_claude(pid):
    """A Claude Code process has `claude` as its comm, or as the file name of its first argument. A gone pid runs
    nothing. Any other error counts as Claude, and so does a missing /proc, where every pid would look gone."""
    if not os.path.isdir(os.path.join(PROC_ROOT, "self")):
        return True
    try:
        with open(os.path.join(PROC_ROOT, str(pid), "comm"), "rb") as handle:
            comm = handle.read().decode("utf-8", "replace").strip()
        with open(os.path.join(PROC_ROOT, str(pid), "cmdline"), "rb") as handle:
            first_argument = handle.read().split(b"\0", 1)[0].decode("utf-8", "replace")
    except (FileNotFoundError, ProcessLookupError):
        return False
    except OSError:
        return True
    return CLAUDE_NAME in (comm, os.path.basename(first_argument))


def release_dead_owners(docs):
    """Write owner_session none, with the id and pid cleared, into each doc whose owner is dead. Returns the docs with
    each freed one replaced by its new copy, and a Release per freed doc. A doc that changed, vanished or fails to
    write keeps its old copy and gets no Release, so a read that frees docs never fails on a race."""
    current, released = [], []
    for doc in docs:
        owner = validate.owner_of(doc)
        if owner is None or owner_is_alive(doc):
            current.append(doc)
            continue
        try:
            # store.update refuses with Conflict when the name, id or pid changed on disk, as on a re-claim.
            freed = store.update(doc, {"owner_session": validate.NO_SESSION, **validate.cleared_owner_values()},
                                 check_under_lock=refuse_live_owner)
        except (store.Conflict, store.Vanished, OwnerAlive, parse.ParseError, OSError, UnicodeDecodeError):
            current.append(doc)
            continue
        current.append(freed)
        released.append(Release(freed, owner, doc.keys[validate.OWNER_SESSION_PID]))
    return current, released


def refuse_live_owner(fresh):
    if owner_is_alive(fresh):
        raise OwnerAlive(fresh.path)
