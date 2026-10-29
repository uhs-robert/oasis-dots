#!/usr/bin/env python3
"""Fails an action definition that refers to something that does not exist.

Runs home/hypr/tests/act_refs.lua, which loads every lib/act/defs/*.lua headlessly and prints the action list as
JSON, reads that list in memory and throws it away: no list is committed, so nothing can drift. Fails on:

  - the Lua failing or `Act` warning (an unknown id, a duplicate, bad params, a `{param}` that is not declared);
  - an id that is repeated or does not look like `area.name`;
  - an `ipc` action naming a function that is not a typed function of a real IpcHandler (read by qml_ipc.declared, the
    parser of `qml-ipc`), or passing it more or fewer arguments than it declares parameters (`qs ipc call` refuses
    a call whose argument count differs);
  - a `command` action whose program is `~/<path>` that no stow package ships as `home/<pkg>/<path>`, except the
    executables in BUILT_EXECUTABLES, which an installer recipe creates;
  - a bind that performs no action and an IPC function that no action calls, unless lib/check/registry.allow lists it
    with a reason (below), and an allow line that no longer matches anything.

The binds come from home/hypr/tests/registry_binds.lua, which loads `keymaps` under stubs and prints each bind with the
action id it performs. `custom/` is never loaded, so the owner's own binds are not checked.

lib/check/registry.allow, one entry per line, the reason after `#` being required:

  bind <submap> <key>  # <reason>        `global` is the map outside any submap; `*` is every named submap; submaps
                                         may be a comma list (`Go,Move`)
  ipc <target> <function>...  # <reason>

A key is compared the way Hyprland does, ignoring case and spaces. An entry that matches no bind or function, or whose
bind or function has an action now, is stale and fails.

Fails, not skips, when `lua` is not installed: a machine without it would otherwise pass the registry unread.

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
from typing import NamedTuple

sys.dont_write_bytecode = True
REPO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qml_ipc  # noqa: E402

REFS_SCRIPT = "home/hypr/tests/act_refs.lua"
ID_PATTERN = re.compile(r"^[a-z][a-z0-9]*\.[a-z][a-z0-9_]*$")
# Executables a recipe builds and links into ~/, so no home/<package>/ ships them. Add one only with the recipe that makes it.
BUILT_EXECUTABLES = {"~/.local/bin/voxcmd": "just voxcmd-build"}
BINDS_SCRIPT = "home/hypr/tests/registry_binds.lua"
ALLOW_PATH = "lib/check/registry.allow"
MISSING_LUA = "lua is not installed; the registry step fails without it rather than pass unread"
GLOBAL_MAP = "global"
ANY_SUBMAP = "*"


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


def load_binds(repo, module=None, path=None):
    """([(submap, key, action id or None)], findings) from running the bind dump. module and path plant a keymap."""
    command = ["lua", os.path.join(repo, BINDS_SCRIPT)] + (["--module", module, "--path", path] if module else [])
    done = subprocess.run(command, capture_output=True, text=True, cwd=repo)
    if done.returncode != 0:
        lines = [line.strip() for line in (done.stderr or done.stdout).splitlines() if line.strip()]
        return None, [f"{BINDS_SCRIPT}: {line}" for line in lines] or [f"{BINDS_SCRIPT}: failed"]
    binds = []
    for line in done.stdout.splitlines():
        submap, key, action = line.split("\t")
        binds.append((submap, key, None if action == "-" else action))
    return binds, []


class AllowEntry(NamedTuple):
    line: int
    kind: str  # "bind" or "ipc"
    submap_or_target: str
    names: tuple  # the key (bind) or the functions (ipc)


def read_allowlist(repo, allow_path=ALLOW_PATH):
    """([AllowEntry], findings) from the allow file. A missing file is an empty list."""
    try:
        with open(os.path.join(repo, allow_path), encoding="utf-8") as file:
            lines = file.read().splitlines()
    except FileNotFoundError:
        return [], []
    entries, found, seen = [], [], set()
    for number, raw in enumerate(lines, 1):
        text, _, reason = raw.partition("#")
        words = text.split()
        if not words:
            continue
        where = f"{allow_path}:{number}"
        if not reason.strip():
            found.append(f"{where}: needs a reason after #")
            continue
        if words[0] == "bind" and len(words) >= 3:
            # A key may hold spaces ("SUPER + H"), so it is whatever follows the submap.
            entry = AllowEntry(number, "bind", words[1], (text.split(None, 2)[2].strip(),))
        elif words[0] == "ipc" and len(words) >= 3:
            entry = AllowEntry(number, "ipc", words[1], tuple(words[2:]))
        else:
            found.append(f'{where}: malformed; expected "bind <submap> <key>  # <reason>" or "ipc <target> <function>...  # <reason>"')
            continue
        for name in entry.names if entry.kind == "ipc" else (normalize_key(entry.names[0]),):
            identity = (entry.kind, entry.submap_or_target, name)
            if identity in seen:
                found.append(f"{where}: duplicate entry for {entry.kind} {entry.submap_or_target} {name}")
            seen.add(identity)
        entries.append(entry)
    return entries, found


def normalize_key(key):
    """Hyprland compares keys ignoring case and whitespace."""
    return "".join(key.split()).lower()


def allow_findings(binds, handlers, listing, entries, allow_path=ALLOW_PATH):
    """Binds without an action and IPC functions without an action that the allow entries do not cover, and the
    entries that cover nothing."""
    found = []
    plain = [(submap, key) for submap, key, action in binds if action is None]
    used = set()
    for submap, key in plain:
        covering = []
        for entry in entries:
            if entry.kind != "bind" or normalize_key(entry.names[0]) != normalize_key(key):
                continue
            for name in entry.submap_or_target.split(","):
                if name == submap or (name == ANY_SUBMAP and submap != GLOBAL_MAP):
                    covering.append((entry.line, name))
        used.update(covering)
        if not covering:
            found.append(
                f"bind {submap} {key} performs no action; define an action for it or add "
                f'"bind {submap} {key}  # <reason>" to {allow_path}'
            )
    called = {
        (action["perform"]["target"], action["perform"]["function"])
        for action in listing["actions"]
        if action["perform"]["kind"] == "ipc"
    }
    allowed_ipc = {
        (entry.submap_or_target, function) for entry in entries if entry.kind == "ipc" for function in entry.names
    }
    for target, handler in sorted(handlers.items()):
        for function in sorted(handler.functions):
            if (target, function) not in called and (target, function) not in allowed_ipc:
                found.append(
                    f"IPC function {target} {function} has no action; define one or add "
                    f'"ipc {target} {function}  # <reason>" to {allow_path}'
                )
    for entry in entries:
        if entry.kind == "bind":
            for name in entry.submap_or_target.split(","):
                if (entry.line, name) not in used:
                    found.append(
                        f"{allow_path}:{entry.line}: bind {name} {entry.names[0]} is stale: no bind without an "
                        "action matches it. Delete it from the line."
                    )
            continue
        handler = handlers.get(entry.submap_or_target)
        for function in entry.names:
            if handler is None or function not in handler.functions:
                found.append(f"{allow_path}:{entry.line}: ipc {entry.submap_or_target} {function} is stale: no IpcHandler declares it. Delete the line.")
            elif (entry.submap_or_target, function) in called:
                found.append(f"{allow_path}:{entry.line}: ipc {entry.submap_or_target} {function} is stale: an action calls it now. Delete the line.")
    return found


def arity_findings(name, perform, handler):
    """A finding when an ipc action passes a different number of arguments than the function's parameters."""
    for function, parameters, _ in handler.signatures:
        if function == perform["function"]:
            expected = len([p for p in parameters.split(",") if p.strip()])
            given = len(perform.get("args", []))
            if given != expected:
                return [f'{name} calls "{perform["target"]} {function}" with {given} argument(s), but {function}({parameters}) takes {expected}']
    return []


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
        return arity_findings(name, perform, handler)
    elif perform["kind"] == "command" and perform["argv"][0].startswith("~/"):
        if perform["argv"][0] in BUILT_EXECUTABLES:
            return []
        if not glob.glob(os.path.join(repo, "home", "*", perform["argv"][0][2:])):
            return [f"{name} runs {perform['argv'][0]}, which no home/<package>/ ships"]
    return []


