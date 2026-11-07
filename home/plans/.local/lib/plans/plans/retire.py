"""`plans close` and `plans cancel`: take a doc off the board, and for cancel also let go of its GitHub and git side.

`plan` lists the steps without changing anything, which is the `--dry-run` output and the board's prompt. `apply` runs
them in a fixed order: PR, issue, worktree, then the local files. The doc file goes last, so a failed step leaves the
doc in place and the owner can fix the cause and run the command again.
"""

import os
import re
import shutil
import subprocess
from typing import Callable, NamedTuple

from . import gh, parse, query, store, validate

PR_COMMENT = "Closed unmerged: the plan for this PR was cancelled. The branch stays, so the PR can be reopened."
# A number, `#number`, or a GitHub PR or issue URL. Anything else is refused, so a value can never pass for a gh flag.
REFERENCE = re.compile(r"#?(\d+)|https://github\.com/([\w.-]+/[\w.-]+)/(?:pull|issues)/(\d+)")
GITHUB_REMOTE_PREFIXES = ("git@github.com:", "https://github.com/", "ssh://git@github.com/")
BRANCH = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]*")
UNSET = gh.UNSET
# What the caller read and the plan depends on. The doc must still hold these when the first step runs and at the delete.
# The owner's id and pid are in it, so a same-named session that claims meanwhile stops the delete.
GUARDED_KEYS = ("status", "owner_session", "pr", "issue", "branch", *validate.OWNER_VALUE_KEYS)
DEPENDS_RETRIES = 3
GIT_TIMEOUT_SECONDS = 60
# Git sets these in hooks and they point every git call at that other repo.
INHERITED_GIT_VARIABLES = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
                           "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_PREFIX")


class Refused(Exception):
    """A doc or value the commands will not act on. Nothing has changed."""


class StepFailed(Exception):
    pass


class Step(NamedTuple):
    text: str
    # Returns None when it changed something, or the reason it had nothing to do. Raises StepFailed or an OSError.
    run: Callable


class Plan(NamedTuple):
    steps: list
    # What the command leaves alone on purpose, so the preview says so.
    notes: list


class Outcome(NamedTuple):
    # (state, text) pairs: done, skipped, failed or not run.
    lines: list
    failed: bool


def plan(root, doc, cancel):
    """The steps to close `doc` (or cancel it) in the repo at `root`, in the order `apply` runs them."""
    project = names_of(root, doc)
    others = [other for other in query.read_repo(root).docs if other.path != doc.path]
    steps, notes = [], []
    if cancel:
        steps += github_steps(root, doc, notes)
        steps += worktree_steps(root, doc, notes)
    steps += local_steps(root, doc, project, others)
    return Plan(steps, notes)


def names_of(root, doc):
    """The project of the doc, after checking that the id and project are plain names and that the path is exactly
    `.plans/<project>/<id>.md`. The delete steps build their paths from these names, so nothing can point elsewhere."""
    project = os.path.basename(os.path.dirname(doc.path))
    if not (validate.NAME.fullmatch(doc.id) and validate.NAME.fullmatch(project)):
        raise Refused(f"{doc.path}: the id and the project must be lowercase letters, digits and dashes")
    if os.path.abspath(doc.path) != os.path.join(os.path.abspath(root), ".plans", project, doc.id + ".md"):
        raise Refused(f"{doc.path} is not .plans/{project}/{doc.id}.md under {root}")
    if not stays_inside(root, ".plans", project):
        raise Refused(f".plans/{project} leads outside {root}")
    return project


def stays_inside(root, top, project):
    """True when `<root>/<top>/<project>` is a real folder under `<root>/<top>`, not a link that leads elsewhere. A
    delete through such a link would remove files outside the repo."""
    return os.path.realpath(os.path.join(root, top, project)) == os.path.join(os.path.realpath(os.path.join(root, top)), project)


def reference(doc, key):
    """The PR or issue the doc names, as text for gh, or None when it names none."""
    value = doc.keys.get(key)
    if value in UNSET:
        return None
    text = str(value)
    found = REFERENCE.fullmatch(text)
    if not found:
        raise Refused(f"{doc.id}: {key} {text!r} is no number or GitHub URL")
    return found.group(1) or text


