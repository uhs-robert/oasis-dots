#!/usr/bin/env python3
"""Checks the file paths the Quickshell config builds as strings, which qmllint cannot see.

qmllint follows `import` lines and type names only, so moving a file that `Qt.resolvedUrl("modules/" + spec.file)`,
`Quickshell.shellDir + "/scripts/x"` or a `.js` file's `.import` names passes it and then fails at runtime. This step
reads the working tree (tracked and untracked-but-not-ignored files, as git lists them) and checks, in the shell tree
and in the greeter tree (the greeter's own files plus the Quickshell files lib/common/greeter-files.sh stages):

  - a literal path (`Qt.resolvedUrl("x")`, `Quickshell.shellDir + "/x"`, `shellPath("x")`, and a bare relative string on
    `source:` or `fragmentShader:` in QML) names an existing file or folder;
  - a path with a dynamic tail either has a TABLES rule, which enumerates the table in the repo it is drawn from and
    checks every file, or gets a prefix check: the folder exists and holds an entry starting with the literal head;
  - every quoted or `qs.` import, and every JS `.import`, resolves;
  - each OUTSIDE_REFS consumer still names an existing Quickshell path.

A missing target passes when git ignores it and its parent folder holds files (generated or imported state such as
theme/theme.json or a skin's audio/), or when its line carries `// qs-path: optional <reason>`. A use of
`Qt.resolvedUrl`, `shellDir` or `shellPath` the scanner cannot classify fails unless its line carries
`// qs-path: skip <reason>`; that is what stops a new pattern from passing unchecked.

  python3 -B lib/check/steps/qml_paths.py
"""

import os
import posixpath
import re
import subprocess
import sys
from typing import Callable, NamedTuple

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from qml_imports import GREETER_LIST, WS, greeter_list, imports, read_lines, staged_files, strip_code  # noqa: E402

REPO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
QS_DIR = "home/quickshell/.config/quickshell"
GREETER_DIR = "system/etc/greetd/quickshell"
SOURCE_SUFFIXES = (".qml", ".js", ".mjs")


# --- Rule data -------------------------------------------------------------------------------------------------------

def key_values(key):
    """Extractor: the string after `key:` wherever it appears."""
    pattern = re.compile(rf'\b{key}:{WS}*"([^"]*)"')
    return lambda lines: [(m.group(1), n) for n, line in lines for m in pattern.finditer(line)]


def array_values(name, capitalise=False):
    """Extractor: the strings of the array on the line declaring `name`, empty ones dropped."""
    declaration = re.compile(rf"\b{name}\b[^\[\n]*\[(.*?)\]")
    return lambda lines: [
        (value[:1].upper() + value[1:] if capitalise else value, n)
        for n, line in lines if (m := declaration.search(line))
        for value in re.findall(r'"([^"]*)"', m.group(1)) if value
    ]


def view_files(lines):
    """Extractor for a popup's per-layout views: each `prefix: "P", views: ["A", ...]` gives PA, and the second
    argument of each view_url(view, shared) call is a file as is."""
    found = []
    for n, line in lines:
        if m := re.search(r'prefix: "([^"]+)", views: \[(.*?)\]', line):
            found += [(m.group(1) + view, n) for view in re.findall(r'"([^"]+)"', m.group(2))]
        found += [(m.group(1), n) for m in re.finditer(r'view_url\("[^"]+", "([^"]+)"\)', line)]
    return found


def weather_slugs(lines):
    """Extractor for WeatherState.asset_url: its literal calls and the values of moon_icon_slugs."""
    found = []
    in_moon = False
    for n, line in lines:
        found += [(m.group(1), n) for m in re.finditer(r'asset_url\("([^"]+)"\)', line)]
        if "moon_icon_slugs: ({" in line:
            in_moon = True
        elif in_moon and line.strip().startswith("})"):
            in_moon = False
        elif in_moon:
            found += [(m.group(1), n) for m in re.finditer(r':\s*"([^"]+)"', line)]
    return found


