#!/usr/bin/env python3
"""Fails a Quickshell import, or a URL load with a literal head, that runs to a higher layer than its file's.

Layers are the top folders of the Quickshell tree, ranked by LAYERS: a file may reach its own rank and below. The
imports are read with qml_imports.imports and the URL loads with qml_paths.call_sites, so a path this step cannot
see (a table-driven load, a URL whose head is not a literal) is the same blind spot qml-paths documents. Edges between
two features, or two styles, are not checked: the Target tree allows them only through a singleton, which needs types.

lib/check/qml-layers.allow lists the upward edges that exist today, one per line:

  <file> -> <target>  # <reason> (<item that removes it, or "permanent">)

where <target> is `qs.<dotted path>` for `import qs`, a tree path for a relative import, and `url:<tree path of the
literal head>` for a URL load. Line numbers are left out so edits above an edge do not break its entry. An entry that
no longer matches an edge fails as stale: the fix that removed the edge deletes the line, so the list only shrinks.

  python3 -B lib/check/steps/qml_layers.py
"""

import os
import posixpath
import re
import sys
from typing import NamedTuple

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qml_imports import imports  # noqa: E402
from qml_paths import QS_DIR, REPO_DIR, SOURCE_SUFFIXES, Finding, call_sites, git_listing, norm  # noqa: E402

ALLOW_PATH = "lib/check/qml-layers.allow"

# The Target tree in quickshell-refactor.md. services/ and components/ are leftovers that dissolve in 5.9; services
# keeps rank 3 as a placeholder until its two files have a destination.
LAYERS = {"core": 0, "theme": 1, "ui": 2, "components": 2, "services": 3, "styles": 4, "features": 5}
UNRANKED = {"scripts", "assets", "sounds", "custom"}

ENTRY = re.compile(r"^(\S+) -> (\S+)\s+#\s*(\S.*)$")


class Edge(NamedTuple):
    file: str
    target: str  # as the allowlist spells it
    line: int
    layer: str  # the target's top folder
    text: str  # how the message names the use


def edges_of(repo, qs_dir, rel):
    """Every edge from one file to a path in the tree, as Edges; the target's layer is its top folder."""
    here = posixpath.dirname(rel)
    path = os.path.join(repo, qs_dir, rel)
    found = []
    for kind, target, line in imports(path):
        if kind == "qs":
            found.append((("qs." + target.replace("/", ".")).rstrip("."), target, line, f"import qs.{target.replace('/', '.')}"))
        else:
            resolved = norm(posixpath.join(here, target))
            found.append((resolved, resolved, line, f'import "{target}"'))
    for site in call_sites(path, rel.endswith(".qml")):
        if not site.terms or site.terms[0][0] != "lit":
            continue
        head = site.terms[0][1]
        resolved = norm(head.lstrip("/") if site.from_root else posixpath.join(here, head))
        found.append((f"url:{resolved}", resolved, site.line, f'load of "{head}"'))
    return [
        Edge(rel, spelling, line, resolved.split("/")[0], text)
        for spelling, resolved, line, text in found
        if resolved and not resolved.startswith("..")
    ]


def is_upward(file_layer, edge):
    return edge.layer in LAYERS and LAYERS[edge.layer] > LAYERS[file_layer]


def read_allowlist(repo, allow_path):
    """The entries as {(file, target): line}, and the findings for malformed and duplicate lines."""
    entries, findings = {}, []
    try:
        with open(os.path.join(repo, allow_path), encoding="utf-8") as file:
            lines = file.read().splitlines()
    except OSError:
        return entries, findings
    for number, line in enumerate(lines, 1):
        if not line.strip() or line.startswith("#"):
            continue
        match = ENTRY.match(line)
        if not match:
            findings.append(Finding(allow_path, number, 'malformed; expected "<file> -> <target>  # <reason> (<item>)"'))
        elif (match.group(1), match.group(2)) in entries:
            findings.append(Finding(allow_path, number, f"duplicate entry for {match.group(1)} -> {match.group(2)}"))
        else:
            entries[(match.group(1), match.group(2))] = number
    return entries, findings


def run_checks(repo, qs_dir=QS_DIR, allow_path=ALLOW_PATH):
    """Every finding for the checkout at repo, sorted."""
    prefix = qs_dir + "/"
    files = sorted(path.removeprefix(prefix) for path in git_listing(repo, [qs_dir]) if path.startswith(prefix))
    allowed, findings = read_allowlist(repo, allow_path)
    seen, upward_seen = set(), set()
    reported_dirs = set()
    for rel in files:
        top = rel.split("/")[0]
        if "/" not in rel or not rel.endswith(SOURCE_SUFFIXES) or top in UNRANKED:
            continue
        if top not in LAYERS:
            if top not in reported_dirs:
                reported_dirs.add(top)
                findings.append(Finding(prefix + rel, 1, f'top folder "{top}" has no rank; add it to LAYERS (or UNRANKED) in lib/check/steps/qml_layers.py'))
            continue
        for edge in edges_of(repo, qs_dir, rel):
            seen.add((rel, edge.target))
            if not is_upward(top, edge):
                continue
            upward_seen.add((rel, edge.target))
            if (rel, edge.target) not in allowed:
                findings.append(Finding(prefix + rel, edge.line, (
                    f"{edge.text} runs upward ({top} rank {LAYERS[top]} -> {edge.layer} rank {LAYERS[edge.layer]}). "
                    "Put the code in a layer both sides may import (ui/ or core/) or pass the data in as properties; "
                    f'for a deliberate seam add "{rel} -> {edge.target}  # <reason> (<item>)" to {allow_path}.'
                )))
    for (file, target), number in allowed.items():
        if (file, target) in upward_seen:
            continue
        reason = "is not an upward edge" if (file, target) in seen else "is stale: the file no longer reaches it"
        findings.append(Finding(allow_path, number, f"{file} -> {target} {reason}. Delete the line."))
    return sorted(set(findings))


def main(argv):
    if argv:
        print("usage: lib/check/steps/qml_layers.py", file=sys.stderr)
        return 2
    findings = run_checks(REPO_DIR)
    for finding in findings:
        print(f"{finding.path}:{finding.line}: {finding.message}", file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
