"""The lint rules for plan docs, and the detection of the layouts that came before them."""

import fnmatch
import os
import re
import subprocess

from typing import NamedTuple

from . import parse, roots

# The Conventional Commits type of the PR that ships the piece. Every doc is a plan doc, so `plan` is no kind.
KINDS = ("feature", "bug", "refactor", "docs", "chore", "research", "design")
# The tracker scheme these docs replace. A doc still on it gets one finding that asks for the migration, not one per rule.
OLD_KINDS = ("plan", "tracker", "handoff")
STATUSES = ("idea", "planned", "approved", "building", "review", "blocked", "parked", "done")
SESSION = re.compile(r"[a-z0-9][a-z0-9.]*(-[a-z0-9.]+)*-[a-z0-9]+")
NO_SESSION = "none"
# Two sessions can share a derived name, so a doc also records the owner's unique values. The id changes on `/clear`
# and the pid changes on `--resume`, so the owner matches when either one does. A doc may leave both out.
OWNER_SESSION_ID = "owner_session_id"
OWNER_SESSION_PID = "owner_session_pid"
SESSION_VALUE_KEYS = (OWNER_SESSION_ID, OWNER_SESSION_PID)
# The host the owner session runs on, written by `claim`. A pid means something only on its own host, so liveness
# judges a doc owned elsewhere as alive. It goes and comes with the session values: an owner change clears all three.
OWNER_HOST = "owner_host"
OWNER_VALUE_KEYS = (*SESSION_VALUE_KEYS, OWNER_HOST)
# A release of a dead owner keeps its name and id here, so the session can take the doc back once it resumes.
LAST_OWNER_SESSION = "last_owner_session"
LAST_OWNER_SESSION_ID = "last_owner_session_id"
LAST_OWNER_KEYS = (LAST_OWNER_SESSION, LAST_OWNER_SESSION_ID)
NAME = re.compile(r"[a-z0-9][a-z0-9-]*")
CHECKLIST_ITEM = re.compile(r"- \[[ xX]\] .*")
# The keys whose value a write must take from a closed set.
CLOSED_VALUES = {"kind": KINDS, "status": STATUSES}
MIGRATE = "migrate this repo"
# Syncthing renames the losing side of a clash to `<doc>.sync-conflict-<date>-<time>-<device>.md`.
CONFLICT_MARK = ".sync-conflict-"


class Finding(NamedTuple):
    path: str
    line: int
    rule: str
    message: str


def is_old_kind(doc):
    return doc.keys.get("kind") in OLD_KINDS


def lint_doc(doc):
    if doc.errors:
        return [Finding(doc.path, line, "front-matter", message) for line, message in doc.errors]
    if is_old_kind(doc):
        return [Finding(doc.path, key_line(doc, "kind"), "old-kind",
                        f"kind: {doc.keys['kind']} is the old {'/'.join(OLD_KINDS)} scheme; {MIGRATE}")]
    return key_findings(doc) + section_findings(doc)


def key_line(doc, key):
    index = doc.key_lines.get(key)
    return 1 if index is None else index + 2


