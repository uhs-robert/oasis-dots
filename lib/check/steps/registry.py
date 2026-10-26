#!/usr/bin/env python3
"""Fails an action manifest that breaks its schema, repeats an id, lacks, repeats or has a stray binding, or whose
binding names something that does not exist.

  - actions.json and every bindings/*.json (home/oasis-djinn/.config/oasis-djinn) validate against
    specs/schema/actions.yaml and bindings.yaml. The step fails, not skips, without check-jsonschema, so a manifest is
    never passed unread.
  - a bindings file is one BINDING_KINDS knows (hypr's lib/key/bind.lua reads those by name) and holds only its kinds.
  - action ids and param names are unique; params with a default come last, and an enum default is one of its values, an int default is a whole i64; every action has exactly one binding and every binding an action.
  - a `lua` binding has a function in hypr's lib/actions/performers.lua, and every function there a `lua` binding.
  - an `ipc` binding names a typed function of a real IpcHandler (read by qml_ipc.declared, the parser of `qml-ipc`),
    and every `{param}` in a binding is a param of its action.
  - a `command` binding whose program is `~/<path>` names a file some stow package ships as `home/<pkg>/<path>`.
    Arity of an ipc call is not checked: declared() keeps function names only.

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

MANIFEST_DIR = "home/oasis-djinn/.config/oasis-djinn"
ACTIONS_SCHEMA = "specs/schema/actions.yaml"
BINDINGS_SCHEMA = "specs/schema/bindings.yaml"
# The tools and the binding kinds each one performs; a file not listed here is one hypr's Bind.action never reads.
BINDING_KINDS = {"quickshell.json": {"ipc", "command"}, "hyprland.json": {"lua"}}
PERFORMERS = "home/hypr/.config/hypr/lib/actions/performers.lua"
# performers.lua keeps its functions as `["<id>"] = function` table rows; the registry reads them as text so it needs
# no Hyprland stub to load the module.
PERFORMER_ROW = re.compile(r'^\s*\["([^"]+)"\]\s*=\s*function\b', re.MULTILINE)
MISSING_TOOL = "check-jsonschema is not installed (pipx install check-jsonschema); the registry step fails without it rather than pass unread"
PLACEHOLDER = re.compile(r"\{(\w+)\}")


def schema_findings(repo, schema, file):
    done = subprocess.run(["check-jsonschema", "--schemafile", os.path.join(repo, schema), os.path.join(repo, file)],
                          capture_output=True, text=True)
    if done.returncode == 0:
        return []
    lines = [line for line in (done.stdout + done.stderr).splitlines() if line.strip() and not line.startswith("Schema validation errors")]
    return [f"{file}: {line.strip()}" for line in lines] or [f"{file}: schema validation failed"]


def read(repo, file):
    try:
        with open(os.path.join(repo, file), encoding="utf-8") as handle:
            return json.load(handle), []
    except (OSError, ValueError) as error:
        return None, [f"{file}: {error}"]


def param_findings(file, action):
    """What the schema cannot say about the defaults of one action's params."""
    found = []
    defaulted = None
    for param in action["params"]:
        if "default" in param:
            defaulted = defaulted or param["name"]
            if param["type"] == "int" and isinstance(param["default"], float):
                # JSON Schema calls 1.0 an integer; oasis-djinn parses an int as i64 and refuses "1.0".
                found.append(f"{file}: {action['id']} param {param['name']} default {param['default']!r} must be written as an integer, without a fraction or exponent")
            if param["type"] == "enum" and param["default"] not in param["values"]:
                found.append(f"{file}: {action['id']} param {param['name']} default {param['default']!r} is not one of its values")
            if param["type"] == "string" and param["default"].startswith("-"):
                found.append(f"{file}: {action['id']} param {param['name']} default starts with '-', which oasis-djinn rejects")
        elif defaulted:
            found.append(f"{file}: {action['id']} requires param {param['name']} after {defaulted}, which has a default and so could never be left out")
    return found


