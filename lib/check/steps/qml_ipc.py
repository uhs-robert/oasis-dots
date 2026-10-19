#!/usr/bin/env python3
"""Fails a `qs ipc call` that names a target or function no Quickshell IpcHandler exposes, and a handler nothing calls.

A caller is a string in a shell script, a Lua file, a Rust file, a tmux.conf or a test stub, so renaming or moving a
handler passes qmllint and every caller then fails silently at runtime (the call answers ""). This step reads the
declarations from the QML and every caller from the rest of the tree (tracked and untracked-but-not-ignored files, as
git lists them) and checks that each caller's target and function exist.

Declared: every `IpcHandler` in QML_DIRS gives its `target:` string literal and the functions at the handler's own
depth. Quickshell exposes only a function whose parameters and return are all typed, so
`function select(frozen: bool): string` counts and `function helper(x)` does not; calling a helper passes a
looser scan and fails live. A target that is not a string literal, or declared twice, fails.

Callers: every file except `.qml`, `.md`, binaries and lib/check/. See CALLERS for the syntaxes; a target or function
that is computed (`$name`, `" .. x`) is skipped, a literal target beside a computed function still has its target
checked, and arity is not checked. Docs are not scanned because prose has placeholders such as `<name>`.

lib/check/qml-ipc.allow holds the exceptions, one per line:

  uncalled <target>  # <reason> (<item that removes it, or "permanent">)
  frozen <target> <function>...  # <reason> (<item>)

`uncalled` excuses a declared target nothing in the repo calls. `frozen` names an interface that callers outside this
repo depend on: the target and every listed function must stay declared and typed, and the target needs no in-repo
caller. A line that no longer applies (an `uncalled` target that is now called or gone, a `frozen` name that is gone)
fails as stale, so the list only shrinks.

  python3 -B lib/check/steps/qml_ipc.py
"""

import os
import re
import sys
from typing import NamedTuple

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qml_imports import blank_strings, read_lines, strip_code  # noqa: E402
from qml_paths import QS_DIR, REPO_DIR, Finding, git_listing  # noqa: E402

ALLOW_PATH = "lib/check/qml-ipc.allow"
QML_DIRS = (QS_DIR, "demo/overlay")
SELF_DIR = "lib/check/"  # the step's own tests hold deliberately wrong calls
SKIPPED_SUFFIXES = (".qml", ".md")

# Helpers pinned to one target, whose first argument is the function: file -> [(helper name, target)].
WRAPPERS = {
    "home/hypr/.config/hypr/scripts/screenshot.sh": [("qs_call", "screenshot")],
    "demo/showcase.sh": [("overlay_ipc", "demo")],
}
# Files where a bare `q <target> <function>` is the shadow skill's IPC shorthand.
Q_SHORTHAND_FILES = (".claude/skills/shadow/smoke.sh",)

ENTRY = re.compile(r"^(uncalled\s+\S+|frozen\s+\S+(?:\s+\w+)+)\s+#\s*(\S.*\S)\s+\(([^()]+)\)\s*$")


# --- Declarations ----------------------------------------------------------------------------------------------------

class Handler(NamedTuple):
    path: str
    line: int
    functions: frozenset  # the typed ones only


PARAM = re.compile(r"^\s*\w+\s*:\s*[\w.<>]+\s*$")
RETURN = re.compile(r"\s*:\s*[\w.<>]+")


def depth_one(text, start):
    """(end, the body) of the braces opened just before start: the body with everything nested deeper blanked to
    spaces, newlines kept so offsets and line numbers stay."""
    depth, i, body = 1, start, []
    while i < len(text) and depth:
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        body.append(c if depth == 1 and c != "}" or c == "\n" else " ")
        i += 1
    return i, "".join(body)


def is_exposed(parameters, after_parameters):
    """Quickshell exposes a function only when its return and every parameter are typed."""
    declared_parameters = [p for p in parameters.split(",") if p.strip()]
    return bool(RETURN.match(after_parameters)) and all(PARAM.match(p) for p in declared_parameters)


