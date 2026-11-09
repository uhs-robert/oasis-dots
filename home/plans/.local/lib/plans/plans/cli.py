"""The `plans` commands: argument parsing and output only. The work is in the library modules."""

import argparse
import json
import os
import sys

from . import backup, gh, issues, liveness, parse, query, retire, roots, server, store, validate

OK, FINDINGS, USAGE, STALE = 0, 1, 2, 3
SESSION_ENV = "PLANS_SESSION"
# Claude Code sets both in every Bash call, subagents included. A human shell has neither.
SESSION_ID_ENV = "CLAUDE_CODE_SESSION_ID"
SESSION_PID_ENV = "CLAUDE_PID"
# `set` leaves these alone. The id and the project come from the doc's path, every write sets `updated` itself, and
# the owner's values come from the environment and its host from this machine.
UNSETTABLE = ("id", "project", store.UPDATED, *validate.OWNER_VALUE_KEYS)
NEW_RANK_GAP = 10


class Refused(Exception):
    """A request the command turns down, exit FINDINGS."""


class UsageError(Exception):
    """Bad input or a missing doc, exit USAGE."""


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        return args.run(args) or OK
    except store.Conflict as error:
        return fail(f"{error}; read it again and retry", STALE)
    except store.Vanished as error:
        return fail(str(error), FINDINGS)
    except (Refused, retire.Refused, backup.BackupError) as error:
        return fail(str(error), FINDINGS)
    except (UsageError, roots.NotInRepo, parse.ParseError, gh.GhMissing) as error:
        return fail(str(error), USAGE)


def fail(message, code):
    print(f"plans: {message}", file=sys.stderr)
    return code


def build_parser():
    parser = argparse.ArgumentParser(prog="plans", description="Read and edit the front matter of the plan docs under .plans/.")
    commands = parser.add_subparsers(dest="command", required=True)

    ls = commands.add_parser("ls", help="one line per doc: id, status, owner, rank, waiting_on")
    ls.add_argument("--owner")
    ls.add_argument("--project")
    ls.add_argument("--status", help="one status, or several separated by commas")
    add_scope_options(ls)
    ls.set_defaults(run=run_ls)

    backup_ = commands.add_parser("backup", help="back up every repo's .plans/ and .logs/ with restic")
    backup_.add_argument("--init", action="store_true", help="create the password file and the restic repo, once")
    backup_.set_defaults(run=run_backup)

    restore = commands.add_parser("restore", help="list snapshots, or restore one (a dry run without --apply)")
    restore.add_argument("snapshot", nargs="?", help="a snapshot id, or latest")
    restore.add_argument("--list", action="store_true", help="list the snapshots")
    restore.add_argument("--repo", help="only this repo: a path under the roots, or its folder name")
    restore.add_argument("--apply", action="store_true", help="copy the restored files into place")
    restore.set_defaults(run=run_restore)

    next_ = commands.add_parser("next", help="the ask lines, then the work line, for this session")
    add_session_option(next_)
    next_.add_argument("--skip", action="append", default=[], metavar="ID", help="leave this doc out (repeatable)")
    next_.add_argument("--all", action="store_true", help="a work line for every free doc, not only the first")
    next_.add_argument("--json", action="store_true")
    next_.set_defaults(run=run_next)

    waiting = commands.add_parser("waiting", help="docs with a non-empty waiting_on")
    add_scope_options(waiting)
    waiting.set_defaults(run=run_waiting)

    questions = commands.add_parser("questions", help="the unchecked items under Open questions")
    add_scope_options(questions)
    questions.set_defaults(run=run_questions)

    show = commands.add_parser("show", help="print a doc, or one section of it")
    show.add_argument("id")
    show.add_argument("--section")
    show.add_argument("--json", action="store_true")
    show.set_defaults(run=run_show)

    set_ = commands.add_parser("set", help="set front matter keys: plans set <id> key=value...")
    set_.add_argument("id")
    set_.add_argument("pairs", nargs="+", metavar="key=value")
    set_.set_defaults(run=run_set)

    note = commands.add_parser("note", help="append a bullet to a body section: plans note <id> --section NAME text")
    note.add_argument("id")
    note.add_argument("--section", required=True)
    note.add_argument("text")
    note.set_defaults(run=run_note)

    claim = commands.add_parser("claim", help="set owner_session to this session")
    claim.add_argument("id")
    add_session_option(claim)
    claim.add_argument("--force", action="store_true", help="take a doc another session owns")
    claim.set_defaults(run=run_claim)

    handoff = commands.add_parser("handoff", help="set owner_session on each doc to another session")
    handoff.add_argument("--to", required=True, dest="to_session")
    handoff.add_argument("ids", nargs="+")
    add_session_option(handoff)
    handoff.add_argument("--force", action="store_true", help="hand off docs another session owns")
    handoff.set_defaults(run=run_handoff)

    new = commands.add_parser("new", help="write .plans/<project>/<id>.md with every key and the five sections")
    new.add_argument("project")
    new.add_argument("id")
    new.add_argument("--kind", default="feature", choices=validate.KINDS)
    new.set_defaults(run=run_new)

    for name, help_text in (("close", "delete the doc and its log folder, and drop it from depends_on; run it after a merge"),
                            ("cancel", "close, plus the open PR (unmerged), the issue (not planned) and a clean worktree")):
        retire_command = commands.add_parser(name, help=help_text)
        retire_command.add_argument("id")
        add_session_option(retire_command)
        retire_command.add_argument("--force", action="store_true", help="act on a doc another session owns")
        retire_command.add_argument("--dry-run", action="store_true", help="print the changes without making them")
        retire_command.set_defaults(run=run_cancel if name == "cancel" else run_close)

    lint = commands.add_parser("lint", help="check every doc against the rules")
    lint.add_argument("--gh", action="store_true", help="also check PRs, branches and issues on GitHub")
    lint.add_argument("--all", action="store_true", help="every repo under ~/.config/plans/roots")
    lint.set_defaults(run=run_lint)

    reclaim = commands.add_parser("reclaim", help="for a SessionStart hook: take back this session's docs, from the hook input on stdin")
    reclaim.set_defaults(run=run_reclaim)

    serve = commands.add_parser("serve", help=f"a web board over every repo's docs, on {server.HOST}")
    serve.add_argument("--port", type=int, default=server.DEFAULT_PORT)
    serve.set_defaults(run=run_serve)
    return parser


