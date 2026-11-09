"""Tell a live owner session from a dead one, free the docs a dead one holds, and let a resumed session take them back.

Liveness rests on the stored owner_session_pid alone. Claude Code's own session files would say more, but their format
is internal and undocumented. Every doubt counts as alive, because a wrong release hands live work to another session,
while a wrong keep only leaves a doc owned as it was before this check.
"""

import os
import socket

from typing import NamedTuple

from . import parse, store, validate

PROC_ROOT = "/proc"
CLAUDE_NAME = "claude"
# An npm install runs Claude Code as a script under one of these, so the comm and the first argument name the
# interpreter. The script then counts only when it is the `claude` launcher or lies inside the Claude Code package.
INTERPRETERS = ("node", "nodejs", "bun")
CLAUDE_PACKAGE = "/@anthropic-ai/claude-code/"
# Interpreter options that take the next argument as their value, and those that run code given on the command line.
VALUE_OPTIONS = ("-r", "--require", "--import", "--loader", "--experimental-loader")
EVAL_OPTIONS = ("-e", "--eval", "-p", "--print")
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
    """False only when the doc stores an owner_session_pid and that pid runs no Claude process here. A doc owned on
    another host is alive: its pid names a process there, which this host cannot see."""
    if is_remote_owned(doc):
        return True
    pid = doc.keys.get(validate.OWNER_SESSION_PID)
    if not isinstance(pid, int) or pid <= 0:
        return True
    return pid_runs_claude(pid)


def this_host():
    # Not the `hostname` binary: a --server install can lack it.
    return socket.gethostname()


def same_host(first, second):
    """Host names compare without case and without a trailing root dot, as DNS compares them. A short name and the
    full name of one host still differ, which is safe: every owner_host comes from this_host() on its own machine."""
    return first.rstrip(".").casefold() == second.rstrip(".").casefold()


def owner_host_of(doc):
    """The doc's owner_host, or None when unset. A non-string value that lint flags counts as a host, so a hand edit
    never turns a doc owned elsewhere into a local one."""
    host = doc.keys.get(validate.OWNER_HOST)
    return None if host in (None, "") else str(host)


def is_remote_owned(doc):
    """True when the doc names an owner_host other than this one. Only that host writes the doc."""
    host = owner_host_of(doc)
    return host is not None and not same_host(host, this_host())


def pid_runs_claude(pid):
    """Any doubt counts as Claude here, so a release never frees a doc on a guess."""
    return claude_process_state(pid) is not False


def claude_process_state(pid):
    """True when the pid runs Claude, False when it runs something else or nothing, None when /proc cannot tell. A
    missing /proc gives None, because every pid would look gone."""
    if not os.path.isdir(os.path.join(PROC_ROOT, "self")):
        return None
    try:
        with open(os.path.join(PROC_ROOT, str(pid), "comm"), "rb") as handle:
            comm = handle.read().decode("utf-8", "replace").strip()
        with open(os.path.join(PROC_ROOT, str(pid), "cmdline"), "rb") as handle:
            arguments = handle.read().decode("utf-8", "replace").split("\0")
    except (FileNotFoundError, ProcessLookupError):
        return False
    except OSError:
        return None
    return is_claude_command(comm, arguments) or runs_claude_install(pid)


def runs_claude_install(pid):
    """True when the pid's executable lies in a Claude install, such as `~/.local/share/claude/versions/<v>`. That
    covers a native Claude started under another name. Only a whole path component `claude` counts, and an
    unreadable exe (another user's process, a kernel thread) adds nothing."""
    try:
        executable = os.readlink(os.path.join(PROC_ROOT, str(pid), "exe"))
    except OSError:
        return False
    return CLAUDE_NAME in executable.split(os.sep)


def is_claude_command(comm, arguments):
    """A native Claude Code has `claude` as its comm or as the file name of its first argument. An interpreted one
    runs `claude` or a file of the Claude Code package as its script, the first argument after the interpreter's
    options."""
    program = os.path.basename(arguments[0]) if arguments else ""
    if CLAUDE_NAME in (comm, program):
        return True
    if program not in INTERPRETERS and comm not in INTERPRETERS:
        return False
    script = interpreted_script(arguments)
    return os.path.basename(script) == CLAUDE_NAME or CLAUDE_PACKAGE in script