def declarations(path, rel):
    """([(target, Handler)], findings) for the IpcHandlers in one QML file."""
    state = {"in_block": False}
    code = "\n".join(strip_code(line, state, keep_strings=True) for line in read_lines(path))
    blank = "\n".join(blank_strings(line) for line in code.split("\n"))
    found, findings = [], []
    for match in re.finditer(r"\bIpcHandler\s*\{", blank):
        line = blank.count("\n", 0, match.start()) + 1
        end, body = depth_one(blank, match.end())
        offset = match.end()
        target = re.search(r"\btarget\s*:\s*", body)
        if not target:
            findings.append(Finding(rel, line, "IpcHandler has no target"))
            continue
        at = offset + target.end()
        literal = re.match(r"([\"'])(.*?)\1", code[at:end])
        if not literal:
            findings.append(Finding(rel, line, "IpcHandler target must be a string literal"))
            continue
        functions = set()
        for function in re.finditer(r"\bfunction\s+(\w+)\s*\(([^)]*)\)", body):
            after = body[function.end():function.end() + 80].split("{", 1)[0]
            if is_exposed(function.group(2), after):
                functions.add(function.group(1))
        found.append((literal.group(2), Handler(rel, line, frozenset(functions))))
    return found, findings


def declared(repo, qml_dirs):
    """({target: Handler}, findings) for every QML file under the dirs."""
    handlers, findings = {}, []
    for rel in sorted(git_listing(repo, list(qml_dirs))):
        if not rel.endswith(".qml") or not os.path.isfile(os.path.join(repo, rel)):
            continue
        found, problems = declarations(os.path.join(repo, rel), rel)
        findings += problems
        for target, handler in found:
            if target in handlers:
                first = handlers[target]
                findings.append(Finding(rel, handler.line, f'IpcHandler target "{target}" is also declared at {first.path}:{first.line}'))
            else:
                handlers[target] = handler
    return handlers, findings


# --- Callers ---------------------------------------------------------------------------------------------------------

# A target or function token: a literal name, and not the start of a longer expression (`popup_$x`, `a.b`).
TARGET = r"([A-Za-z_][\w-]*)(?![\w$.{\[(-])"
FUNCTION = r"([A-Za-z_]\w*)(?![\w$.{\[(-])"
CALL_ARGS = rf"call[ \t]+{TARGET}(?:[ \t]+{FUNCTION})?"
# The word before `call`: qs-ipc, QS_IPC, $ipc, ${QS_IPC:-.../qs-ipc}, overlay_ipc, qs_query, or `qs ipc [--pid X]` itself. A bare
# `ipc` is not one, so prose such as "<ipc call args>" is not read as a call.
IPC_WORD = r"(?:\$\{?\w*ipc\w*|[\w-]*(?:qs[-_](?:ipc|query)|_ipc)\w*|\bqs[ \t]+ipc(?:[ \t]+--pid[ \t]+\S+)?)[}\"']*"
# Quickshell's own `ipc show`, not a handler.
BUILTINS = {"show"}


class Caller(NamedTuple):
    path: str
    line: int
    target: str
    function: str  # "" when computed or absent


CALL_LIST_ITEM = re.compile(rf"""["']{TARGET}(?:[ \t]+{FUNCTION})?["']""")


def pair(match):
    """The (target, function) of a match whose groups are a target and an optional function."""
    return [(match.group(1), match.group(2) or "")]


def call_list(match):
    """The pairs in a `for call in "popup close" "overview close"` list."""
    return [(item.group(1), item.group(2) or "") for item in CALL_LIST_ITEM.finditer(match.group(1))]


def readers_for(rel):
    """[(regex, reader)] for one file: each regex finds a call, and its reader turns a match into (target, function)
    pairs."""
    readers = [
        # bash, tmux.conf, goldens, stubs that echo the command: `"$qs_ipc" call popup open`
        (re.compile(rf"{IPC_WORD}[ \t]+{CALL_ARGS}", re.I), pair),
        # a case pattern in a test stub: *"call popup open"*
        (re.compile(rf"""\*"{CALL_ARGS}"""), pair),
        # Python argv: "call", "calendar", "refresh"
        (re.compile(rf"""["']call["'],\s*["']{TARGET}["'](?:,\s*["']{FUNCTION}["'])?"""), pair),
        # Rust: qs_ipc_call(&["popup".as_ref(), "open".as_ref()]) and ask(&["popup", "state"]), over lines
        (re.compile(rf"""\b(?:qs_ipc_call|ask)\(\s*&\[\s*["']{TARGET}["'](?:(?:\.as_ref\(\))?\s*,\s*["']{FUNCTION}["'])?"""), pair),
        # the shadow skill's own command: shadow.sh ipc base popup state
        (re.compile(rf"""\bshadow\.sh[ \t]+ipc[ \t]+\S+[ \t]+{TARGET}(?:[ \t]+{FUNCTION})?"""), pair),
        (re.compile(r"""\bfor[ \t]+call[ \t]+in((?:[ \t]+"[^"]*")+)[ \t]*;"""), call_list),
    ]
    if rel.endswith(".lua"):
        # a Lua string that starts with `call`, so a continuation line has no ipc word: " call settings open"
        readers.append((re.compile(rf"""["']\s*{CALL_ARGS}"""), pair))
    if rel in Q_SHORTHAND_FILES:
        readers.append((re.compile(rf"""(?<![\w-])q[ \t]+{TARGET}(?:[ \t]+{FUNCTION})?"""), pair))
    if rel == "demo/showcase.sh":
        # its ipc helper takes the key label first: ipc "SUPER + TAB" call overview open
        readers.append((re.compile(rf"""^[ \t]*ipc[ \t]+"[^"]*"[ \t]+{CALL_ARGS}""", re.M), pair))
    for helper, target in WRAPPERS.get(rel, []):
        readers.append((re.compile(rf"""\b{helper}[ \t]+{FUNCTION}"""), lambda match, target=target: [(target, match.group(1))]))
    return readers


