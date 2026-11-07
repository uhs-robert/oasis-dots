"""Tell a live owner session from a dead one, free the docs a dead one holds, and let a resumed session take them back.

Liveness rests on the stored owner_session_pid alone. Claude Code's own session files would say more, but their format
is internal and undocumented. Every doubt counts as alive, because a wrong release hands live work to another session,
while a wrong keep only leaves a doc owned as it was before this check.
"""

import os

from typing import NamedTuple

from . import parse, store, validate

PROC_ROOT = "/proc"
CLAUDE_NAME = "claude"
# A hook runs a few shells below Claude. The cap stops a walk that a broken stat file would keep going.
MAX_ANCESTORS = 16


class OwnerAlive(Exception):
    """Raised under the store lock to cancel a release, when the owner on disk turns out to be alive."""


class NotThisSession(Exception):
    """Raised under the store lock to cancel a take-back, when the doc on disk no longer names this session."""


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
    """Any doubt counts as Claude here, so a release never frees a doc on a guess."""
    return claude_process_state(pid) is not False


def claude_process_state(pid):
    """True when the pid runs Claude, False when it runs something else or nothing, None when /proc cannot tell. A
    Claude Code process has `claude` as its comm, or as the file name of its first argument. A missing /proc gives
    None, because every pid would look gone."""
    if not os.path.isdir(os.path.join(PROC_ROOT, "self")):
        return None
    try:
        with open(os.path.join(PROC_ROOT, str(pid), "comm"), "rb") as handle:
            comm = handle.read().decode("utf-8", "replace").strip()
        with open(os.path.join(PROC_ROOT, str(pid), "cmdline"), "rb") as handle:
            first_argument = handle.read().split(b"\0", 1)[0].decode("utf-8", "replace")
    except (FileNotFoundError, ProcessLookupError):
        return False
    except OSError:
        return None
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
            freed = store.update(doc, {"owner_session": validate.NO_SESSION, **validate.cleared_owner_values(),
                                       validate.LAST_OWNER_SESSION: owner,
                                       validate.LAST_OWNER_SESSION_ID: doc.keys.get(validate.OWNER_SESSION_ID) or ""},
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


def own_claude_pid(environ=os.environ):
    """The pid of the Claude process this command runs under: $CLAUDE_PID when it runs Claude, else the nearest
    ancestor that does. A hook gets no promise of $CLAUDE_PID, so the walk up the parents covers it. None when no
    Claude process is found."""
    raw = environ.get("CLAUDE_PID", "")
    # A guess would claim docs, so this asks for a sure True, unlike pid_runs_claude.
    if parse.INTEGER.fullmatch(raw) and int(raw) > 0 and claude_process_state(int(raw)) is True:
        return int(raw)
    pid = os.getppid()
    for _ in range(MAX_ANCESTORS):
        if pid <= 1:
            return None
        if claude_process_state(pid) is True:
            return pid
        pid = parent_of(pid)
    return None


def parent_of(pid):
    try:
        with open(os.path.join(PROC_ROOT, str(pid), "stat"), "rb") as handle:
            # The comm in parentheses can hold spaces, so the fields count from the last ")".
            return int(handle.read().rsplit(b")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def take_back(docs, session_id, pid):
    """Point this session's docs at its new pid after a resume, and claim back each free doc it lost while it was
    gone. Returns the docs it wrote. A doc another session holds is left alone, and a doc that changes, vanishes or
    fails to write is skipped."""
    taken = []
    for doc in docs:
        changes = take_back_changes(doc, session_id, pid)
        if changes is None:
            continue
        try:
            taken.append(store.update(doc, changes, check_under_lock=lambda fresh: refuse_changed_take_back(fresh, changes, session_id, pid)))
        except (store.Conflict, store.Vanished, NotThisSession, parse.ParseError, OSError, UnicodeDecodeError):
            continue
    return taken


def take_back_changes(doc, session_id, pid):
    owner = validate.owner_of(doc)
    if owner is not None:
        if doc.keys.get(validate.OWNER_SESSION_ID) != session_id or doc.keys.get(validate.OWNER_SESSION_PID) == pid:
            return None
        return {validate.OWNER_SESSION_PID: pid}
    last_owner = doc.keys.get(validate.LAST_OWNER_SESSION)
    if doc.keys.get(validate.LAST_OWNER_SESSION_ID) != session_id or not validate.is_session_or_none(last_owner) \
            or last_owner == validate.NO_SESSION:
        return None
    return {"owner_session": last_owner, validate.OWNER_SESSION_ID: session_id, validate.OWNER_SESSION_PID: pid}


def refuse_changed_take_back(fresh, changes, session_id, pid):
    """store.update compares only the keys a write changes, not the id that names this session, so the take-back is
    worked out again on the doc as it is on disk."""
    if take_back_changes(fresh, session_id, pid) != changes:
        raise NotThisSession(fresh.path)