def binding_findings(repo, file, action, binding, handlers):
    """What is wrong with one binding of an action, given the IpcHandlers."""
    name = action["id"]
    found = []
    words = binding.get("args", []) + binding.get("argv", [])
    known = {param["name"] for param in action["params"]}
    for word in words:
        for used in PLACEHOLDER.findall(word):
            if used not in known:
                found.append(f"{file}: {name} uses {{{used}}}, which is not one of its params")
    if binding["kind"] == "ipc":
        handler = handlers.get(binding["target"])
        if handler is None:
            found.append(f'{file}: {name} calls IPC target "{binding["target"]}", which no IpcHandler declares')
        elif binding["function"] not in handler.functions:
            found.append(f'{file}: {name} calls "{binding["target"]} {binding["function"]}", which is not a typed function (has: {", ".join(sorted(handler.functions))})')
    elif binding["kind"] == "command" and binding["argv"][0].startswith("~/"):
        pattern = os.path.join(repo, "home", "*", binding["argv"][0][2:])
        if not glob.glob(pattern):
            found.append(f"{file}: {name} runs {binding['argv'][0]}, which no home/<package>/ ships")
    return found


def performer_findings(repo, lua_ids):
    """A lua binding whose id has no function in performers.lua, and a function there no lua binding names."""
    try:
        with open(os.path.join(repo, PERFORMERS), encoding="utf-8") as handle:
            defined = set(PERFORMER_ROW.findall(handle.read()))
    except OSError as error:
        return [f"{PERFORMERS}: {error}"] if lua_ids else []
    found = [f"{id_} is a lua binding, but performers.lua has no function for it" for id_ in sorted(lua_ids - defined)]
    found += [f"{PERFORMERS}: has a function for {id_}, which no lua binding names" for id_ in sorted(defined - lua_ids)]
    return found


def run_checks(repo, manifest_dir=MANIFEST_DIR, qml_dirs=qml_ipc.QML_DIRS):
    """Every finding for the checkout at repo."""
    if not shutil.which("check-jsonschema"):
        return [MISSING_TOOL]
    actions_file = f"{manifest_dir}/actions.json"
    binding_files = sorted(os.path.relpath(path, repo) for path in glob.glob(os.path.join(repo, manifest_dir, "bindings", "*.json")))
    found = schema_findings(repo, ACTIONS_SCHEMA, actions_file)
    for file in binding_files:
        if os.path.basename(file) not in BINDING_KINDS:
            found.append(f"{file} is not a bindings file (known: {', '.join(sorted(BINDING_KINDS))}); Bind.action would never read it")
        else:
            found += schema_findings(repo, BINDINGS_SCHEMA, file)
    if found:
        return found
    manifest, problems = read(repo, actions_file)
    if problems:
        return problems
    actions = manifest["actions"]
    bindings = {}  # action id -> (bindings file, binding)
    for file in binding_files:
        parsed, problems = read(repo, file)
        if problems:
            return problems
        file_label = f"bindings/{os.path.basename(file)}"
        for id_, binding in sorted(parsed["bindings"].items()):
            if binding["kind"] not in BINDING_KINDS[os.path.basename(file)]:
                found.append(f"{file}: {id_} is a {binding['kind']} binding, which this file cannot hold")
            if id_ in bindings:
                first = f"bindings/{os.path.basename(bindings[id_][0])}"
                found.append(f"{manifest_dir}: {id_} is bound in both {first} and {file_label}")
            else:
                bindings[id_] = (file, binding)
    for id_, count in sorted(Counter(action["id"] for action in actions).items()):
        if count > 1:
            found.append(f"{actions_file}: action id {id_} appears {count} times")
    for action in actions:
        for name, count in sorted(Counter(param["name"] for param in action["params"]).items()):
            if count > 1:
                found.append(f"{actions_file}: {action['id']} repeats param {name}")
        found += param_findings(actions_file, action)
    handlers, ipc_problems = qml_ipc.declared(repo, qml_dirs)
    found += [f"{problem.path}:{problem.line}: {problem.message}" for problem in ipc_problems]
    by_id = {action["id"]: action for action in actions}
    for id_, action in sorted(by_id.items()):
        if id_ not in bindings:
            found.append(f"{manifest_dir}/bindings: {id_} has no binding")
        else:
            found += binding_findings(repo, bindings[id_][0], action, bindings[id_][1], handlers)
    for id_ in sorted(set(bindings) - set(by_id)):
        found.append(f"{bindings[id_][0]}: binding {id_} names no action")
    found += performer_findings(repo, {id_ for id_, (_, binding) in bindings.items() if binding["kind"] == "lua"})
    return found


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