def interpreted_script(arguments):
    """The script an interpreter runs, or "" when it runs code from the command line or no script at all."""
    rest = iter(arguments[1:])
    for argument in rest:
        if argument in EVAL_OPTIONS:
            return ""
        if argument in VALUE_OPTIONS:
            next(rest, None)
        elif argument and not argument.startswith("-"):
            return argument
    return ""


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
    """The pid of the Claude process this command runs under: the nearest ancestor that runs Claude, else $CLAUDE_PID
    when it runs Claude. The walk comes first because a nested `claude` inherits its parent's $CLAUDE_PID, and a hook
    gets no promise of the variable. None when no Claude process is found."""
    # A guess would claim docs, so both ask for a sure True, unlike pid_runs_claude.
    pid = os.getppid()
    for _ in range(MAX_ANCESTORS):
        if pid <= 1:
            break
        if claude_process_state(pid) is True:
            return pid
        pid = parent_of(pid)
    raw = environ.get("CLAUDE_PID", "")
    if parse.INTEGER.fullmatch(raw) and int(raw) > 0 and claude_process_state(int(raw)) is True:
        return int(raw)
    return None


def parent_of(pid):
    try:
        with open(os.path.join(PROC_ROOT, str(pid), "stat"), "rb") as handle:
            # The comm in parentheses can hold spaces, so the fields count from the last ")".
            return int(handle.read().rsplit(b")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def take_back(docs, session_id, pid, cleared=False):
    """Point this session's docs at its new pid after a resume or, when `cleared` (a `/clear`), at its new id, and
    claim back each free doc it lost while it was gone. Returns the docs it wrote. A doc another session holds is left
    alone, and a doc that vanishes or fails to write is skipped."""
    taken = []
    for doc in docs:
        try:
            written = take_back_one(doc, session_id, pid, cleared)
        except (store.Conflict, store.Vanished, NotThisSession, parse.ParseError, OSError, UnicodeDecodeError):
            continue
        if written is not None:
            taken.append(written)
    return taken


def take_back_one(doc, session_id, pid, cleared):
    # A release can land between the read and the lock, which turns an owned doc free. One retry on a fresh read
    # then claims the doc back instead of leaving it free until the next session start.
    for attempt in range(2):
        changes = take_back_changes(doc, session_id, pid, cleared)
        if changes is None:
            return None
        try:
            return store.update(doc, changes, check_under_lock=lambda fresh: refuse_changed_take_back(fresh, changes, session_id, pid, cleared))
        except store.Conflict:
            if attempt:
                raise
            doc = parse.load(doc.path)
    return None


def take_back_changes(doc, session_id, pid, cleared=False):
    # The pid and even the id can match by chance across hosts. A session never moves hosts, so a doc owned elsewhere
    # is never this session's.
    if is_remote_owned(doc):
        return None
    host = {validate.OWNER_HOST: this_host()}
    owner = validate.owner_of(doc)
    if owner is not None:
        stored_id, stored_pid = validate.stored_owner_values(doc)
        if stored_id == session_id and stored_pid != pid:
            return {validate.OWNER_SESSION_PID: pid, **host}
        # A live pid belongs to one process, so after a `/clear` a doc that stores this pid is this session's, now
        # under a new id. Only then: on startup or resume the pid can be a dead owner's, reused after a reboot.
        if cleared and stored_pid == pid and stored_id != session_id:
            return {validate.OWNER_SESSION_ID: session_id, **host}
        return None
    last_owner = doc.keys.get(validate.LAST_OWNER_SESSION)
    if doc.keys.get(validate.LAST_OWNER_SESSION_ID) != session_id or not validate.is_session_or_none(last_owner) \
            or last_owner == validate.NO_SESSION:
        return None
    return {"owner_session": last_owner, validate.OWNER_SESSION_ID: session_id, validate.OWNER_SESSION_PID: pid, **host}


def refuse_changed_take_back(fresh, changes, session_id, pid, cleared):
    """store.update compares only the keys a write changes, not the id that names this session, so the take-back is
    worked out again on the doc as it is on disk."""
    if take_back_changes(fresh, session_id, pid, cleared) != changes:
        raise NotThisSession(fresh.path)
