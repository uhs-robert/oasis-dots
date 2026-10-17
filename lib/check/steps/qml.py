#!/usr/bin/env python3
"""Lints the Quickshell config and the greeter with Qt 6 qmllint, failing only on findings that are real errors.

Stages qmldirs only for the folders Quickshell registers (reached by imports from shell.qml) and flags uses of
unregistered types. Fails on syntax errors, unknown types or imports, unknown or misspelled properties and names,
type-incompatible assignments, writes to read-only properties, and duplicate or cyclic declarations; not on style
warnings, members read through untyped `parent`/`Loader.item`, or known gaps in Quickshell's type info. A file loaded by
URL from a folder nothing reached from shell.qml imports fails when it instantiates, declares a property of, or reads a
singleton among its siblings' types (#531).

Known gaps, to be fixed on their own: commented-out imports count when reading imports, a string's quote does not
carry across lines, a repeated import is reported twice, and a report the filter cannot read is reported but passes.

  python3 -B lib/check/steps/qml.py [--keep-stage DIR]

--keep-stage copies the stage (sources, qmldirs, the pruned Quickshell module, reached lists, raw reports) to DIR,
which must not exist, for debugging a qmllint upgrade.
"""

import json
import locale
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from qml_imports import GREETER_LIST, WS, folder_imports, greeter_entries, read_lines, strip_code  # noqa: E402

REPO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
QS_DIR = "home/quickshell/.config/quickshell"
GREETER_DIR = "system/etc/greetd/quickshell"
# Each staged tree and the repository folder its findings are reported under.
TREE_SOURCES = {"shell": QS_DIR, "greeter": GREETER_DIR}
# /usr/bin/qmllint on Arch is the Qt 5 one, which cannot read Qt 6 QML.
QMLLINT_CANDIDATES = ("/usr/lib/qt6/bin/qmllint", "qmllint6", "qmllint")
FALLBACK_QT_QML_DIR = "/usr/lib/qt6/qml"
SOURCE_SUFFIXES = (".qml", ".js", ".mjs")
# How deep under each tree's root qmllint lints: the greeter's own files sit at its top, beside the staged shell copies.
LINT_DEPTH = {"shell": 99, "greeter": 1}
# Each qmllint call stays below this, as find -exec + and xargs keep under ARG_MAX.
MAX_ARGV_BYTES = 128 * 1024

COMPONENT_OPEN = re.compile(r"^    Component \{$")
COMPONENT_CLOSE = re.compile(r"^    \}$")
OPAQUE_STUB = re.compile(rf"^{WS}*Component \{{ isTypeOpaque: true;.*\}}{WS}*$")

# The ids that always fail, the ids that fail unless the message is a known gap, and the rest of the filter: see
# failing_findings.
ALWAYS_FAILING = {
    "syntax", "import", "read-only-property", "required", "non-list-property", "duplicated-name",
    "duplicate-property-binding", "duplicate-inline-component", "duplicate-enum-entries", "alias-cycle",
    "inheritance-cycle", "unresolved-alias", "missing-enum-entry", "var-used-before-declaration",
}
TYPE_FAILING = {"incompatible-type", "uncreatable-type", "unresolved-type", "missing-type"}
QUALIFYING_FIX = re.compile(r"\.$|^pragma ComponentBehavior")
# Members read through parent, Loader.item and the like are typed QObject/QQuickItem, so a miss there is unknowable.
UNTYPED_MISS = re.compile(
    r'not found on type "(QObject|QQuickItem|QJSPrimitiveValue)"|::item with type (QObject|QQuickItem)$|returning QQuickItem$'
)
# Types Quickshell's qmltypes leave unexported or wrongly mark uncreatable; all exist at runtime. Edges and
# PopupAdjustment flags have no type of their own (0.3.2 declares them only as opaque stubs), so an int assigned to one
# reads as incompatible.
TYPE_GAP = re.compile(
    r'^Type PanelWindow is not creatable|^Type margins is used|^Type "BluetoothAdapter" of property'
    r'|^No type found for property "(edges|gravity|adjustment)"|^Cannot assign binding of type int to (Edges|PopupAdjustment)::Flags$'
)