def identity_of(reference_text, current_repo):
    """(repo slug, number) of a PR or issue reference. A bare number belongs to `current_repo`, None when unknown."""
    found = REFERENCE.fullmatch(reference_text)
    if found.group(1):
        return current_repo, found.group(1)
    return found.group(2).lower(), found.group(3)


def current_repo_slug(root):
    """owner/name of the origin remote, lowercase, or None off GitHub."""
    remote = subprocess.run(["git", "-C", root, "remote", "get-url", "origin"], capture_output=True, text=True,
                            env=git_environment()).stdout.strip()
    for prefix in GITHUB_REMOTE_PREFIXES:
        if remote.startswith(prefix):
            return remote[len(prefix):].removesuffix("/").removesuffix(".git").lower()
    return None


def github_steps(root, doc, notes):
    steps = []
    pr = reference(doc, "pr")
    if pr:
        steps.append(Step(f"close PR {pr} unmerged, with a comment (if it is still open)", lambda: close_pr(root, pr)))
    issue = reference(doc, "issue")
    if issue:
        sharing = sharers(root, doc, issue)
        if sharing:
            notes.append(f"keep issue {issue} open: {', '.join(sharing)} also names it")
        else:
            steps.append(Step(f"close issue {issue} as not planned (if it is still open)", lambda: close_issue(root, doc, issue)))
    return steps


def sharers(root, doc, issue):
    """The ids of the other docs that name `doc`'s issue, read from disk now."""
    current_repo = current_repo_slug(root)
    mine = identity_of(issue, current_repo)
    return [other.id for other in query.read_repo(root).docs if other.path != doc.path and shares_issue(other, mine, current_repo)]


def shares_issue(other, mine, current_repo):
    """True when `other` names the same issue. A repo that is unknown on either side counts as the same, so the issue
    stays open rather than closing under a doc that may need it."""
    value = other.keys.get("issue")
    if value in UNSET or not REFERENCE.fullmatch(str(value)):
        return False
    slug, number = identity_of(str(value), current_repo)
    return number == mine[1] and (slug is None or mine[0] is None or slug == mine[0])


def close_pr(root, pr):
    state, error = gh.view_state(root, "pr", pr)
    if error:
        raise StepFailed(f"could not read PR {pr}: {error}")
    if state != "OPEN":
        return f"PR {pr} is {state.lower()}"
    result = gh.gh(root, "pr", "close", pr, "--comment", PR_COMMENT)
    if result.returncode != 0:
        raise StepFailed(f"gh pr close {pr} failed: {gh.first_line(result.stderr)}")


def close_issue(root, doc, issue):
    # The plan checked this before the slow PR step, and a sibling may have named the issue since.
    sharing = sharers(root, doc, issue)
    if sharing:
        return f"{', '.join(sharing)} now also names it"
    state, error = gh.view_state(root, "issue", issue)
    if error:
        raise StepFailed(f"could not read issue {issue}: {error}")
    if state != "OPEN":
        return f"issue {issue} is {state.lower()}"
    result = gh.gh(root, "issue", "close", issue, "--reason", "not planned")
    if result.returncode != 0:
        raise StepFailed(f"gh issue close {issue} failed: {gh.first_line(result.stderr)}")


def worktree_steps(root, doc, notes):
    branch = doc.keys.get("branch")
    if branch in UNSET:
        return []
    if not BRANCH.fullmatch(str(branch)) or ".." in str(branch):
        raise Refused(f"{doc.id}: branch {branch!r} is no branch name")
    notes.append(f"keep branch {branch}, local and remote, so the PR can be reopened")
    return [Step(f"remove the worktree on branch {branch} (only if it has no uncommitted changes; its ignored files go with it)",
                 lambda: remove_worktree(root, str(branch)))]


def git_environment():
    return {name: value for name, value in os.environ.items() if name not in INHERITED_GIT_VARIABLES}


def git(root, *args):
    try:
        return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, timeout=GIT_TIMEOUT_SECONDS,
                              env=git_environment())
    except subprocess.TimeoutExpired:
        raise StepFailed(f"git {' '.join(args)} timed out") from None


def worktree_of(root, branch):
    result = git(root, "worktree", "list", "--porcelain")
    if result.returncode != 0:
        raise StepFailed(f"git worktree list failed: {gh.first_line(result.stderr)}")
    path = None
    for line in result.stdout.splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):]
        elif line == f"branch refs/heads/{branch}":
            return path
    return None