def key_findings(doc):
    findings = []

    def flag(key, rule, message):
        findings.append(Finding(doc.path, key_line(doc, key), rule, message))

    keys = doc.keys
    for key in parse.KEY_ORDER:
        if key not in keys and key not in parse.DEFAULTS:
            flag(key, "missing-key", f"no {key} key")
    if "kind" in keys and keys["kind"] not in KINDS:
        flag("kind", "kind", f"kind {keys['kind']!r} is none of {', '.join(KINDS)}")
    if "status" in keys and keys["status"] not in STATUSES:
        flag("status", "status", f"status {keys['status']!r} is none of {', '.join(STATUSES)}")
    if "id" in keys and keys["id"] != doc.file_id:
        flag("id", "id", f"id {keys['id']!r} differs from the file name {doc.file_id!r}")
    for key in parse.INTEGER_KEYS:
        if key in keys and not isinstance(keys[key], int):
            flag(key, key.replace("_", "-"), f"{key} {keys[key]!r} is no integer")
    if "owner_session" in keys and not is_session_or_none(keys["owner_session"]):
        flag("owner_session", "owner-session", f"owner_session {keys['owner_session']!r} is no session name (like dotfiles-56) or none")
    if OWNER_SESSION_ID in keys and not isinstance(keys[OWNER_SESSION_ID], str):
        flag(OWNER_SESSION_ID, "owner-session-id", f'{OWNER_SESSION_ID} must be a string, "" when unknown')
    if OWNER_SESSION_PID in keys and keys[OWNER_SESSION_PID] != "" and not isinstance(keys[OWNER_SESSION_PID], int):
        flag(OWNER_SESSION_PID, "owner-session-pid", f'{OWNER_SESSION_PID} must be a whole number, "" when unknown')
    if OWNER_HOST in keys and not isinstance(keys[OWNER_HOST], str):
        flag(OWNER_HOST, "owner-host", f'{OWNER_HOST} must be a host name, "" when unset')
    if LAST_OWNER_SESSION in keys and keys[LAST_OWNER_SESSION] != "" and not is_session_or_none(keys[LAST_OWNER_SESSION]):
        flag(LAST_OWNER_SESSION, "last-owner-session", f'{LAST_OWNER_SESSION} {keys[LAST_OWNER_SESSION]!r} is no session name (like dotfiles-56), "" when unset')
    if LAST_OWNER_SESSION_ID in keys and not isinstance(keys[LAST_OWNER_SESSION_ID], str):
        flag(LAST_OWNER_SESSION_ID, "last-owner-session-id", f'{LAST_OWNER_SESSION_ID} must be a string, "" when unset')
    if "waiting_on" in keys and not isinstance(keys["waiting_on"], str):
        flag("waiting_on", "waiting-on", 'waiting_on must be a string, "" when the doc waits on nothing')
    for key in parse.LIST_KEYS:
        if key in keys and not isinstance(keys[key], list):
            flag(key, "list", f"{key} must be a list, `[a, b]` or `[]`")
    return findings


def owner_of(doc):
    """The session that owns the doc, or None. An empty or missing owner_session counts as none, and lint flags it."""
    owner = doc.keys.get("owner_session")
    return None if owner in (None, "", NO_SESSION) else owner


class Caller(NamedTuple):
    """Who runs a command: the session name, and the unique values Claude Code gives the session, None when unset."""
    name: str
    session_id: str = None
    pid: int = None

    @property
    def has_values(self):
        return self.session_id is not None or self.pid is not None


def stored_owner_values(doc):
    """The doc's owner_session_id and owner_session_pid, None for a missing or empty value."""
    return tuple(None if doc.keys.get(key) in (None, "") else doc.keys[key] for key in SESSION_VALUE_KEYS)


def is_name_clash(doc, caller):
    """True when the caller has the owner's name but is another session. It takes both stored values to differ: one
    empty value proves nothing, and a caller without values (a human shell) matches by name, as before the values."""
    if caller is None or not caller.has_values or owner_of(doc) != caller.name:
        return False
    stored_id, stored_pid = stored_owner_values(doc)
    return stored_id is not None and stored_pid is not None and stored_id != caller.session_id and stored_pid != caller.pid


def is_owned_by(doc, caller):
    return caller is not None and owner_of(doc) == caller.name and not is_name_clash(doc, caller)


def shares_a_value(doc, caller):
    """True when the caller's session id or pid equals the stored one: the same session, or its subagent."""
    stored = stored_owner_values(doc)
    return caller is not None and any(value is not None and value == own for value, own in zip(stored, (caller.session_id, caller.pid), strict=True))


def owner_value_changes(doc, caller):
    """The owner_session_id and owner_session_pid write for `caller`. A value the caller lacks goes in empty only when
    the doc already has its key, so a claim from before the keys adds no `""` line."""
    values = (caller.session_id or "", "" if caller.pid is None else caller.pid)
    return {key: value for key, value in zip(SESSION_VALUE_KEYS, values, strict=True) if value != "" or key in doc.keys}


def cleared_owner_values():
    """The write that drops the old owner's values and host on an owner change. Every key goes in even on a doc
    without it, so store.update sees a claim that lands meanwhile and refuses with Conflict instead of keeping its
    values."""
    return {key: "" for key in OWNER_VALUE_KEYS}