def callers_in(rel, text):
    """The callers one file holds, as Callers."""
    return [
        Caller(rel, text.count("\n", 0, match.start()) + 1, target, function)
        for regex, reader in readers_for(rel)
        for match in regex.finditer(text)
        for target, function in reader(match)
        if target not in BUILTINS
    ]


def is_text(path):
    try:
        with open(path, "rb") as file:
            return b"\0" not in file.read(8192)
    except OSError:
        return False


def callers(repo, listing):
    found = []
    for rel in sorted(listing):
        full = os.path.join(repo, rel)
        if rel.endswith(SKIPPED_SUFFIXES) or rel.startswith(SELF_DIR) or os.path.islink(full):
            continue
        if not os.path.isfile(full) or not is_text(full):
            continue
        with open(full, encoding="utf-8", errors="surrogateescape") as file:
            found += callers_in(rel, file.read())
    return found


# --- Allowlist -------------------------------------------------------------------------------------------------------

class Entry(NamedTuple):
    kind: str  # "uncalled" or "frozen"
    target: str
    functions: tuple
    line: int


def read_allowlist(repo, allow_path):
    """([Entry], findings for malformed and duplicate lines)."""
    entries, findings, seen = [], [], set()
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
            findings.append(Finding(allow_path, number, 'malformed; expected "uncalled <target>  # <reason> (<item>)" or "frozen <target> <function>...  # <reason> (<item>)"'))
            continue
        kind, target, *functions = match.group(1).split()
        if target in seen:
            findings.append(Finding(allow_path, number, f"duplicate entry for {target}"))
            continue
        seen.add(target)
        entries.append(Entry(kind, target, tuple(functions), number))
    return entries, findings


# --- Checks ----------------------------------------------------------------------------------------------------------

def run_checks(repo, qml_dirs=QML_DIRS, allow_path=ALLOW_PATH):
    """Every finding for the checkout at repo, sorted."""
    handlers, findings = declared(repo, qml_dirs)
    entries, problems = read_allowlist(repo, allow_path)
    findings += problems
    calls = callers(repo, git_listing(repo, []))
    called = {call.target for call in calls}
    for call in calls:
        handler = handlers.get(call.target)
        if handler is None:
            findings.append(Finding(call.path, call.line, f'qs ipc target "{call.target}" is declared by no IpcHandler (declared: {", ".join(sorted(handlers))})'))
        elif call.function and call.function not in handler.functions:
            findings.append(Finding(call.path, call.line, f'target "{call.target}" has no typed function "{call.function}" (has: {", ".join(sorted(handler.functions))})'))
    allowed = {entry.target: entry for entry in entries}
    for target, handler in sorted(handlers.items()):
        if target not in called and target not in allowed:
            findings.append(Finding(handler.path, handler.line, f'target "{target}" is called by nothing in the repo; add a caller or "uncalled {target}  # <reason> (<item>)" to {allow_path}'))
    for entry in entries:
        handler = handlers.get(entry.target)
        if handler is None:
            findings.append(Finding(allow_path, entry.line, f'{entry.kind} {entry.target} is stale: no IpcHandler declares it. Delete the line.'))
        elif entry.kind == "uncalled" and entry.target in called:
            findings.append(Finding(allow_path, entry.line, f"uncalled {entry.target} is stale: something calls it now. Delete the line."))
        else:
            for function in entry.functions:
                if function not in handler.functions:
                    findings.append(Finding(allow_path, entry.line, f'frozen {entry.target} is stale: it has no typed function "{function}" (has: {", ".join(sorted(handler.functions))}).'))
    return sorted(set(findings))


def main(argv):
    if argv:
        print("usage: lib/check/steps/qml_ipc.py", file=sys.stderr)
        return 2
    findings = run_checks(REPO_DIR)
    for finding in findings:
        print(f"{finding.path}:{finding.line}: {finding.message}", file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