def collate_key(text):
    """The order `sort` and a shell glob give: the locale's collation, ties broken by the bytes as sort does."""
    return (locale.strxfrm(text), text)


def strip_prefix(text, prefix):
    """The shell's ${text#prefix}."""
    return text[len(prefix):] if text.startswith(prefix) else text


def write_out(stream, lines):
    """Writes the lines as UTF-8 whatever the locale, as the shell passed qmllint's bytes through."""
    stream.buffer.write("".join(line + "\n" for line in lines).encode("utf-8", "surrogateescape"))
    stream.flush()


def find_qmllint():
    for candidate in QMLLINT_CANDIDATES:
        path = shutil.which(candidate)
        if path is None:
            continue
        try:
            probe = subprocess.run((path, "--version"), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
        except OSError:
            continue
        if any(line.startswith(b"qmllint 6.") for line in probe.stdout.split(b"\n")):
            return path
    return None


def copy_sources(src, dest):
    """Copies src's tracked and untracked-but-not-ignored QML and JS into dest, keeping symlinks as links."""
    os.makedirs(dest, exist_ok=True)
    listed = subprocess.run(
        ("git", "ls-files", "-co", "--exclude-standard", "-z", "--", src), stdout=subprocess.PIPE, check=True
    ).stdout.decode("utf-8", "surrogateescape")
    for path in listed.split("\0")[:-1]:
        if not path.endswith(SOURCE_SUFFIXES) or not os.path.isfile(path):
            continue
        target = os.path.join(dest, strip_prefix(path, src + "/"))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(path, target, follow_symlinks=False)


def stage_greeter_sources(shell, greeter, entries):
    """Copies the greeter list's QML and JS from the source-only shell copy into the greeter tree, never its fonts or
    the imported skin audio and GoldenEye frames, which can run to hundreds of megabytes. Returns the first entry the
    shell copy lacks, or None."""
    for entry in entries:
        relative = entry.removesuffix("/")
        source = os.path.join(shell, relative)
        target = os.path.join(greeter, relative)
        if not os.path.lexists(source):
            return entry
        if os.path.isdir(source) and not os.path.islink(source):
            shutil.copytree(source, target, symlinks=True, dirs_exist_ok=True)
        else:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(source, target, follow_symlinks=False)
    return None


def type_names(directory):
    """The capitalised .qml names in the folder, which Quickshell registers as its types."""
    try:
        names = os.listdir(directory)
    except OSError:
        return []
    return [name for name in names if "A" <= name[:1] <= "Z" and name.endswith(".qml")]


def type_files(directory):
    """The capitalised .qml files in the folder, in shell glob order."""
    names = [name for name in type_names(directory) if os.path.isfile(os.path.join(directory, name))]
    return [os.path.join(directory, name) for name in sorted(names, key=collate_key)]


def is_singleton(path):
    try:
        return any(line.startswith("pragma Singleton") for line in read_lines(path))
    except OSError:
        return False


def reached_dirs(root):
    """Walks import edges like Quickshell's scanner: shell.qml, then every capitalised .qml file of each reached folder.
    Returns the reached folders, frontier by frontier, each frontier in collation order."""
    reached = [root]
    seen = {root}
    frontier = [root]
    while frontier:
        files = []
        for directory in frontier:
            if directory == root:
                files.append(os.path.join(root, "shell.qml"))
            files.extend(os.path.join(directory, name) for name in type_names(directory))
        targets = {os.path.realpath(target) for path in files for _, target in folder_imports(path, root)}
        frontier = [t for t in sorted(targets, key=collate_key) if os.path.isdir(t) and t not in seen]
        reached.extend(frontier)
        seen.update(frontier)
    return reached


def module_name(directory, root):
    """What `import qs.<path>` names the folder: qs.<path from the tree root>, qs for the root."""
    return "qs" if directory == root else "qs." + strip_prefix(directory, root + "/").replace("/", ".")


def write_qmldirs(reached, root):
    """Writes a qmldir per reached folder as Quickshell does: every capitalised .qml file is a type. A folder without
    one gets none, and an existing qmldir is left alone."""
    for directory in reached:
        qmldir = os.path.join(directory, "qmldir")
        if os.path.exists(qmldir):
            continue
        lines = [f"module {module_name(directory, root)}"]
        for path in type_files(directory):
            name = os.path.basename(path).removesuffix(".qml")
            lines.append(f"{'singleton ' if is_singleton(path) else ''}{name} 1.0 {name}.qml")
        if len(lines) > 1:
            with open(qmldir, "w", encoding="utf-8", errors="surrogateescape") as file:
                file.write("".join(line + "\n" for line in lines))


USE_NAME_LEAD = re.compile(r"^[^A-Za-z_]+")
USE_NAME_PROPERTY = re.compile(rf"^property{WS}+(list{WS}*<{WS}*)?")
USE_NAME_TAIL = re.compile(r"[^A-Za-z0-9_].*$", re.S)


def first_unregistered_use(path, types, singletons):
    """(line number, name) of the file's first instance of, property declared as, or singleton member read from one of
    the types; None when there is none. On a line the three are tried in that order."""
    alternation = "|".join(map(re.escape, types))
    patterns = [
        re.compile(rf"(^|[^.A-Za-z0-9_])({alternation}){WS}*\{{"),
        re.compile(rf"(^|[^A-Za-z0-9_])property{WS}+(list{WS}*<{WS}*)?({alternation})([^A-Za-z0-9_]|$)"),
    ]
    if singletons:
        patterns.append(re.compile(rf"(^|[^.A-Za-z0-9_])({'|'.join(map(re.escape, singletons))}){WS}*\."))
    state = {"in_block": False}
    try:
        lines = read_lines(path)
    except OSError:
        return None
    for number, line in enumerate(lines, 1):
        text = strip_code(line, state)
        for pattern in patterns:
            if match := pattern.search(text):
                name = USE_NAME_LEAD.sub("", match.group(0), count=1)
                name = USE_NAME_PROPERTY.sub("", name, count=1)
                return number, USE_NAME_TAIL.sub("", name, count=1)
    return None


def unregistered_use_message(path, directory, root):
    """The #531 line for the file's first use of a type from the unregistered folder, or None."""
    names = type_names(directory)
    if not names:
        return None
    types = [name.removesuffix(".qml") for name in names]
    singletons = [os.path.basename(p).removesuffix(".qml") for p in type_files(directory) if is_singleton(p)]
    hit = first_unregistered_use(path, types, singletons)
    if hit is None:
        return None
    module = "qs." + strip_prefix(directory, root + "/").replace("/", ".")
    return (
        f"{strip_prefix(path, root + '/')}:{hit[0]}: {hit[1]} will not resolve at runtime: nothing reached from shell.qml "
        f"imports {module}, so Quickshell will not register its types; import {module} from a file Quickshell reaches "
        f"from shell.qml (for example the one that loads {os.path.basename(path)}) (#531)"
    )


def unregistered_messages(root, reached):
    """Flags files outside the registered folders that use their siblings, or an unregistered folder imported without
    "as". An import repeated, or of the file's own folder, is reported each time."""
    registered = set(reached)
    holders = set()
    for directory, dirnames, filenames in os.walk(root):
        if any(name.endswith(".qml") for name in dirnames + filenames):
            holders.add(directory)
    messages = []
    for directory in sorted(holders - registered, key=collate_key):
        names = [n for n in os.listdir(directory) if n.endswith(".qml") and not n.startswith(".")]
        for name in sorted(names, key=collate_key):
            path = os.path.join(directory, name)
            messages.append(unregistered_use_message(path, directory, root))
            for alias, target in folder_imports(path, root):
                target = os.path.realpath(target)
                if alias is None and os.path.isdir(target) and target not in registered:
                    messages.append(unregistered_use_message(path, target, root))
    return [message for message in messages if message is not None]


def qt_qml_dirs(qmllint):
    """Where Qt's QML modules may be: what the qtpaths6 beside qmllint says, then Arch's path."""
    dirs = []
    try:
        query = subprocess.run(
            (os.path.join(os.path.dirname(qmllint), "qtpaths6"), "--query", "QT_INSTALL_QML"),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        dirs = query.stdout.decode("utf-8", "surrogateescape").split()
    except OSError:
        pass
    return dirs + [FALLBACK_QT_QML_DIR]


def prune_qmltypes(module_copy):
    """Quickshell 0.3.2 gives each module one-line opaque stubs (no members) for types another module defines, and
    qmllint resolves a name to whichever stub it meets first, so every member of QuickshellScreenInfo, ObjectModel or
    Anchors reads as missing. Drops each stub whose type a multi-line, non-opaque Component defines somewhere in the
    copy; some types (QList<NMSettings*> and the like) are declared nowhere but in their stub, so those stay."""
    types_files = sorted(
        os.path.join(directory, name)
        for directory, _, names in os.walk(module_copy)
        for name in names
        if name.endswith(".qmltypes")
    )
    concrete = set()
    in_component = opaque = False
    name = ""
    for path in types_files:
        for line in read_lines(path):
            if COMPONENT_OPEN.match(line):
                in_component, opaque, name = True, False, ""
                continue
            if not in_component:
                continue
            if line.startswith("        isTypeOpaque: true"):
                opaque = True
            if line.startswith('        name: "'):
                name = line.split('"', 2)[1]
            if COMPONENT_CLOSE.match(line):
                if not opaque and name:
                    concrete.add(name)
                in_component = False
    for path in types_files:
        kept = []
        for line in read_lines(path):
            if OPAQUE_STUB.match(line):
                stub_name = re.sub(r'.*name: "', "", line, count=1, flags=re.S).split('"', 1)[0]
                if stub_name in concrete:
                    continue
            kept.append(line)
        with open(path, "w", encoding="utf-8", errors="surrogateescape") as file:
            file.write("".join(line + "\n" for line in kept))


def stage_quickshell_module(stage, qmllint):
    """A copy of the installed Quickshell module without the stubs, and the Qt QML dir it came from; (None, None) when
    Qt has no Quickshell module. The copy only wins under --bare, which drops the default import paths so it can be
    listed ahead of the system one."""
    for qt_dir in qt_qml_dirs(qmllint):
        installed = os.path.join(qt_dir, "Quickshell")
        if os.path.isdir(installed):
            module_copy = os.path.join(stage, "qml")
            shutil.copytree(installed, os.path.join(module_copy, "Quickshell"), symlinks=True, dirs_exist_ok=True)
            prune_qmltypes(module_copy)
            return module_copy, qt_dir
    return None, None


def walk_paths(top, max_depth):
    """Every path under top down to max_depth, in find's order (without following symlinked folders)."""
    stack = [(top, 0)]
    while stack:
        directory, depth = stack.pop()
        try:
            entries = list(os.scandir(directory))
        except OSError:
            continue
        for entry in entries:
            yield entry.path, entry.name
        if depth + 1 < max_depth:
            stack.extend((e.path, depth + 1) for e in reversed(entries) if e.is_dir(follow_symlinks=False))


def lint_files(tree, depth):
    """The paths qmllint lints, in C order (qmllint reports files in the order it is given them)."""
    return sorted(path for path, name in walk_paths(tree, depth) if name.endswith(SOURCE_SUFFIXES))


def argv_chunks(command, files):
    """command plus files, split as find -exec + does so no call exceeds the argument limit."""
    limit = MAX_ARGV_BYTES - sum(len(arg) + 1 for arg in command)
    chunk, size = [], 0
    for path in files:
        if chunk and size + len(path) + 1 > limit:
            yield [*command, *chunk]
            chunk, size = [], 0
        chunk.append(path)
        size += len(path) + 1
    if chunk:
        yield [*command, *chunk]


def run_qmllint(qmllint, stage, tree, module_copy, qt_dir, files):
    """qmllint's JSON over the tree's files, one document per call, concatenated; its stderr is dropped."""
    tree_dir = os.path.join(stage, tree)
    command = [qmllint, "--ignore-settings", "--json", "-", "-I", os.path.join(stage, tree + "_root")]
    if module_copy is not None:
        command += ["--bare", "-I", module_copy, "-I", qt_dir]
    # Qt 6.12 imports only the qmldirs named with -i (one flag each, absolute like the linted files so the two paths
    # compare equal), not the one beside the linted file.
    for path, name in sorted(walk_paths(tree_dir, sys.maxsize)):
        if name == "qmldir":
            command += ["-i", path]
    report = b""
    for argv in argv_chunks(command, files):
        report += subprocess.run(argv, cwd=tree_dir, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False).stdout
    return report


def parse_documents(report):
    """The JSON documents in the report, back to back as `jq -s` reads them; None when any is malformed or has no
    files list."""
    text = report.decode("utf-8", "replace")
    decoder = json.JSONDecoder()
    documents = []
    position = 0
    while True:
        while position < len(text) and text[position] in " \t\n\r":
            position += 1
        if position == len(text):
            break
        try:
            document, position = decoder.raw_decode(text, position)
        except json.JSONDecodeError:
            return None
        if not isinstance(document, dict) or not isinstance(document.get("files"), list):
            return None
        documents.append(document)
    return documents


def jq_text(value):
    """value as jq's string interpolation writes it."""
    if isinstance(value, str):
        return value
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "null"
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def listed(value):
    """jq's `(value // [])[]` for a list or a missing value."""
    return value or []


def qualifies(suggestion):
    """A fix that qualifies the name (ends in a dot, or adds the ComponentBehavior pragma): not a missing name."""
    replacements = [] if suggestion.get("replacement") in (None, False) else [suggestion["replacement"]]
    replacements += [edit.get("replacement") for edit in listed(suggestion.get("documentEdits"))]
    return any(QUALIFYING_FIX.search(replacement) for replacement in replacements)


def is_failing(warning):
    warning_id = warning.get("id")
    if not isinstance(warning_id, str):
        return False
    if warning_id in ALWAYS_FAILING:
        return True
    if warning_id in TYPE_FAILING and not TYPE_GAP.search(warning.get("message")):
        return True
    if warning_id == "missing-property" and not UNTYPED_MISS.search(warning.get("message")):
        return True
    return (
        warning_id == "unqualified"
        and warning.get("message") == "Unqualified access"
        and not any(qualifies(s) for s in listed(warning.get("suggestions")))
    )


class ReportShapeError(Exception):
    """The report has a shape the filter cannot read (a missing warnings list, a message that is no string), at the
    same points the jq filter qml.sh used stopped; findings holds what came before it."""

    def __init__(self, findings, error):
        super().__init__(error)
        self.findings = findings


def failing_findings(documents):
    """`<file>:<line>:<column>: <message>[ Did you mean ...] [<id>]` for each finding that is a real error. Raises
    ReportShapeError on a shape it cannot read."""
    findings = []
    try:
        for document in documents:
            for file in document["files"]:
                for warning in file["warnings"]:
                    if not is_failing(warning):
                        continue
                    hints = [s.get("message") for s in listed(warning.get("suggestions"))]
                    hint = next((" " + h for h in hints if h.startswith("Did you mean")), "")
                    findings.append(
                        f"{jq_text(file.get('filename'))}:{jq_text(warning.get('line'))}:"
                        f"{jq_text(warning.get('column'))}: {jq_text(warning.get('message'))}{hint} "
                        f"[{jq_text(warning.get('id'))}]"
                    )
    except (KeyError, TypeError, AttributeError) as error:
        raise ReportShapeError(findings, error) from error
    return findings


def relabel(line, stage_tree, prefix):
    """A finding's line with the stage path replaced by the repository one."""
    if line.startswith("./"):
        line = prefix + "/" + line[2:]
    return line.replace(stage_tree, prefix)


def lint_tree(qmllint, stage, tree, reached, module_copy, qt_dir):
    """Lints one staged tree, printing its findings to stderr; returns whether it passed."""
    tree_dir = os.path.join(stage, tree)
    prefix = TREE_SOURCES[tree]
    passed = True
    unregistered = unregistered_messages(tree_dir, reached)
    if unregistered:
        write_out(sys.stderr, [prefix + "/" + line for line in unregistered])
        passed = False
    files = lint_files(tree_dir, LINT_DEPTH[tree])
    report = run_qmllint(qmllint, stage, tree, module_copy, qt_dir, files)
    with open(os.path.join(stage, tree + ".json"), "wb") as file:
        file.write(report)
    documents = parse_documents(report)
    linted = 0 if documents is None else sum(len(document["files"]) for document in documents)
    if linted != len(files):
        write_out(sys.stderr, [f"qmllint: linted {linted} of {len(files)} files in {prefix}"])
        return False
    try:
        findings = failing_findings(documents or [])
    except ReportShapeError as error:
        # Reported, but not a failure in itself: a known gap (see the module docstring).
        write_out(sys.stderr, [f"qmllint: unexpected report shape in {prefix}: {error}"])
        findings = error.findings
    findings = "\n".join(findings).rstrip("\n")
    if findings:
        write_out(sys.stderr, [relabel(line, tree_dir, prefix) for line in findings.split("\n")])
        passed = False
    return passed


def lint_stage(stage, qmllint):
    """Stages both trees in stage and lints them; returns the exit status."""
    shell = os.path.join(stage, "shell")
    greeter = os.path.join(stage, "greeter")
    copy_sources(QS_DIR, shell)
    copy_sources(GREETER_DIR, greeter)
    missing = stage_greeter_sources(shell, greeter, greeter_entries(REPO_DIR))
    if missing is not None:
        write_out(sys.stderr, [f"qmllint: {missing} from {GREETER_LIST} is missing in {QS_DIR}"])
        return 1
    module_copy, qt_dir = stage_quickshell_module(stage, qmllint)
    reached = {}
    for tree in TREE_SOURCES:
        tree_dir = os.path.join(stage, tree)
        reached[tree] = reached_dirs(tree_dir)
        with open(os.path.join(stage, tree + ".reached"), "w", encoding="utf-8", errors="surrogateescape") as file:
            file.write("".join(directory + "\n" for directory in reached[tree]))
        write_qmldirs(reached[tree], tree_dir)
        # `import qs` needs a module root holding a qs link to the tree.
        os.makedirs(os.path.join(stage, tree + "_root"), exist_ok=True)
        os.symlink(tree_dir, os.path.join(stage, tree + "_root", "qs"))
    status = 0
    for tree in TREE_SOURCES:
        if not lint_tree(qmllint, stage, tree, reached[tree], module_copy, qt_dir):
            status = 1
    return status


def main(argv):
    keep_stage = None
    if argv[:1] == ["--keep-stage"] and len(argv) == 2:
        keep_stage = os.path.abspath(argv[1])
    elif argv:
        print("usage: lib/check/steps/qml.py [--keep-stage DIR]", file=sys.stderr)
        return 2
    try:
        locale.setlocale(locale.LC_COLLATE, "")
    except locale.Error:
        # A locale the environment names but the host lacks: the shell warned and sorted in C order, so do the same.
        pass
    os.chdir(REPO_DIR)
    qmllint = find_qmllint()
    if qmllint is None:
        write_out(sys.stdout, ["skip: qmllint (Qt 6, qt6-declarative) not installed"])
        return 0

    def end_on_signal(signum, frame):
        raise SystemExit(1)

    for signum in (signal.SIGINT, signal.SIGTERM):
        # A signal ignored when the step started stays ignored, as a shell trap leaves it.
        if signal.getsignal(signum) is not signal.SIG_IGN:
            signal.signal(signum, end_on_signal)
    with tempfile.TemporaryDirectory() as stage:
        stage = os.path.realpath(stage)
        try:
            return lint_stage(stage, qmllint)
        finally:
            if keep_stage is not None:
                shutil.copytree(stage, keep_stage, symlinks=True)
                # The module-root links point into the stage, which is deleted next.
                for tree in TREE_SOURCES:
                    link = os.path.join(keep_stage, tree + "_root", "qs")
                    if os.path.islink(link):
                        os.remove(link)
                        os.symlink(os.path.join(keep_stage, tree), link)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
