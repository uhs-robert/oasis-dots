#!/usr/bin/env python3
"""Scaffolds a `.plans/` doc with front matter that passes `lib/plan-frontmatter.yaml`.

  just plan-new <topic> <tracker|plan|handoff> [item]

The doc goes in the main checkout's `.plans/` (worktrees do not see it) and is never overwritten. `item` names a plan
(`<topic>-<item>-plan-draft.md`) or a piece's handoff (`<topic>-<item>-handoff-draft.md`). test_plan_new validates each scaffold against the schema,
so it cannot drift.
"""

import datetime
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KINDS = ("tracker", "plan", "handoff")
NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")
USAGE = f"usage: just plan-new <topic> <{'|'.join(KINDS)}> [item]  (item names a plan)"


def main_checkout(repo_dir):
    """The main checkout holding .plans/, from the git common dir, so a worktree resolves to it."""
    common = subprocess.run(
        ["git", "-C", repo_dir, "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return os.path.dirname(common)


def doc_path(root, topic, kind, item):
    folder = os.path.join(root, ".plans", topic)
    if kind == "tracker":
        return os.path.join(folder, f"{topic}.md")
    if kind == "handoff":
        # orchestrator-handoff names a piece's handoff <topic>-<item>-handoff-draft.md.
        name = f"{topic}-{item}-handoff-draft.md" if item else f"{topic}-handoff.md"
        return os.path.join(folder, name)
    return os.path.join(folder, f"{topic}-{item}-plan-draft.md")


def front_matter(kind, today):
    lines = [f"kind: {kind}", "status: active", "owner_session: none", f'updated: "{today}"']
    if kind != "tracker":
        lines.append("branch: none")
    lines.append("pr: none")
    return "---\n" + "\n".join(lines) + "\n---\n"


def scaffold(root, topic, kind, item=None, today=None):
    """Write the doc and return its path; raises ValueError with the fix on bad input or an existing file."""
    if kind not in KINDS:
        raise ValueError(f"unknown kind {kind!r}; use one of: {', '.join(KINDS)}")
    if not NAME.match(topic):
        raise ValueError(f"topic {topic!r} must be lowercase letters, digits and dashes")
    if kind == "plan" and not item:
        raise ValueError("a plan needs an item name: just plan-new <topic> plan <item>")
    if item and not NAME.match(item):
        raise ValueError(f"item {item!r} must be lowercase letters, digits and dashes")
    if kind == "tracker" and item:
        raise ValueError("a tracker takes no item")
    path = doc_path(root, topic, kind, item)
    if os.path.exists(path):
        raise ValueError(f"{path} exists; edit it instead of scaffolding over it")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    title = f"{topic}: {item} plan draft" if kind == "plan" else f"{topic}: {kind}"
    with open(path, "x") as handle:
        handle.write(front_matter(kind, today or datetime.date.today().isoformat()) + f"# {title}\n")
    return path


def main(argv):
    if not 2 <= len(argv) <= 3:
        print(USAGE, file=sys.stderr)
        return 2
    try:
        path = scaffold(main_checkout(REPO_DIR), *argv)
    except ValueError as error:
        print(f"plan-new: {error}", file=sys.stderr)
        return 1
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
