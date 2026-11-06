"""The issue check of `plans next`: open GitHub issues that no doc ranks, and ranked issues that are closed.

A doc ranks an issue when its `issue` key holds the number, or its Plan section names `#N`. Other sections hold history
("#94 merged as PR #194"), so they do not count. The GitHub answers are cached per repo, and any `gh` failure falls back
to the old cache or to no lines, so `next` never fails or hangs on the network."""

import json
import os
import re
import subprocess
import time

from typing import NamedTuple

from .query import rank_order

CACHE_VERSION = 1
CACHE_SECONDS = 600
# After a failed fetch, wait this long before the next try, so an offline `next` pays the gh timeout once.
RETRY_SECONDS = 60
GH_TIMEOUT_SECONDS = 5
OPEN_LIMIT = 1000
# GitHub caps the nodes of one GraphQL query, so the state lookups go in batches.
STATE_BATCH = 100
# The lookbehind keeps `owner/repo#12` and `PR#12` out, and the lookahead `#12x`: only a bare same-repo `#N` counts.
PLAN_NUMBER = re.compile(r"(?<![\w/#])#(\d+)(?![\w])")
ISSUE_URL = re.compile(r"https://github\.com/([^/\s]+/[^/\s]+)/issues/(\d+)/?")
REMOTE_URL = re.compile(r"(?:git@github\.com:|ssh://git@github\.com/|https://github\.com/)([^/\s]+/[^/\s]+?)(?:\.git)?/?")


class IssueStep(NamedTuple):
    number: int
    # "rank" (open, no doc ranks it) or "closed" (a doc ranks it, but it is closed).
    reason: str
    title: str
    doc: object


def ranked_numbers(docs, slug):
    """Issue number -> the first doc by rank that ranks it."""
    ranked = {}
    for doc in sorted(docs, key=rank_order):
        for number in doc_numbers(doc, slug):
            ranked.setdefault(number, doc)
    return ranked


def doc_numbers(doc, slug):
    numbers = []
    issue = doc.keys.get("issue")
    if isinstance(issue, int):
        numbers.append(issue)
    elif isinstance(issue, str):
        if re.fullmatch(r"#?\d+", issue):
            numbers.append(int(issue.lstrip("#")))
        else:
            url = ISSUE_URL.fullmatch(issue)
            if url and url.group(1).lower() == slug.lower():
                numbers.append(int(url.group(2)))
    plan = doc.sections().get("Plan")
    if plan:
        numbers += [int(match.group(1)) for match in PLAN_NUMBER.finditer(plan[1])]
    return numbers


def github_slug(repo):
    """`owner/name` from the origin remote, read locally so a repo without a GitHub origin costs no network call."""
    try:
        result = subprocess.run(["git", "-C", repo, "remote", "get-url", "origin"], capture_output=True, text=True,
                                timeout=GH_TIMEOUT_SECONDS)
    except (OSError, subprocess.TimeoutExpired):
        return None
    match = REMOTE_URL.fullmatch(result.stdout.strip()) if result.returncode == 0 else None
    return match.group(1) if match else None


def cache_path(slug):
    """One folder per owner: a hyphen can join both an owner and a repo name, so `a-b/c` and `a/b-c` must not share a file."""
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    owner, name = slug.split("/", 1)
    return os.path.join(base, "plans", owner, name + ".json")


def read_cache(path):
    """The cache, or None when it is missing or not in this version's shape. A bad cache must not stop `next`."""
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("version") != CACHE_VERSION:
        return None
    number = (int, float)
    if not isinstance(data.get("failed_at", 0), number) or isinstance(data.get("failed_at"), bool):
        return None
    if "open" in data:
        if not isinstance(data.get("fetched_at"), number) or isinstance(data.get("fetched_at"), bool):
            return None
        for key in ("open", "states"):
            table = data.get(key)
            if not isinstance(table, dict) or not all(k.isdigit() and isinstance(v, str) for k, v in table.items()):
                return None
    return data