def add_scope_options(parser):
    parser.add_argument("--all", action="store_true", help="every repo under ~/.config/plans/roots")
    parser.add_argument("--json", action="store_true")


def add_session_option(parser):
    parser.add_argument("--as", dest="session", help=f"this session's name, else ${SESSION_ENV}")


def repos(args):
    if getattr(args, "all", False):
        return [read_repo_freeing_dead_owners(root) for root in roots.all_repos()]
    return [read_repo_freeing_dead_owners(roots.main_checkout())]


def current_repo():
    return read_repo_freeing_dead_owners(roots.main_checkout())


def read_repo_freeing_dead_owners(root):
    repo = query.read_repo(root)
    docs, released = liveness.release_dead_owners(repo.docs)
    report_releases(released)
    return repo._replace(docs=docs)


def report_releases(released):
    for release in released:
        print(f"plans: {release.doc.path}: freed, owner {release.owner} is dead (pid {release.pid} runs no Claude)",
              file=sys.stderr)


def session_of(args, required):
    session = args.session or os.environ.get(SESSION_ENV) or None
    if session is None:
        if required:
            raise UsageError(f"name this session with --as <session> or ${SESSION_ENV}")
        return None
    if not validate.SESSION.fullmatch(session):
        raise UsageError(f"{session!r} is no session name (like dotfiles-56)")
    return session


def caller_of(args, required):
    """The session running the command, with its unique values from the environment, or None when it has no name."""
    name = session_of(args, required)
    return None if name is None else unnamed_caller()._replace(name=name)


def unnamed_caller():
    """The values of the session running the command, without a name. `set` takes no --as, so it has only these."""
    raw_pid = os.environ.get(SESSION_PID_ENV, "")
    pid = int(raw_pid) if parse.INTEGER.fullmatch(raw_pid) else None
    return validate.Caller(None, os.environ.get(SESSION_ID_ENV) or None, pid)