class Table(NamedTuple):
    consumer: str  # Quickshell-relative file holding the call
    head: str  # the call's literal head, or its whole argument when that starts with no literal
    source: str  # Quickshell-relative file holding the table
    extract: Callable  # (lines of the source as (number, text)) -> [(value, line)]


PICKER_PARTS = ("cursors", "targets", "loupe")
TABLES = [
    Table("bar/Bar.qml", "modules/", "services/BarModules.js", key_values("file")),
    Table("settings/SettingsPopup.qml", "section.source", "settings/Sections.js", key_values("source")),
    Table("popups/WeatherPopup.qml", "weather/", "popups/WeatherPopup.qml", view_files),
    Table("popups/KeeptabsPopup.qml", "keeptabs/", "popups/KeeptabsPopup.qml", view_files),
    Table("theme/Style.qml", "styles/", "theme/styles/index.js", array_values("sources")),
    Table("components/ControllerBadge.qml", "KeyHints.button_path(root.controller)", "components/KeyHints.js", key_values("button")),
    Table("services/WeatherState.qml", "../assets/weather/", "services/WeatherState.qml", weather_slugs),
    Table("lock/skins/goldeneye/GoldeneyeAudio.qml", "fx/", "lock/skins/goldeneye/GoldeneyeAudio.qml", array_values("shipped")),
    Table("lock/skins/mgs2/Mgs2Audio.qml", "fx/", "lock/skins/mgs2/Mgs2Audio.qml", array_values("shipped")),
] + [
    Table(consumer, head, "theme/Style.qml", array_values("picker_skins", capitalise=True))
    for consumer, head in [
        ("components/ZoomReticle.qml", "picker/cursors/"),
        ("components/ClickHintsOverlay.qml", "picker/cursors/"),
        ("components/RegionSelector.qml", "picker/targets/"),
        ("components/RegionSelector.qml", "picker/cursors/"),
        ("components/picker/Loupe.qml", "loupe/"),
    ]
]

# Files outside the Quickshell tree that name a path in it: (consumer, the Quickshell-relative path it must still
# mention). The consumer is checked for the text, so a rename on either side fails. Each consumer has a PATH_SCOPES
# entry reaching the qml scope.
OUTSIDE_REFS = [
    ("home/hypr/.config/hypr/scripts/lock-screen.sh", "scripts/lock-flag"),
    ("home/voxcmd/.local/bin/voxcmd-alarm", "sounds/alarm.ogg"),
    ("home/voxcmd/tests/run-monitors.sh", "overview/Voice.js"),
    ("home/quickshell/tests/notification_markup.js", "services/NotificationMarkup.js"),
]

# A relative string on these QML keys is a path; other keys hold prose, glyphs or SVG data.
BARE_PATH_KEYS = re.compile(rf'\b(?:source|fragmentShader){WS}*:{WS}*"([^"]+)"')
URL_SCHEME = re.compile(r"^(/|[A-Za-z][A-Za-z0-9+.-]*:)")
CALL_SITE = re.compile(r"Qt\.resolvedUrl\(|Quickshell\.shellPath\(|\bshellDir\b")
MARKER = re.compile(r"//{}*qs-path:{}*(optional|skip){}+\S".format(WS, WS, WS))


class Finding(NamedTuple):
    path: str
    line: int
    message: str


# --- Reading call sites ------------------------------------------------------------------------------------------------