def is_session_or_none(value):
    return value == NO_SESSION or (isinstance(value, str) and SESSION.fullmatch(value) is not None)


def write_problem(key, value):
    """Why a write may not set `key` to `value`, or None. `plans set`, `plans claim` and the board all check with it."""
    if key in CLOSED_VALUES and value not in CLOSED_VALUES[key]:
        return f"{key} {value!r} is none of {', '.join(CLOSED_VALUES[key])}"
    if key == "owner_session" and not is_session_or_none(value):
        return f"{value!r} is no session name (like dotfiles-56) or none"
    return None


def section_findings(doc):
    findings = []
    sections = doc.sections()
    for title in parse.SECTIONS:
        if title not in sections:
            findings.append(Finding(doc.path, doc.body_first_line, "section", f"no `## {title}` section"))
    questions = sections.get("Open questions")
    if questions:
        first_line, text = questions
        for offset, line in enumerate(text.splitlines()):
            # An indented line continues the item above it.
            if line.strip() and not line.startswith((" ", "\t")) and not CHECKLIST_ITEM.fullmatch(line):
                findings.append(Finding(doc.path, first_line + offset, "open-questions", f"not a `- [ ]` item: {line!r}"))
    return findings


def lint_repo(docs):
    """The rules that span docs: unique ids, and a depends_on entry naming a doc that exists."""
    findings = []
    by_id = {}
    for doc in docs:
        by_id.setdefault(doc.id, []).append(doc)
    for doc_id, same in by_id.items():
        if len(same) > 1:
            for doc in same:
                others = ", ".join(other.path for other in same if other is not doc)
                findings.append(Finding(doc.path, key_line(doc, "id"), "duplicate-id", f"id {doc_id!r} is also used by {others}"))
    for doc in docs:
        depends_on = doc.keys.get("depends_on")
        if not isinstance(depends_on, list):
            continue
        for dependency in depends_on:
            if dependency not in by_id:
                # A merged piece deletes its doc, so this is either a typo or a finished piece to drop from the list.
                findings.append(Finding(doc.path, key_line(doc, "depends_on"), "depends-on",
                                        f"no doc {dependency!r}; drop it if that piece merged"))
    return findings


def conflict_findings(copies):
    """One finding per Syncthing conflict copy, given by path."""
    return [Finding(path, 1, "conflict", f"merge {os.path.basename(path).split(CONFLICT_MARK, 1)[0]}.md by hand, then delete the copy")
            for path in copies]


def old_layouts(repo):
    """One line per old layout in the repo: its name and the call to migrate."""
    found = []
    if os.path.isfile(os.path.join(repo, ".planning", "roadmap.md")):
        found.append(".planning/roadmap.md")
    if os.path.isfile(os.path.join(repo, ".plans", "roadmap.md")):
        found.append(".plans/roadmap.md")
    if os.path.isdir(os.path.join(repo, ".plans", "projects")):
        found.append(".plans/projects/")
    excluded = excluded_root_docs(repo)
    if excluded:
        found.append("root docs in info/exclude: " + ", ".join(excluded))
    return [f"{layout}; {MIGRATE}" for layout in found]


def excluded_root_docs(repo):
    """Untracked `.md` files at the repo root that a pattern in `<git-common-dir>/info/exclude` hides."""
    try:
        exclude = os.path.join(roots.git_common_dir(repo), "info", "exclude")
        with open(exclude, encoding="utf-8") as handle:
            patterns = [line.strip() for line in handle if line.strip() and not line.startswith("#")]
    except (roots.NotInRepo, OSError):
        return []
    root_docs = sorted(name for name in os.listdir(repo) if name.endswith(".md") and os.path.isfile(os.path.join(repo, name)))
    matched = [name for name in root_docs if any(fnmatch.fnmatchcase(name, pattern.lstrip("/")) for pattern in patterns)]
    if not matched:
        return []
    listed = subprocess.run(["git", "-C", repo, "ls-files", "-z", "--", *matched], capture_output=True, text=True).stdout
    tracked = listed.split("\0")
    return [name for name in matched if name not in tracked]