def warn_unlisted(repo, show_repo):
    """Say on stderr what the listing leaves out, so stdout stays one line per doc."""
    where = f"{repo.root}: " if show_repo else ""
    for layout in validate.old_layouts(repo.root):
        print(f"plans: {where}old layout {layout}", file=sys.stderr)
    if repo.old_kind:
        print(f"plans: {where}{len(repo.old_kind)} docs on the old kind {'/'.join(validate.OLD_KINDS)} scheme; {validate.MIGRATE}", file=sys.stderr)
    for finding in validate.conflict_findings(query.conflict_paths(repo.root)):
        print(f"plans: {finding.path}: {finding.rule}: {finding.message}", file=sys.stderr)
    for doc in repo.unreadable:
        reason = f"cannot be read: {doc.unread_cause}" if doc.unread_cause else "outside the front matter subset; run plans lint"
        print(f"plans: {doc.path}: {reason}", file=sys.stderr)


def doc_line(doc, repo=None):
    keys = doc.keys
    columns = [doc.id, keys.get("status", ""), keys.get("owner_session", ""), keys.get("rank", ""), keys.get("waiting_on", "")]
    if repo is not None:
        columns.insert(0, repo.name)
    return "\t".join(one_line(value) for value in columns)


def one_line(value):
    return " ".join(str(value).split()) if value is not None else ""


def doc_json(doc, repo=None):
    data = dict(doc.keys)
    for key, value in parse.DEFAULTS.items():
        data.setdefault(key, value)
    data["path"] = doc.path
    if repo is not None:
        data["repo"] = repo.name
    return data


def print_docs(args, pairs):
    """`pairs` holds (repo, doc) tuples. The repo column shows only with --all."""
    show_repo = getattr(args, "all", False)
    if args.json:
        print(json.dumps([doc_json(doc, repo if show_repo else None) for repo, doc in pairs], indent=2))
        return
    for repo, doc in pairs:
        print(doc_line(doc, repo if show_repo else None))


def run_ls(args):
    pairs = []
    for repo in repos(args):
        warn_unlisted(repo, args.all)
        pairs += [(repo, doc) for doc in query.listing(repo.docs, args.owner, args.project, args.status)]
    print_docs(args, pairs)


def run_waiting(args):
    pairs = []
    for repo in repos(args):
        pairs += [(repo, doc) for doc in query.waiting(repo.docs)]
    print_docs(args, pairs)


def run_questions(args):
    rows = []
    for repo in repos(args):
        rows += [(repo, question) for question in query.questions(repo.docs)]
    if args.json:
        print(json.dumps([{"id": q.doc.id, "question": q.text, "path": q.doc.path, **({"repo": repo.name} if args.all else {})}
                          for repo, q in rows], indent=2))
        return
    for repo, question in rows:
        columns = ([repo.name] if args.all else []) + [question.doc.id, question.text]
        print("\t".join(one_line(column) for column in columns))


def run_next(args):
    caller = caller_of(args, required=False)
    repo = current_repo()
    warn_unlisted(repo, False)
    steps = query.next_steps(repo.docs, caller, unreadable_ids={doc.id for doc in repo.unreadable + repo.old_kind},
                             skip=set(args.skip), all=args.all)
    issue_steps = issues.issue_steps(repo.root, repo.docs)
    if args.json:
        rows = [{"action": "ask", "id": f"#{step.number}", "issue": step.number, "detail": issue_detail(step),
                 "path": step.doc.path if step.doc else None} for step in issue_steps]
        rows += [{"action": step.action, "id": step.doc.id, "detail": step.detail, "path": step.doc.path} for step in steps]
        print(json.dumps(rows, indent=2))
        return
    for step in issue_steps:
        print("\t".join(["ask", f"#{step.number}", one_line(issue_detail(step))]))
    for step in steps:
        detail = f"blocked by {step.detail}" if step.action == "blocked" else step.detail
        print("\t".join([step.action, step.doc.id, one_line(detail)]))


def issue_detail(step):
    return f"rank: {step.title}" if step.reason == "rank" else f"closed: drop it from {step.doc.id}"


def load_doc(repo_root, doc_id):
    paths = query.find(repo_root, doc_id)
    if not paths:
        raise UsageError(f"no doc {doc_id!r} under {repo_root}/.plans")
    if len(paths) > 1:
        raise UsageError(f"id {doc_id!r} names several docs: {', '.join(paths)}")
    docs, released = liveness.release_dead_owners([parse.load(paths[0])])
    report_releases(released)
    return docs[0]