def split_terms(text, i=0):
    """Reads `a + b + c` from text[i:], each term a ("lit", value) string or a ("dyn", source). Stops at the first
    character that cannot continue the sum (a closing bracket, comma, `?`, ...) and returns (terms, end)."""
    terms = []
    stops = ",;?:|&=<>!)]}"
    while True:
        while i < len(text) and text[i] in " \t\n":
            i += 1
        if i < len(text) and text[i] in "\"'":
            quote, value = text[i], []
            i += 1
            while i < len(text) and text[i] != quote:
                if text[i] == "\\":
                    i += 1
                value.append(text[i:i + 1])
                i += 1
            i += 1
            terms.append(("lit", "".join(value)))
        else:
            start, depth, inner_quote = i, 0, ""
            while i < len(text):
                c = text[i]
                if inner_quote:
                    if c == "\\":
                        i += 1
                    elif c == inner_quote:
                        inner_quote = ""
                elif c in "\"'`":
                    inner_quote = c
                elif c in "([{":
                    depth += 1
                elif c in ")]}" and depth > 0:
                    depth -= 1
                elif depth == 0 and (c == "+" or c in stops):
                    break
                i += 1
            if text[start:i].strip() == "":
                return terms, start
            terms.append(("dyn", text[start:i].strip()))
        while i < len(text) and text[i] in " \t\n":
            i += 1
        if text[i:i + 1] == "+" and text[i + 1:i + 2] != "+":
            i += 1
        else:
            return terms, i


def balanced_argument(text, start):
    """The text from start up to the parenthesis closing the call whose `(` precedes it, or None when it never closes."""
    depth, i, quote = 1, start, ""
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = ""
        elif c in "\"'`":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[start:i]
        i += 1
    return None


class Site(NamedTuple):
    line: int
    marker: str  # "optional", "skip" or ""
    from_root: bool  # shellDir and shellPath resolve against the config root, resolvedUrl against the file
    terms: list  # None when the use cannot be classified
    argument: str  # the call's whole argument as written, '' for shellDir


def call_sites(path, qml_file):
    """The path-building uses in a file: Qt.resolvedUrl, shellPath, shellDir and, in QML, bare relative strings."""
    raw = read_lines(path)
    state = {"in_block": False}
    code = [strip_code(line, state, keep_strings=True) for line in raw]
    sites = []
    for number, line in enumerate(code):
        marker = (MARKER.search(raw[number]) or [None, ""])[1]
        window = "\n".join(code[number:number + 3])
        for match in CALL_SITE.finditer(line):
            if match.group().endswith("("):
                argument = balanced_argument(window, match.end())
                terms = None
                if argument is not None:
                    terms, end = split_terms(argument)
                    if argument[end:].strip():
                        terms = None
                sites.append(Site(number + 1, marker, "resolvedUrl" not in match.group(), terms, (argument or "").strip()))
            else:
                after = window[match.end():].lstrip(" \t")
                terms = None
                if after.startswith("+"):
                    terms, _ = split_terms(window, match.end() + len(window[match.end():]) - len(after) + 1)
                    if not terms or terms[0][0] != "lit":
                        terms = None
                sites.append(Site(number + 1, marker, True, terms, ""))
        if qml_file:
            for match in BARE_PATH_KEYS.finditer(line):
                if not URL_SCHEME.match(match.group(1)):
                    sites.append(Site(number + 1, marker, False, [("lit", match.group(1))], ""))
    return sites


# --- The trees paths resolve in -----------------------------------------------------------------------------------------

def norm(path):
    path = posixpath.normpath(path)
    return "" if path == "." else path


class Tree:
    """A set of files by tree-relative path, where each came from in the repository, and what git ignores."""

    def __init__(self, name, origins, ignore_roots, ignored):
        self.name = name
        self.origins = origins
        self.ignore_roots = ignore_roots
        self.ignored = ignored
        self.dirs = {""}
        self.children = {}
        for path in origins:
            while path:
                parent = posixpath.dirname(path)
                self.children.setdefault(parent, set()).add(posixpath.basename(path))
                self.dirs.add(parent)
                path = parent

    def exists(self, path):
        return path in self.origins or path in self.dirs

    def is_generated(self, path):
        """True for a missing path git ignores below a folder that holds files: generated or imported state. The first
        missing component must be the ignored one, so a moved parent folder is not excused by its children's patterns."""
        parts = path.split("/")
        if ".." in parts:
            return False
        folder = ""
        for part in parts:
            candidate = posixpath.join(folder, part)
            if candidate not in self.dirs:
                return any(self.ignored(root + "/" + candidate) for root in self.ignore_roots)
            folder = candidate
        return False


