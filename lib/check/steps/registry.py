#!/usr/bin/env python3
"""Fails an action definition that refers to something that does not exist.

Runs home/hypr/tests/act_refs.lua, which loads every lib/actions/defs/*.lua headlessly and prints the action list as
JSON, reads that list in memory and throws it away: no list is committed, so nothing can drift. Fails on:

  - the Lua failing or `Act` warning (an unknown id, a duplicate, bad params, a `{param}` that is not declared);
  - an id that is repeated or does not look like `area.name`;
  - an `ipc` action naming a function that is not a typed function of a real IpcHandler (read by qml_ipc.declared, the
    parser of `qml-ipc`). Arity is not checked: declared() keeps function names only;
  - a `command` action whose program is `~/<path>` that no stow package ships as `home/<pkg>/<path>`.

Skips, with a reason, when `lua` is not installed.

  python3 -B lib/check/steps/registry.py
"""

import glob
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter

sys.dont_write_bytecode = True
REPO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qml_ipc  # noqa: E402

REFS_SCRIPT = "home/hypr/tests/act_refs.lua"
ID_PATTERN = re.compile(r"^[a-z][a-z0-9]*\.[a-z][a-z0-9_]*$")
SKIP_REASON = "the action reference check needs lua"


def load_list(repo, defs_dir=None):
    """(the parsed action list, findings) from running the headless load."""
    command = ["lua", os.path.join(repo, REFS_SCRIPT)] + (["--defs", defs_dir] if defs_dir else [])
    done = subprocess.run(command, capture_output=True, text=True, cwd=repo)
    if done.returncode != 0:
        lines = [line.strip() for line in (done.stderr or done.stdout).splitlines() if line.strip()]
        return None, [f"{REFS_SCRIPT}: {line}" for line in lines] or [f"{REFS_SCRIPT}: failed"]
    try:
        return json.loads(done.stdout), []
    except ValueError as error:
        return None, [f"{REFS_SCRIPT}: the list is not JSON: {error}"]


def action_findings(repo, action, handlers):
    """What is wrong with what one action refers to, given the IpcHandlers."""
    name = action["id"]
    perform = action["perform"]
    if perform["kind"] == "ipc":
        handler = handlers.get(perform["target"])
        if handler is None:
            return [f'{name} calls IPC target "{perform["target"]}", which no IpcHandler declares']
        if perform["function"] not in handler.functions:
            return [f'{name} calls "{perform["target"]} {perform["function"]}", which is not a typed function (has: {", ".join(sorted(handler.functions))})']
    elif perform["kind"] == "command" and perform["argv"][0].startswith("~/"):
        if not glob.glob(os.path.join(repo, "home", "*", perform["argv"][0][2:])):
            return [f"{name} runs {perform['argv'][0]}, which no home/<package>/ ships"]
    return []


def list_findings(repo, listing, qml_dirs=qml_ipc.QML_DIRS):
    """Every finding for a parsed action list."""
    found = []
    actions = listing["actions"]
    for id_, count in sorted(Counter(action["id"] for action in actions).items()):
        if count > 1:
            found.append(f"action id {id_} appears {count} times")
        if not ID_PATTERN.match(id_):
            found.append(f"action id {id_} does not look like 'area.name'")
    handlers, ipc_problems = qml_ipc.declared(repo, qml_dirs)
    found += [f"{problem.path}:{problem.line}: {problem.message}" for problem in ipc_problems]
    for action in actions:
        found += action_findings(repo, action, handlers)
    return found


def run_checks(repo, defs_dir=None, qml_dirs=qml_ipc.QML_DIRS):
    """Every finding for the checkout at repo, or None when lua is missing."""
    if not shutil.which("lua"):
        return None
    listing, found = load_list(repo, defs_dir)
    return found if listing is None else list_findings(repo, listing, qml_dirs)


def main(argv):
    if argv:
        print("usage: lib/check/steps/registry.py", file=sys.stderr)
        return 2
    findings = run_checks(REPO_DIR)
    if findings is None:
        print(f"skip: {SKIP_REASON}")
        return 0
    for finding in findings:
        print(finding, file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