def run_show(args):
    doc = load_doc(roots.main_checkout(), args.id)
    if args.section is not None:
        sections = {title.lower(): content for title, (_, content) in doc.sections().items()}
        if args.section.lower() not in sections:
            raise UsageError(f"{args.id} has no section {args.section!r}")
        text = sections[args.section.lower()].strip("\n")
        if args.json:
            print(json.dumps({"id": doc.id, "section": args.section, "text": text}, indent=2))
        else:
            print(text)
        return
    if args.json:
        print(json.dumps({**doc_json(doc), "body": doc.body}, indent=2))
    else:
        sys.stdout.write(doc.text)


def run_set(args):
    caller = unnamed_caller()
    doc = load_doc(roots.main_checkout(), args.id)
    changes = dict(parse_pair(pair) for pair in args.pairs)
    if changes.get("owner_session", doc.keys.get("owner_session")) != doc.keys.get("owner_session"):
        owner_values = validate.cleared_owner_values()
    elif validate.shares_a_value(doc, caller) and not liveness.is_remote_owned(doc):
        # The skills write with a plain `set` and claim a doc once. Without this, a `/clear` and then a resume leave
        # both stored values stale, and the owner is locked out of its own doc. A doc owned on another host is
        # left out: its pid can match a session here by chance.
        owner_values = validate.owner_value_changes(doc, caller)
    else:
        owner_values = {}
    store.update(doc, {**changes, **owner_values})


def run_note(args):
    doc = load_doc(roots.main_checkout(), args.id)
    text = args.text.strip()
    if not text or "\n" in text or "\r" in text:
        raise UsageError("the note must be one non-empty line")
    sections = {title.lower(): (title, start, content) for title, (start, content) in doc.sections().items()}
    if args.section.lower() not in sections:
        raise UsageError(f"{args.id} has no section {args.section!r}")
    title, start, content = sections[args.section.lower()]
    if title == "Decisions":
        bullet = f"- {store.today()} {text}\n"
    elif title == "Open questions":
        # Lint and `plans questions` read only checklist items in this section.
        bullet = f"{text}\n" if validate.CHECKLIST_ITEM.fullmatch(text) else f"- [ ] {text}\n"
    else:
        bullet = f"- {text}\n"
    lines = doc.body.splitlines(keepends=True)
    first = start - doc.body_first_line
    old = lines[first:first + len(content.splitlines(keepends=True))]
    # Blank lines at the end of a section separate it from the next heading, so the bullet goes above them.
    gap = 0
    while gap < len(old) and old[len(old) - 1 - gap].strip() == "":
        gap += 1
    kept = old[:len(old) - gap] or ["\n"]
    if not kept[-1].endswith("\n"):
        kept[-1] += "\n"
    lines[first:first + len(old)] = kept + [bullet] + ["\n"] * gap
    store.update(doc, {parse.BODY: "".join(lines)})


def parse_pair(pair):
    key, equals, raw = pair.partition("=")
    if not equals:
        raise UsageError(f"{pair!r} is no key=value pair")
    if key in UNSETTABLE:
        raise UsageError(f"{key} cannot be set")
    if key not in parse.KEY_ORDER:
        raise UsageError(f"unknown key {key!r}; the keys are {', '.join(parse.KEY_ORDER)}")
    if "\n" in raw or "\r" in raw:
        raise UsageError(f"{key}: a value must be one line")
    return key, coerce(key, raw.strip())


def coerce(key, raw):
    """A command-line value as the front matter holds it, checked against the key's closed set or form."""
    if key in parse.LIST_KEYS:
        inner = raw[1:-1] if raw.startswith("[") and raw.endswith("]") else raw
        return [item.strip() for item in inner.split(",") if item.strip()]
    if key in parse.INTEGER_KEYS:
        if not parse.INTEGER.fullmatch(raw):
            raise UsageError(f"{key} must be a whole number, not {raw!r}")
        return int(raw)
    problem = validate.write_problem(key, raw)
    if problem:
        raise UsageError(problem)
    if key in ("issue", "pr") and parse.INTEGER.fullmatch(raw):
        return int(raw)
    return raw