def git_listing(repo, pathspecs):
    out = subprocess.run(
        ("git", "ls-files", "-co", "--exclude-standard", "-z", "--", *pathspecs),
        cwd=repo, stdout=subprocess.PIPE, check=True,
    ).stdout.decode("utf-8", "surrogateescape")
    return set(out.split("\0")[:-1])


def make_ignored(repo):
    """A cached predicate on repository paths. A folder-only ignore pattern matches only the path with a trailing slash
    when nothing exists there (a clean checkout), so both spellings are asked."""
    cache = {}

    def ignored(path):
        if path not in cache:
            cache[path] = bool(subprocess.run(
                ("git", "check-ignore", "--", path, path + "/"), cwd=repo, stdout=subprocess.PIPE
            ).stdout.strip())
        return cache[path]

    return ignored


class Layout(NamedTuple):
    qs_dir: str = QS_DIR
    greeter_dir: str = GREETER_DIR
    tables: list = TABLES
    outside_refs: list = OUTSIDE_REFS
    greeter_entries: list = None  # None reads lib/common/greeter-files.sh


def build_trees(repo, layout, listing, ignored):
    """The shell tree and the greeter tree (its own files over the staged Quickshell ones), plus the greeter list's
    entries that match nothing."""
    qs_prefix = layout.qs_dir + "/"
    greeter_prefix = layout.greeter_dir + "/"
    qs_files = {path.removeprefix(qs_prefix): path for path in listing if path.startswith(qs_prefix)}
    entries = layout.greeter_entries if layout.greeter_entries is not None else greeter_list(repo)
    staged, unmatched = staged_files(set(qs_files), entries)
    greeter_origins = {path: qs_files[path] for path in staged}
    greeter_origins.update({path.removeprefix(greeter_prefix): path for path in listing if path.startswith(greeter_prefix)})
    shell = Tree("shell", qs_files, [layout.qs_dir], ignored)
    greeter = Tree("greeter", greeter_origins, [layout.greeter_dir, layout.qs_dir], ignored)
    return shell, greeter, unmatched


# --- Checks -----------------------------------------------------------------------------------------------------------

def table_values(repo, layout, rule):
    path = os.path.join(repo, layout.qs_dir, rule.source)
    try:
        state = {"in_block": False}
        lines = [(n, strip_code(line, state, keep_strings=True)) for n, line in enumerate(read_lines(path), 1)]
    except OSError:
        return []
    return rule.extract(lines)


def check_site(repo, layout, tree, consumer, origin, site):
    """The findings for one call site, resolved in one tree."""
    unrecognised = Finding(origin, site.line, 'unrecognised path expression; add a TABLES rule or a "// qs-path: skip <reason>" marker')
    if site.marker == "skip":
        return []
    if site.terms is None:
        return [unrecognised]
    base = "" if site.from_root else posixpath.dirname(consumer)
    leading = []
    for kind, value in site.terms:
        if kind != "lit":
            break
        leading.append(value)
    prefix = "".join(leading)
    all_literal = len(leading) == len(site.terms)

    def missing(path, note=""):
        if tree.exists(path) or site.marker == "optional" or tree.is_generated(path):
            return []
        return [Finding(origin, site.line, f"{path or '.'}{note} does not exist" + ("" if tree.name == "shell" else " in the greeter tree"))]

    def resolve(text):
        return norm(text.lstrip("/") if site.from_root else posixpath.join(base, text))

    if all_literal:
        return missing(resolve(prefix))
    rule = next((r for r in layout.tables if r.consumer == consumer and r.head == (prefix if leading else site.argument)), None)
    suffix = site.terms[-1][1] if site.terms[-1][0] == "lit" else ""
    if rule is not None:
        values = table_values(repo, layout, rule)
        if not values:
            return [Finding(origin, site.line, f"no values found in {layout.qs_dir}/{rule.source} for its TABLES rule")]
        found = []
        for value, line in values:
            found += missing(resolve(prefix + value + suffix), f" (from {layout.qs_dir}/{rule.source}:{line})")
        return found
    if not leading:
        return [unrecognised]
    # Prefix check: the folder exists and holds an entry shaped like the head.
    full = posixpath.join(base, prefix) if not site.from_root else prefix.lstrip("/")
    folder = norm(full) if prefix.endswith("/") else norm(posixpath.dirname(full))
    leaf = "" if prefix.endswith("/") else posixpath.basename(full)
    if folder not in tree.dirs:
        return missing(folder)
    if site.marker == "optional" or any(
        name.startswith(leaf) and name.endswith(suffix) for name in tree.children.get(folder, ())
    ):
        return []
    return [Finding(origin, site.line, f'nothing in {folder or "."}/ starts with "{leaf}"' + (f' and ends with "{suffix}"' if suffix else ""))]


