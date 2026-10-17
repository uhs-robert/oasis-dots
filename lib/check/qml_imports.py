"""Reads Quickshell QML and JS import statements and the greeter's file list; shared by the qmllint step (steps/qml.py)."""

import fnmatch
import os
import re
import subprocess

GREETER_LIST = "lib/common/greeter-files.sh"

# POSIX [[:space:]], ASCII only.
WS = "[ \t\n\v\f\r]"
QS_IMPORT = re.compile(rf"^{WS}*import{WS}+qs(\.[A-Za-z0-9_]+)*({WS}|$)")
QS_IMPORT_HEAD = re.compile(rf"^{WS}*import{WS}+qs")
QUOTED_IMPORT = re.compile(rf'^{WS}*import{WS}+"[^"]+"')
IMPORT_ALIAS = re.compile(rf'({WS}|"){WS}*as{WS}+[A-Za-z_][A-Za-z0-9_]*')
SCRIPT_TARGET = re.compile(r"\.m?js$")
FROM_FIRST_SPACE = re.compile(rf"{WS}.*$", re.S)
UP_TO_LAST_SPACE = re.compile(rf".*{WS}", re.S)


def read_lines(path):
    """A file's lines as awk and grep see them: split on newline only, no empty record after a final newline."""
    with open(path, "rb") as file:
        text = file.read().decode("utf-8", "surrogateescape")
    lines = text.split("\n")
    if lines[-1] == "":
        lines.pop()
    return lines


def greeter_list(repo):
    """Every GREETER_QS_FILES entry as written, optional mark and globs included. The list stays bash, read by
    sourcing it, so it has no second copy here."""
    script = 'source "$1" && printf "%s\\0" "${GREETER_QS_FILES[@]}"'
    output = subprocess.run(
        ("bash", "-c", script, "_", os.path.join(repo, GREETER_LIST)), stdout=subprocess.PIPE, check=True
    ).stdout.decode("utf-8", "surrogateescape")
    return output.split("\0")[:-1]


def greeter_entries(repo):
    """The greeter list's QML and JS entries (directories, .qml and .js files), optional mark dropped."""
    entries = []
    for entry in greeter_list(repo):
        entry = entry.removesuffix("?")
        if entry.endswith(("/", ".qml", ".js")):
            entries.append(entry)
    return entries


def staged_files(qs_files, entries):
    """Splits the greeter list's entries (as greeter_list reads them) into the Quickshell files the greeter stages,
    from qs_files (paths relative to the Quickshell dir), and the required entries that match none of them."""
    staged = set()
    unmatched = []
    for entry in entries:
        optional = entry.endswith("?")
        entry = entry.removesuffix("?")
        if entry.endswith("/"):
            found = {path for path in qs_files if path.startswith(entry)}
        else:
            found = {path for path in qs_files if fnmatch.fnmatchcase(path, entry)}
        staged |= found
        if not found and not optional:
            unmatched.append(entry)
    return staged, unmatched


def folder_imports(path, root):
    """Yields (alias or None, folder) for each folder import in the file. A quoted import is relative to the importing
    file, `import qs.a.b` to the tree root. The folder is not resolved; script imports are skipped. Only single-line
    imports are read, and commented-out ones count."""
    try:
        lines = read_lines(path)
    except OSError:
        return
    for line in lines:
        for statement in line.split(";"):
            if match := QS_IMPORT.match(statement):
                target = QS_IMPORT_HEAD.sub("", match.group(0), count=1)
                target = FROM_FIRST_SPACE.sub("", target, count=1).replace(".", "/")
                base = root
            elif match := QUOTED_IMPORT.match(statement):
                target = match.group(0).split('"', 1)[1].removesuffix('"')
                if SCRIPT_TARGET.search(target):
                    continue
                target = "/" + target
                base = path.rsplit("/", 1)[0]
            else:
                continue
            alias = None
            if match := IMPORT_ALIAS.search(statement):
                alias = UP_TO_LAST_SPACE.sub("", match.group(0), count=1)
            yield alias, base + target


def strip_code(line, state, keep_strings=False):
    """The line without comments and string contents (a string keeps its quotes; keep_strings keeps the contents
    too). state["in_block"] carries an open block comment to the next line; a string's quote does not carry, so a
    template literal's later lines read as code."""
    if keep_strings and "/" not in line and not state["in_block"]:
        # No comment can start or end here, and every string is kept as it is.
        return line
    out = []
    quote = ""
    i = 0
    while i < len(line):
        c = line[i]
        following = line[i + 1:i + 2]
        if state["in_block"]:
            if c == "*" and following == "/":
                state["in_block"] = False
                i += 1
        elif quote:
            if c == "\\":
                if keep_strings:
                    out.append(line[i:i + 2])
                i += 1
            elif c == quote:
                quote = ""
                out.append(c)
            elif keep_strings:
                out.append(c)
        elif c == "/" and following == "/":
            break
        elif c == "/" and following == "*":
            state["in_block"] = True
            i += 1
        else:
            if c in "\"'`":
                quote = c
            out.append(c)
        i += 1
    return "".join(out)


QUOTED_STATEMENT = re.compile(rf'^{WS}*\.?import{WS}+"([^"]+)"')
QS_STATEMENT = re.compile(rf"^{WS}*import{WS}+qs((?:\.[A-Za-z0-9_]+)*)({WS}|$)")


def imports(path):
    """Yields (kind, target, line) for each import the file makes, with comments stripped: ("qs", "a/b") for
    `import qs.a.b` (the root is ""), ("folder", text) and ("script", text) for a quoted import, and a JS file's
    `.import "x.js"` as a script. Quoted targets are as written, relative to the importing file. Only single-line
    imports are read."""
    try:
        lines = read_lines(path)
    except OSError:
        return
    state = {"in_block": False}
    for number, raw in enumerate(lines, 1):
        for statement in strip_code(raw, state, keep_strings=True).split(";"):
            if match := QS_STATEMENT.match(statement):
                yield "qs", match.group(1).removeprefix(".").replace(".", "/"), number
            elif match := QUOTED_STATEMENT.match(statement):
                kind = "script" if SCRIPT_TARGET.search(match.group(1)) else "folder"
                yield kind, match.group(1), number
