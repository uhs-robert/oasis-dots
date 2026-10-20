#!/usr/bin/env python3
"""Fails a Quickshell README that links to or cites a file that is not there.

Moving a folder or a section leaves the READMEs pointing at the old place, and nothing else reads them. For every
`*.md` under the Quickshell tree:

  - `[text](path)` must name a file or folder that exists, relative to the README; `[text](file.md#anchor)` and
    `[text](#anchor)` must also name a heading of that file, by GitHub's anchor rules. URLs are not followed.
  - a backticked path whose first folder is one of QS_FOLDERS (resolved against the Quickshell tree) or REPO_FOLDERS
    (against the repository root) must exist, as a path in the Quickshell tree, from the README's own folder, from the
    repository root or inside a stow package under home/. A path with a glob, placeholder or variable is prose.

Existence is read from git's listing (tracked and untracked-but-not-ignored). A cited path that is missing but that git
ignores is a machine-local file (custom/sessions.lua, a generated asset folder) and passes.

  python3 -B lib/check/steps/readme_links.py
"""

import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qml_paths import QS_DIR, REPO_DIR, Finding, git_listing, make_ignored  # noqa: E402

# Spelled out, not read from the tree: a folder derived from the tree would stop being checked the day it is renamed away.
QS_FOLDERS = ("core", "theme", "ui", "services", "styles", "features", "custom", "assets", "scripts", "sounds")
REPO_FOLDERS = ("lib", "home", "system", "docs", "packages", "extras", "demo")

LINK = re.compile(r"(?<!!)\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+[^)]*)?\)")
CODE_SPAN = re.compile(r"`([^`\n]+)`")
PATH_TOKEN = re.compile(r"^[A-Za-z0-9_.][A-Za-z0-9_./-]*$")
HEADING = re.compile(r"^ {0,3}#{1,6}\s+(.*?)\s*#*\s*$")
FENCE = re.compile(r"^ {0,3}(```|~~~)")


def prose_lines(text):
    """(number, line) for each line outside a fenced code block."""
    fenced = None
    for number, line in enumerate(text.splitlines(), 1):
        fence = FENCE.match(line)
        if fence and fenced in (None, fence.group(1)):
            fenced = None if fenced else fence.group(1)
        elif not fenced:
            yield number, line


def anchor_of(heading, seen):
    """GitHub's anchor for a heading line's text; seen counts earlier equal anchors in the file."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading).replace("`", "")
    slug = re.sub(r"[^\w\- ]", "", text.lower()).replace(" ", "-")
    count = seen.get(slug, 0)
    seen[slug] = count + 1
    return slug if count == 0 else f"{slug}-{count}"


def anchors(text):
    seen, found = {}, set()
    for _, line in prose_lines(text):
        match = HEADING.match(line)
        if match:
            found.add(anchor_of(match.group(1), seen))
    return found


class Tree:
    """The repository's files as git lists them, with the folders they imply."""

    def __init__(self, files):
        self.files = files
        self.folders = {"."}
        for path in files:
            parts = path.split("/")[:-1]
            self.folders.update("/".join(parts[:i]) for i in range(1, len(parts) + 1))

    def has(self, path):
        path = os.path.normpath(path)
        return path in self.files or path in self.folders


def cited_path_exists(tree, ignored, qs_dir, readme_dir, token):
    path = token.rstrip("/")
    first = path.split("/")[0]
    if first in QS_FOLDERS:
        bases = (qs_dir, readme_dir, "")
    elif first in REPO_FOLDERS:
        bases = ("",)
    else:
        return True
    candidates = [os.path.normpath(os.path.join(base, path)) for base in (*bases, "home")]
    return any(tree.has(candidate) or ignored(candidate) for candidate in candidates)


def check_readme(repo, tree, ignored, qs_dir, readme):
    findings = []
    readme_dir = os.path.dirname(readme)
    with open(os.path.join(repo, readme), encoding="utf-8") as file:
        text = file.read()
    own_anchors = None
    for number, line in prose_lines(text):
        for match in LINK.finditer(line):
            target = match.group(2)
            if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", target):
                continue
            file_part, _, anchor = target.partition("#")
            linked = readme if not file_part else os.path.normpath(os.path.join(readme_dir, file_part))
            if file_part and not tree.has(linked):
                findings.append(Finding(readme, number, f"link {target} points at {linked}, which does not exist"))
                continue
            if anchor and linked.endswith(".md") and linked in tree.files:
                if linked == readme:
                    own_anchors = own_anchors if own_anchors is not None else anchors(text)
                    known = own_anchors
                else:
                    with open(os.path.join(repo, linked), encoding="utf-8") as other:
                        known = anchors(other.read())
                if anchor not in known:
                    findings.append(Finding(readme, number, f"link {target} names no heading of {linked}"))
        for span in CODE_SPAN.finditer(LINK.sub(r"\1", line)):
            token = span.group(1)
            if "/" not in token or not PATH_TOKEN.match(token):
                continue
            if not cited_path_exists(tree, ignored, qs_dir, readme_dir, token):
                findings.append(Finding(readme, number, f"`{token}` does not exist (relative to the Quickshell tree, this README, the repository root or home/)"))
    return findings


def run_checks(repo, qs_dir=QS_DIR):
    """Every finding for the checkout at repo, sorted."""
    tree = Tree(git_listing(repo, ["."]))
    readmes = sorted(path for path in tree.files if path.startswith(qs_dir + "/") and path.endswith(".md") and os.path.isfile(os.path.join(repo, path)))
    ignored = make_ignored(repo)
    findings = []
    for readme in readmes:
        findings.extend(check_readme(repo, tree, ignored, qs_dir, readme))
    return sorted(set(findings))


def main(argv):
    if argv:
        print("usage: lib/check/steps/readme_links.py", file=sys.stderr)
        return 2
    findings = run_checks(REPO_DIR)
    for finding in findings:
        print(f"{finding.path}:{finding.line}: {finding.message}", file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