def check_imports(tree, repo, consumer, origin):
    """The findings for the imports of one file, resolved in one tree."""
    found = []
    suffix = ""
    if tree.name == "greeter":
        suffix = " (greeter tree)" if origin.startswith(GREETER_DIR + "/") else " (greeter tree; see " + GREETER_LIST + ")"
    for kind, target, line in imports(os.path.join(repo, origin)):
        if kind == "qs":
            path, text = target, "qs" + ("." + target.replace("/", ".") if target else "")
            ok = path in tree.dirs
        else:
            path, text = norm(posixpath.join(posixpath.dirname(consumer), target)), f'"{target}"'
            ok = tree.exists(path)
        if not ok:
            found.append(Finding(origin, line, f"import {text} does not resolve{suffix}"))
    return found


def check_outside(repo, layout, listing, shell):
    found = []
    for consumer, target in layout.outside_refs:
        if not shell.exists(target):
            found.append(Finding(consumer, 1, f"names {target}, which is not in {layout.qs_dir}"))
            continue
        try:
            with open(os.path.join(repo, consumer), encoding="utf-8", errors="surrogateescape") as file:
                text = file.read()
        except OSError:
            text = None
        if consumer not in listing or text is None:
            found.append(Finding(consumer, 1, "listed in OUTSIDE_REFS in lib/check/steps/qml_paths.py but not a file"))
        elif target not in text:
            found.append(Finding(consumer, 1, f"no longer mentions {target}; update OUTSIDE_REFS in lib/check/steps/qml_paths.py"))
    return found


def run_checks(repo, layout=Layout()):
    """Every finding for the checkout at repo, sorted."""
    listing = git_listing(repo, [layout.qs_dir, layout.greeter_dir] + [consumer for consumer, _ in layout.outside_refs])
    shell, greeter, unmatched = build_trees(repo, layout, listing, make_ignored(repo))
    findings = [Finding(GREETER_LIST, 1, f"{entry} matches nothing in {layout.qs_dir}") for entry in unmatched]
    for tree in (shell, greeter):
        for consumer, origin in sorted(tree.origins.items()):
            if not consumer.endswith(SOURCE_SUFFIXES):
                continue
            for site in call_sites(os.path.join(repo, origin), consumer.endswith(".qml")):
                findings += check_site(repo, layout, tree, consumer, origin, site)
            findings += check_imports(tree, repo, consumer, origin)
    findings += check_outside(repo, layout, listing, shell)
    return sorted(set(findings))


def main(argv):
    if argv:
        print("usage: lib/check/steps/qml_paths.py", file=sys.stderr)
        return 2
    findings = run_checks(REPO_DIR)
    for finding in findings:
        print(f"{finding.path}:{finding.line}: {finding.message}", file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
