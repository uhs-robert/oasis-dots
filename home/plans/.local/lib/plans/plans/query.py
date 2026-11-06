"""The read side: a repo's docs, and the `ls`, `next`, `waiting` and `questions` queries over them."""

import glob
import os
import re

from typing import NamedTuple

from . import parse, validate

# `next` walks only these, in rank order.
ACTIVE_STATUSES = ("planned", "approved", "building")
FINISHED_STATUS = "done"
UNCHECKED_ITEM = re.compile(r"- \[ \] (.*)")
# Under `.plans/projects/` lies the old layout, never a project.
OLD_PROJECTS_DIR = "projects"


def doc_paths(repo):
    """`.plans/<project>/<id>.md` under the repo, by glob: there is no index file."""
    paths = glob.glob(os.path.join(glob.escape(repo), ".plans", "*", "*.md"))
    return sorted(path for path in paths if os.path.basename(os.path.dirname(path)) != OLD_PROJECTS_DIR)


class Repo(NamedTuple):
    root: str
    # Docs inside the subset and on the current scheme: the ones every query reads.
    docs: list
    # Docs outside the subset, and docs on an old kind.
    unreadable: list
    old_kind: list

    @property
    def name(self):
        return os.path.basename(self.root)


def read_repo(root):
    docs, unreadable, old_kind = [], [], []
    for path in doc_paths(root):
        try:
            doc = parse.read(path)
        except FileNotFoundError:
            # A doc that vanished mid-read is gone, not unreadable: the board reads the repo again.
            raise
        except (OSError, UnicodeDecodeError) as failure:
            # One bad file must not hide the rest of the repo.
            doc = parse.unreadable(path, failure)
        if doc.errors:
            unreadable.append(doc)
        elif validate.is_old_kind(doc):
            old_kind.append(doc)
        else:
            docs.append(doc)
    return Repo(root, docs, unreadable, old_kind)


def find(repo, doc_id):
    """Every doc in the repo whose file name is `doc_id`, readable or not, so a caller can tell missing from duplicate."""
    return [path for path in doc_paths(repo) if os.path.splitext(os.path.basename(path))[0] == doc_id]


def rank_order(doc):
    rank = doc.keys.get("rank")
    # A doc without an integer rank sorts last, and lint flags it.
    return (0, rank, doc.id) if isinstance(rank, int) else (1, 0, doc.id)


def matches(doc, owner=None, project=None, status=None):
    def wanted(key, values):
        return values is None or str(doc.keys.get(key)) in values.split(",")
    return wanted("owner_session", owner) and wanted("project", project) and wanted("status", status)


def listing(docs, owner=None, project=None, status=None):
    return sorted((doc for doc in docs if matches(doc, owner, project, status)), key=rank_order)


def waiting(docs):
    return [doc for doc in sorted(docs, key=rank_order) if doc.keys.get("waiting_on")]


class Question(NamedTuple):
    doc: object
    text: str


def questions(docs):
    """The unchecked `- [ ]` items under each doc's Open questions. An indented line continues the item above it, and
    joins its text after a space."""
    found = []
    for doc in sorted(docs, key=rank_order):
        section = doc.sections().get("Open questions")
        if not section:
            continue
        current = None
        for line in section[1].splitlines():
            item = UNCHECKED_ITEM.fullmatch(line)
            if item:
                current = [item.group(1)]
                found.append(Question(doc, current))
            elif current is not None and line.startswith((" ", "\t")) and line.strip():
                current.append(line.strip())
            else:
                current = None
    return [Question(question.doc, " ".join(question.text)) for question in found]


class Step(NamedTuple):
    # "ask" (the doc waits on the owner), "blocked" (an unfinished dependency) or "work" (a free doc: the first one, or every one with `all`).
    action: str
    doc: object
    detail: str


def next_steps(docs, session=None, unreadable_ids=(), skip=(), all=False):
    """What to do next, per the `next` rule: walk the active docs by rank and skip those another session owns. Each doc
    above the first free one gives an `ask` line when it waits on the owner, else a `blocked` line naming its first
    unfinished dependency. A dependency in `unreadable_ids` exists but cannot be read, so it blocks too. The first free
    doc gives the `work` line, and the walk ends there unless `all` is set, which gives a `work` line for every free doc.
    A dependent of a free doc stays blocked, because that doc is not done. A doc in `skip` gets no line, but it still
    counts as a dependency. Asks come first so a high-ranked doc that waits on a question keeps its place: the owner
    answers while lower-ranked work goes on."""
    by_id = {doc.id: doc for doc in docs}
    steps = []
    for doc in sorted(docs, key=rank_order):
        if doc.id in skip or doc.keys.get("status") not in ACTIVE_STATUSES or owned_by_other(doc, session):
            continue
        waiting_on = doc.keys.get("waiting_on")
        if waiting_on:
            steps.append(Step("ask", doc, str(waiting_on)))
            continue
        blocker = first_unfinished_dependency(doc, by_id, unreadable_ids)
        if blocker:
            steps.append(Step("blocked", doc, blocker))
            continue
        steps.append(Step("work", doc, str(doc.keys.get("status"))))
        if not all:
            break
    return steps


def owned_by_other(doc, session):
    owner = validate.owner_of(doc)
    return owner is not None and owner != session


def first_unfinished_dependency(doc, by_id, unreadable_ids=()):
    """A dependency is finished when its doc is done or gone, because a merged piece deletes its doc."""
    for dependency in doc.keys.get("depends_on") or []:
        if dependency in unreadable_ids:
            return f"{dependency} (unreadable)"
        target = by_id.get(dependency)
        if target is not None and target.keys.get("status") != FINISHED_STATUS:
            return dependency
    return None
