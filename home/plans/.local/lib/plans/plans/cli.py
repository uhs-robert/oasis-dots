"""The `plans` commands: argument parsing and output only. The work is in the library modules."""

import argparse
import json
import os
import sys

from . import gh, parse, query, roots, store, validate

OK, FINDINGS, USAGE, STALE = 0, 1, 2, 3
SESSION_ENV = "PLANS_SESSION"
# `set` leaves these alone. The id and the project come from the doc's path, and every write sets `updated` itself.
UNSETTABLE = ("id", "project", store.UPDATED)
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
    except Refused as error:
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

    lint = commands.add_parser("lint", help="check every doc against the rules")
    lint.add_argument("--gh", action="store_true", help="also check PRs, branches and issues on GitHub")
    lint.add_argument("--all", action="store_true", help="every repo under ~/.config/plans/roots")
    lint.set_defaults(run=run_lint)
    return parser


def add_scope_options(parser):
    parser.add_argument("--all", action="store_true", help="every repo under ~/.config/plans/roots")
    parser.add_argument("--json", action="store_true")


def add_session_option(parser):
    parser.add_argument("--as", dest="session", help=f"this session's name, else ${SESSION_ENV}")


def repos(args):
    if getattr(args, "all", False):
        return [query.read_repo(root) for root in roots.all_repos()]
    return [query.read_repo(roots.main_checkout())]


def current_repo():
    return query.read_repo(roots.main_checkout())


def session_of(args, required):
    session = args.session or os.environ.get(SESSION_ENV) or None
    if session is None:
        if required:
            raise UsageError(f"name this session with --as <session> or ${SESSION_ENV}")
        return None
    if not validate.SESSION.fullmatch(session):
        raise UsageError(f"{session!r} is no session name (like dotfiles-56)")
    return session


def warn_unlisted(repo, show_repo):
    """Say on stderr what the listing leaves out, so stdout stays one line per doc."""
    where = f"{repo.root}: " if show_repo else ""
    for layout in validate.old_layouts(repo.root):
        print(f"plans: {where}old layout {layout}", file=sys.stderr)
    if repo.old_kind:
        print(f"plans: {where}{len(repo.old_kind)} docs on the old kind {'/'.join(validate.OLD_KINDS)} scheme; {validate.MIGRATE}", file=sys.stderr)
    for doc in repo.unreadable:
        print(f"plans: {doc.path}: outside the front matter subset; run plans lint", file=sys.stderr)


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
    session = session_of(args, required=False)
    repo = current_repo()
    steps = query.next_steps(repo.docs, session, unreadable_ids={doc.id for doc in repo.unreadable + repo.old_kind},
                             skip=set(args.skip), all=args.all)
    if args.json:
        print(json.dumps([{"action": step.action, "id": step.doc.id, "detail": step.detail, "path": step.doc.path} for step in steps], indent=2))
        return
    for step in steps:
        detail = f"blocked by {step.detail}" if step.action == "blocked" else step.detail
        print("\t".join([step.action, step.doc.id, one_line(detail)]))


def load_doc(repo_root, doc_id):
    paths = query.find(repo_root, doc_id)
    if not paths:
        raise UsageError(f"no doc {doc_id!r} under {repo_root}/.plans")
    if len(paths) > 1:
        raise UsageError(f"id {doc_id!r} names several docs: {', '.join(paths)}")
    return parse.load(paths[0])


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
    doc = load_doc(roots.main_checkout(), args.id)
    changes = dict(parse_pair(pair) for pair in args.pairs)
    store.update(doc, changes)


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
    closed_sets = {"kind": validate.KINDS, "status": validate.STATUSES}
    if key in closed_sets and raw not in closed_sets[key]:
        raise UsageError(f"{key} {raw!r} is none of {', '.join(closed_sets[key])}")
    if key == "owner_session" and not validate.is_session_or_none(raw):
        raise UsageError(f"{raw!r} is no session name (like dotfiles-56) or none")
    if key in ("issue", "pr") and parse.INTEGER.fullmatch(raw):
        return int(raw)
    return raw


def refuse_other_owner(doc, session, force, verb):
    owner = validate.owner_of(doc)
    if not force and owner not in (None, session):
        raise Refused(f"{doc.id} is owned by {owner}; {verb} it with --force")


def run_claim(args):
    session = session_of(args, required=True)
    doc = load_doc(roots.main_checkout(), args.id)
    refuse_other_owner(doc, session, args.force, "claim")
    store.update(doc, {"owner_session": session})


def run_handoff(args):
    session = session_of(args, required=True)
    if not validate.is_session_or_none(args.to_session):
        raise UsageError(f"{args.to_session!r} is no session name (like dotfiles-56) or none")
    root = roots.main_checkout()
    # Every doc is checked before any is written, so a refusal leaves all of them as they were.
    docs = [load_doc(root, doc_id) for doc_id in args.ids]
    for doc in docs:
        refuse_other_owner(doc, session, args.force, "hand")
    stale = []
    for doc in docs:
        try:
            store.update(doc, {"owner_session": args.to_session})
        except store.Conflict as error:
            print(f"plans: {error}", file=sys.stderr)
            stale.append(doc.id)
    if stale:
        return fail(f"not handed off: {', '.join(stale)}; read them again and retry", STALE)
    return OK


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
    if args.gh:
        findings += gh.check(repo.root, repo.docs)
    findings.sort(key=lambda finding: (finding.path, finding.line))
    return lines + [f"{where(f.path)}:{f.line}: {f.rule}: {f.message}" for f in findings]