def write_cache(path, data):
    """Owner-only, because the titles of a private repo's issues are private. Written then renamed, so a parallel `next`
    never reads half a file."""
    temp = f"{path}.{os.getpid()}.tmp"
    try:
        os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
        with os.fdopen(os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as handle:
            json.dump(data, handle)
        os.replace(temp, path)
    except OSError:
        try:
            os.unlink(temp)
        except OSError:
            pass


def gh(*args):
    """The stdout of a gh call, or None when gh is missing, slow or fails without output."""
    try:
        result = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=GH_TIMEOUT_SECONDS)
    except (OSError, subprocess.TimeoutExpired):
        return None
    # A GraphQL call that names a missing number exits 1 but still prints the data for the rest.
    if result.returncode != 0 and not result.stdout.strip():
        return None
    return result.stdout


def fetch_open(slug):
    out = gh("issue", "list", "--repo", slug, "--state", "open", "--limit", str(OPEN_LIMIT), "--json", "number,title")
    try:
        return {str(item["number"]): item["title"] for item in json.loads(out)}
    except (TypeError, ValueError, KeyError):
        return None


def fetch_states(slug, numbers):
    """Number -> CLOSED, OPEN, PR or MISSING. Issues and PRs share one number space, and a `#N` in a plan can be a PR."""
    owner, name = slug.split("/", 1)
    states = {}
    numbers = sorted(numbers)
    for start in range(0, len(numbers), STATE_BATCH):
        batch = numbers[start:start + STATE_BATCH]
        fields = " ".join(f"n{n}: issueOrPullRequest(number: {n}) {{ __typename ... on Issue {{ state }} }}" for n in batch)
        query = f"query($owner: String!, $name: String!) {{ repository(owner: $owner, name: $name) {{ {fields} }} }}"
        out = gh("api", "graphql", "-f", f"query={query}", "-f", f"owner={owner}", "-f", f"name={name}")
        try:
            found = json.loads(out)["data"]["repository"]
            for number in batch:
                node = found.get(f"n{number}")
                if node is None:
                    states[str(number)] = "MISSING"
                elif node.get("__typename") == "Issue":
                    states[str(number)] = node.get("state", "MISSING")
                else:
                    states[str(number)] = "PR"
        except (TypeError, ValueError, KeyError, AttributeError):
            return None
    return states


def github_view(slug, ranked, now=None):
    """The cached open issues and states, fetched again when the cache is old or lacks a ranked number. None when there is
    neither a fresh answer nor an old cache."""
    now = time.time() if now is None else now
    path = cache_path(slug)
    cached = read_cache(path)
    if cached is not None and now - cached.get("failed_at", 0) < RETRY_SECONDS:
        return cached if "open" in cached else None
    if cached is not None:
        known = set(cached.get("open", {})) | set(cached.get("states", {}))
        fresh = now - cached.get("fetched_at", 0) < CACHE_SECONDS
        if fresh and {str(n) for n in ranked} <= known:
            return cached
    open_issues = fetch_open(slug)
    if open_issues is not None:
        states = fetch_states(slug, {n for n in ranked if str(n) not in open_issues})
        if states is not None:
            fetched = {"version": CACHE_VERSION, "fetched_at": now, "open": open_issues, "states": states}
            write_cache(path, fetched)
            return fetched
    write_cache(path, {**(cached or {"version": CACHE_VERSION}), "failed_at": now})
    return cached


def issue_steps(repo, docs, now=None):
    """The `rank` lines by issue number, then the `closed` lines. Empty when the repo has no GitHub origin or GitHub
    cannot be reached and nothing is cached."""
    slug = github_slug(repo)
    if slug is None:
        return []
    ranked = ranked_numbers(docs, slug)
    view = github_view(slug, ranked, now)
    if view is None:
        return []
    open_issues, states = view.get("open", {}), view.get("states", {})
    steps = [IssueStep(int(n), "rank", title, None) for n, title in open_issues.items() if int(n) not in ranked]
    steps.sort(key=lambda step: step.number)
    steps += [IssueStep(n, "closed", "", doc) for n, doc in sorted(ranked.items()) if states.get(str(n)) == "CLOSED"]
    return steps
