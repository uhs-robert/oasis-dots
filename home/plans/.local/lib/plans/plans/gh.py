"""The `lint --gh` checks: a doc that outlived its PR, branch or issue on GitHub, asked through the `gh` CLI."""

import json
import re
import subprocess

from .validate import Finding, key_line

UNSET = (None, "", "none")
GONE = re.compile(r"HTTP 404|Not Found")
TIMEOUT_SECONDS = 30


class GhMissing(Exception):
    pass


def gh(repo, *args):
    try:
        return subprocess.run(["gh", *args], cwd=repo, capture_output=True, text=True, timeout=TIMEOUT_SECONDS)
    except FileNotFoundError as error:
        raise GhMissing("lint --gh needs the gh CLI") from error
    except subprocess.TimeoutExpired:
        # A failed call, so each check reports it as a gh-error finding.
        return subprocess.CompletedProcess(["gh", *args], 1, "", f"gh timed out after {TIMEOUT_SECONDS} s")


def number_or_url(value):
    """`12`, `#12` or a URL, as gh takes it."""
    text = str(value)
    return text[1:] if text.startswith("#") else text


def check(repo, docs):
    findings = []
    for doc in docs:
        findings += check_pr(repo, doc) + check_issue(repo, doc) + check_branch(repo, doc)
    return findings


def check_pr(repo, doc):
    pr = doc.keys.get("pr")
    if pr in UNSET:
        return []
    state, error = view_state(repo, "pr", pr)
    if error:
        return [Finding(doc.path, key_line(doc, "pr"), "gh-error", f"could not read pr {pr}: {error}")]
    if state in ("MERGED", "CLOSED"):
        return [Finding(doc.path, key_line(doc, "pr"), "gh-pr", f"pr {pr} is {state.lower()}; finish or delete the doc")]
    return []


def check_issue(repo, doc):
    issue = doc.keys.get("issue")
    if issue in UNSET:
        return []
    state, error = view_state(repo, "issue", issue)
    if error:
        return [Finding(doc.path, key_line(doc, "issue"), "gh-error", f"could not read issue {issue}: {error}")]
    if state == "CLOSED":
        return [Finding(doc.path, key_line(doc, "issue"), "gh-issue", f"issue {issue} is closed")]
    return []


def check_branch(repo, doc):
    branch = doc.keys.get("branch")
    if branch in UNSET:
        return []
    # git/ref (singular) matches only the exact ref. git/refs also matches a branch whose name starts with this one.
    result = gh(repo, "api", f"repos/{{owner}}/{{repo}}/git/ref/heads/{branch}", "--silent")
    if result.returncode == 0:
        return []
    if GONE.search(result.stderr):
        return [Finding(doc.path, key_line(doc, "branch"), "gh-branch", f"branch {branch} is not on the remote")]
    return [Finding(doc.path, key_line(doc, "branch"), "gh-error", f"could not read branch {branch}: {first_line(result.stderr)}")]


def view_state(repo, noun, value):
    result = gh(repo, noun, "view", number_or_url(value), "--json", "state")
    if result.returncode != 0:
        return None, first_line(result.stderr)
    try:
        return json.loads(result.stdout)["state"], None
    except (ValueError, KeyError):
        return None, f"unexpected gh output {result.stdout[:80]!r}"


def first_line(text):
    return (text.strip().splitlines() or ["gh failed"])[0]