def refuse_name_clash(doc, caller, verb):
    if validate.is_name_clash(doc, caller):
        stored_id, stored_pid = validate.stored_owner_values(doc)
        raise Refused(f"{doc.id} is owned by another session also named {caller.name} (owner_session_id {stored_id}, "
                      f"owner_session_pid {stored_pid}; this session is {caller.session_id}, pid {caller.pid}); "
                      f"{verb} it with --force")


def refuse_other_owner(doc, caller, force, verb):
    if force:
        return
    refuse_name_clash(doc, caller, verb)
    owner = validate.owner_of(doc)
    if owner not in (None, caller.name):
        raise Refused(f"{doc.id} is owned by {owner}; {verb} it with --force")
    # A session on another host can share this caller's name, and a shell caller matches by name alone.
    if owner is not None and liveness.is_remote_owned(doc):
        raise Refused(f"{doc.id} is owned by {owner} on {liveness.owner_host_of(doc)}; hand it off from there, or "
                      f"{verb} it with --force once that session is dead")


def claim_values(doc, caller):
    """The owner_session_id and owner_session_pid a claim writes. A caller with values writes its own, so a `/clear`
    (new id) or a resume (new pid) heals on the next claim. A caller without values (a human shell) keeps them under
    the same name and drops the old owner's under a new one or from another host."""
    if caller.has_values:
        return validate.owner_value_changes(doc, caller)
    if caller.name != doc.keys.get("owner_session") or liveness.is_remote_owned(doc):
        return validate.cleared_owner_values()
    return {}


def run_claim(args):
    caller = caller_of(args, required=True)
    doc = load_doc(roots.main_checkout(), args.id)
    refuse_other_owner(doc, caller, args.force, "claim")
    store.update(doc, {"owner_session": caller.name, **claim_values(doc, caller), validate.OWNER_HOST: liveness.this_host()})


def run_handoff(args):
    caller = caller_of(args, required=True)
    if not validate.is_session_or_none(args.to_session):
        raise UsageError(f"{args.to_session!r} is no session name (like dotfiles-56) or none")
    root = roots.main_checkout()
    # Every doc is checked before any is written, so a refusal leaves all of them as they were.
    docs = [load_doc(root, doc_id) for doc_id in args.ids]
    for doc in docs:
        refuse_other_owner(doc, caller, args.force, "hand")
    stale = []
    for doc in docs:
        try:
            # The sender does not know the receiver's values. The receiver's first claim writes them.
            store.update(doc, {"owner_session": args.to_session, **validate.cleared_owner_values()})
        except store.Conflict as error:
            print(f"plans: {error}", file=sys.stderr)
            stale.append(doc.id)
    if stale:
        return fail(f"not handed off: {', '.join(stale)}; read them again and retry", STALE)
    return OK


def run_close(args):
    return retire_doc(args, cancel=False)


def run_cancel(args):
    return retire_doc(args, cancel=True)


def retire_doc(args, cancel):
    verb = "cancel" if cancel else "close"
    # Without a session name the caller owns nothing, so a doc with an owner needs --force.
    caller = caller_of(args, required=False) or unnamed_caller()
    root = roots.main_checkout()
    doc = load_doc(root, args.id)
    refuse_other_owner(doc, caller, args.force, verb)
    plan = retire.plan(root, doc, cancel)
    if args.dry_run:
        for step in plan.steps:
            print(f"would: {step.text}")
        for note in plan.notes:
            print(f"keep: {note}")
        return OK
    outcome = retire.apply(doc, plan.steps)
    for state, text in outcome.lines:
        print(f"{state}: {text}")
    for note in plan.notes:
        print(f"keep: {note}")
    if outcome.failed:
        return fail(f"{verb} {doc.id} stopped; the doc is kept. Fix the failed step and run it again", FINDINGS)


def run_new(args):
    for name in (args.project, args.id):
        if not validate.NAME.fullmatch(name):
            raise UsageError(f"{name!r} must be lowercase letters, digits and dashes")
    if args.project == query.OLD_PROJECTS_DIR:
        raise UsageError(f"{query.OLD_PROJECTS_DIR!r} is the folder of the old layout; pick another project name")
    repo = current_repo()

    def refuse_taken_id():
        existing = query.find(repo.root, args.id)
        if existing:
            raise Refused(f"id {args.id!r} exists: {existing[0]}")

    # The early check gives the clear message. The one under the lock stops a second `plans new` of the same id in
    # another project.
    refuse_taken_id()
    path = os.path.join(repo.root, ".plans", args.project, args.id + ".md")
    try:
        store.create(path, new_doc_text(args.project, args.id, args.kind, next_rank(repo.docs)), refuse_taken_id)
    except FileExistsError:
        raise Refused(f"{path} exists") from None
    print(path)