def remove_worktree(root, branch):
    path = worktree_of(root, branch)
    if path is None:
        return f"no worktree has branch {branch} checked out"
    if os.path.realpath(path) == os.path.realpath(root):
        return f"branch {branch} is checked out in the main checkout, which stays"
    status = git(path, "status", "--porcelain", "--untracked-files=all")
    if status.returncode != 0:
        raise StepFailed(f"git status in {path} failed: {gh.first_line(status.stderr)}")
    if status.stdout.strip():
        return f"{path} has uncommitted changes and stays"
    # No --force: git refuses a locked worktree, and that stops the cancel.
    result = git(root, "worktree", "remove", path)
    if result.returncode != 0:
        raise StepFailed(f"git worktree remove {path} failed: {gh.first_line(result.stderr)}")


def local_steps(root, doc, project, others):
    """The dependents' edits, the log folder, then the doc itself last."""
    listing = [other.id for other in others if doc.id in depends_of(other)]
    # The step reads the dependents again when it runs: the PR and worktree steps before it are slow, and a doc may
    # have gained the dependency meanwhile.
    text = f"drop {doc.id} from depends_on of {', '.join(listing)}" if listing else f"drop {doc.id} from every depends_on (none lists it now)"
    steps = [Step(text, lambda: drop_dependencies(root, doc))]
    logs = os.path.join(root, ".logs", project, doc.id)
    if not stays_inside(root, ".logs", project):
        raise Refused(f".logs/{project} leads outside {root}")
    if os.path.lexists(logs):
        steps.append(Step(f"delete .logs/{project}/{doc.id}/", lambda: delete_logs(root, project, logs, doc)))
    steps.append(Step(f"delete .plans/{project}/{doc.id}.md", lambda: delete_doc(root, project, doc)))
    return steps


def depends_of(doc):
    value = doc.keys.get("depends_on")
    return value if isinstance(value, list) else []


def drop_dependencies(root, doc):
    store.check_unchanged(doc, GUARDED_KEYS)
    dependents = [other for other in query.read_repo(root).docs if other.path != doc.path and doc.id in depends_of(other)]
    for other in dependents:
        drop_dependency(doc.id, other)
    if not dependents:
        return f"no doc lists {doc.id}"


def drop_dependency(doc_id, other):
    for _ in range(DEPENDS_RETRIES):
        try:
            current = parse.load(other.path)
            remaining = [item for item in depends_of(current) if item != doc_id]
            if len(remaining) == len(depends_of(current)):
                return f"{other.id} no longer lists {doc_id}"
            store.update(current, {"depends_on": remaining})
            return None
        except FileNotFoundError:
            return f"{other.id} was deleted meanwhile"
        except store.Vanished:
            return f"{other.id} was deleted meanwhile"
        except store.Conflict:
            continue
    raise StepFailed(f"{other.id} kept changing depends_on; run the command again")


def delete_logs(root, project, logs, doc):
    # The doc delete rechecks under the lock, but the logs would already be gone by then.
    store.check_unchanged(doc, GUARDED_KEYS)
    if not stays_inside(root, ".logs", project):
        raise StepFailed(f".logs/{project} leads outside {root}")
    if os.path.islink(logs):
        os.unlink(logs)
    elif os.path.isdir(logs):
        shutil.rmtree(logs)
    else:
        return "no log folder"


def delete_doc(root, project, doc):
    if not stays_inside(root, ".plans", project):
        raise StepFailed(f".plans/{project} leads outside {root}")
    try:
        store.delete(doc, GUARDED_KEYS)
    except store.Vanished:
        return "the doc was already deleted"


def apply(doc, steps):
    """Run `steps` in order and stop at the first failure. Raises Conflict or Vanished, before any step, when the doc
    changed since it was read. Never raises for a failed step: the failure is in the outcome, with the steps not run."""
    store.check_unchanged(doc, GUARDED_KEYS)
    lines, failed = [], False
    for step in steps:
        if failed:
            lines.append(("not run", step.text))
            continue
        try:
            reason = step.run()
        except (StepFailed, gh.GhMissing, OSError, store.Vanished, store.Conflict, parse.ParseError, UnicodeDecodeError) as error:
            lines.append(("failed", f"{step.text}: {error}"))
            failed = True
            continue
        lines.append(("skipped", f"{step.text}: {reason}") if reason else ("done", step.text))
    return Outcome(lines, failed)
