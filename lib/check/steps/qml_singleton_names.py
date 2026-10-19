#!/usr/bin/env python3
"""Fails a Quickshell `pragma Singleton` file whose name ends in Config, Store or Manager.

A singleton is named for what it holds: `Settings` for the user's saved choices, `State` for live data read from outside
(the system, a daemon, a file the user does not edit), else a plain noun (`Sessions`, `Popups`). A Config, Store or
Manager suffix says nothing about which, and a Store that holds saved choices is exactly what `Settings` names.

lib/check/qml-singleton-names.allow lists the files that still carry one of those names, one per line:

  <file under the Quickshell tree>  # <reason> (<item that removes it, or "permanent">)

A line whose file is gone, is no longer a singleton or no longer has such a name fails as stale: the rename that removes
the name deletes the line, so the list only shrinks.

  python3 -B lib/check/steps/qml_singleton_names.py
"""

import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qml_imports import read_lines, strip_code  # noqa: E402
from qml_paths import QS_DIR, REPO_DIR, Finding, git_listing  # noqa: E402

ALLOW_PATH = "lib/check/qml-singleton-names.allow"
BAD_SUFFIXES = ("Config", "Store", "Manager")

ENTRY = re.compile(r"^(\S+\.qml)\s+#\s*(\S.*\S)\s+\(([^()]+)\)\s*$")
PRAGMA = re.compile(r"^\s*pragma\s+Singleton\b")


def is_singleton(path):
    """True when a line outside comments is `pragma Singleton`."""
    state = {"in_block": False}
    return any(PRAGMA.match(strip_code(line, state)) for line in read_lines(path))


def badly_named_singletons(repo, qs_dir):
    """The tree-relative paths of the singletons named with a banned suffix."""
    prefix = qs_dir + "/"
    return sorted(
        path.removeprefix(prefix)
        for path in git_listing(repo, [qs_dir])
        if path.endswith(".qml")
        and os.path.basename(path).removesuffix(".qml").endswith(BAD_SUFFIXES)
        and os.path.isfile(os.path.join(repo, path))
        and is_singleton(os.path.join(repo, path))
    )


def read_allowlist(repo, allow_path):
    """The entries as {file: line}, and the findings for malformed and duplicate lines."""
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
            findings.append(Finding(allow_path, number, 'malformed; expected "<file>.qml  # <reason> (<item>)"'))
        elif match.group(1) in entries:
            findings.append(Finding(allow_path, number, f"duplicate entry for {match.group(1)}"))
        else:
            entries[match.group(1)] = number
    return entries, findings


def run_checks(repo, qs_dir=QS_DIR, allow_path=ALLOW_PATH):
    """Every finding for the checkout at repo, sorted."""
    allowed, findings = read_allowlist(repo, allow_path)
    named = badly_named_singletons(repo, qs_dir)
    for rel in named:
        if rel not in allowed:
            name = os.path.basename(rel).removesuffix(".qml")
            suffix = next(s for s in BAD_SUFFIXES if name.endswith(s))
            findings.append(Finding(f"{qs_dir}/{rel}", 1, (
                f"singleton {name} ends in {suffix}. "
                "Name it Settings for saved user choices, State for live data read from outside, else a plain noun "
                f'(see "Naming singletons" in the Quickshell README); for a temporary exception add "{rel}  # <reason> (<item>)" to {allow_path}.'
            )))
    for rel, number in allowed.items():
        if rel not in named:
            findings.append(Finding(allow_path, number, f"{rel} is stale: it is gone, not a singleton or no longer ends in {'/'.join(BAD_SUFFIXES)}. Delete the line."))
    return sorted(set(findings))


def main(argv):
    if argv:
        print("usage: lib/check/steps/qml_singleton_names.py", file=sys.stderr)
        return 2
    findings = run_checks(REPO_DIR)
    for finding in findings:
        print(f"{finding.path}:{finding.line}: {finding.message}", file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