def next_rank(docs):
    """NEW_RANK_GAP below the last-ranked doc, so a new doc starts at the bottom of the order."""
    ranks = [doc.keys["rank"] for doc in docs if isinstance(doc.keys.get("rank"), int)]
    return max(ranks, default=0) + NEW_RANK_GAP


def new_doc_text(project, doc_id, kind, rank):
    keys = {
        "id": doc_id, "project": project, "kind": kind, "status": "idea", "owner_session": validate.NO_SESSION,
        "rank": rank, "depends_on": [], "waiting_on": "", "issue": "none", "pr": "none", "branch": "none",
        "fix_rounds": 0, "updated": store.today(),
    }
    head = "".join(f"{key}: {parse.format_value(keys[key])}\n" for key in parse.KEY_ORDER)
    sections = "".join(f"\n## {title}\n" for title in parse.SECTIONS)
    return f"---\n{head}---\n# {doc_id}\n{sections}"


def run_lint(args):
    lines = []
    for repo in repos(args):
        lines += repo_lint_lines(repo, args)
    for line in lines:
        print(line)
    return FINDINGS if lines else OK


def repo_lint_lines(repo, args):
    def where(path):
        return path if args.all else os.path.relpath(path, repo.root)

    lines = [f"{where(repo.root)}: old-layout: {layout}" for layout in validate.old_layouts(repo.root)]
    findings = []
    for doc in repo.unreadable + repo.old_kind + repo.docs:
        findings += validate.lint_doc(doc)
    findings += validate.lint_repo(repo.docs + repo.old_kind + repo.unreadable)
    findings += validate.conflict_findings(query.conflict_paths(repo.root))
    if args.gh:
        findings += gh.check(repo.root, repo.docs)
    findings.sort(key=lambda finding: (finding.path, finding.line))
    return lines + [f"{where(f.path)}:{f.line}: {f.rule}: {f.message}" for f in findings]


def run_reclaim(args):
    """Silent and always OK: a hook's stdout reaches the model, and a failure would show at every session start."""
    try:
        hook_input = json.load(sys.stdin)
        session_id = hook_input.get("session_id") if isinstance(hook_input, dict) else None
        pid = liveness.own_claude_pid()
        if not isinstance(session_id, str) or not session_id or pid is None:
            return OK
        for root in reclaim_repos():
            try:
                liveness.take_back(query.read_repo(root).docs, session_id, pid, cleared=hook_input.get("source") == "clear")
            except Exception:  # noqa: BLE001, S112 - one unreadable repo must not stop the others
                continue
    except Exception:  # noqa: BLE001, S110 - see the docstring
        pass
    return OK


def reclaim_repos():
    """The repos under the roots, and the current checkout when the hook runs in a repo the roots miss."""
    repo_roots = roots.all_repos()
    try:
        current = os.path.realpath(roots.main_checkout())
    except (roots.NotInRepo, OSError):
        return repo_roots
    return repo_roots if current in repo_roots else [*repo_roots, current]


def run_serve(args):
    try:
        return server.serve(args.port)
    except OSError as error:
        raise UsageError(f"cannot serve on {server.HOST}:{args.port}: {error.strerror or error}") from None


def run_backup(args):
    try:
        if args.init:
            backup.init(print)
        else:
            backup.backup(print)
    except Exception as error:
        # A timer run has nobody watching the terminal. Any failure notifies, since systemd skips its own notice for
        # an exit-code failure.
        if not args.init:
            backup.notify_failure(str(error) or type(error).__name__)
        if isinstance(error, backup.BackupError):
            raise
        raise Refused(f"backup failed: {type(error).__name__}: {error}") from error


def run_restore(args):
    if args.list == bool(args.snapshot):
        raise UsageError("give --list, or a snapshot to restore")
    if args.list:
        backup.list_snapshots(print)
        return OK
    return OK if backup.restore(args.snapshot, args.repo, args.apply, print) else FINDINGS