def list_findings(repo, listing, qml_dirs=qml_ipc.QML_DIRS, binds=None, allow_path=ALLOW_PATH):
    """Every finding for a parsed action list; with `binds` (from load_binds), also the bind and IPC coverage."""
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
    if binds is not None:
        entries, allow_problems = read_allowlist(repo, allow_path)
        found += allow_problems
        found += allow_findings(binds, handlers, listing, entries, allow_path)
    return found


def run_checks(repo, defs_dir=None, qml_dirs=qml_ipc.QML_DIRS, keymap=None, allow_path=ALLOW_PATH, coverage=True):
    """Every finding for the checkout at repo. keymap is (module, path) of a planted keymap to load instead of the
    shipped ones; coverage=False skips the bind and IPC coverage (a planted defs directory replaces the real actions)."""
    if not shutil.which("lua"):
        return [MISSING_LUA]
    listing, found = load_list(repo, defs_dir)
    if listing is None:
        return found
    if not coverage:
        return list_findings(repo, listing, qml_dirs)
    binds, bind_problems = load_binds(repo, *(keymap or (None, None)))
    if binds is None:
        return bind_problems
    return list_findings(repo, listing, qml_dirs, binds, allow_path)


def main(argv):
    if argv:
        print("usage: lib/check/steps/registry.py", file=sys.stderr)
        return 2
    findings = run_checks(REPO_DIR)
    for finding in findings:
        print(finding, file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
