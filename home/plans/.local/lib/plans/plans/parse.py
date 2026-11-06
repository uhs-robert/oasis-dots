"""Plan docs: the front matter subset and the body sections, read into a Doc.

The front matter is a strict subset of YAML: flat `key: value` lines, `[a, b]` lists and double-quoted strings. A bare
value that YAML reads as a bool, null, float or date is refused, so what this parser reads (an int or a string) is what
any YAML parser reads.
"""

import os
import re

KEY_ORDER = ("id", "project", "kind", "status", "owner_session", "rank", "depends_on", "waiting_on", "issue", "pr", "branch", "fix_rounds", "updated")
LIST_KEYS = ("depends_on",)
INTEGER_KEYS = ("rank", "fix_rounds")
# A doc may leave these keys out, and then holds this value. fix_rounds came after the first docs were written.
DEFAULTS = {"fix_rounds": 0}
SECTIONS = ("Goal", "Decisions", "Plan", "Open questions", "Owner checks")
# A body edit counts as a change to this pseudo-key (store.update compares it like any other key).
BODY = "body"

KEY_LINE = re.compile(r"([a-z_][a-z0-9_]*): (.*)")
QUOTED = re.compile(r'"((?:[^"\\]|\\["\\])*)"')
INTEGER = re.compile(r"0|[1-9][0-9]*")
# Bare words that YAML 1.1 or 1.2 reads as something other than a string or an int.
YAML_TYPED = re.compile(
    r"(?i:true|false|yes|no|on|off|y|n|null|~)"
    r"|[-+]?(\.[0-9]+|[0-9]+\.[0-9]*|[0-9]+(\.[0-9]*)?[eE][-+]?[0-9]+)"
    r"|[-+]?\.(?i:inf|nan)|0[0-9xob].*|[-+][0-9]+|[0-9]+(:[0-9]+)+"
    r"|[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}.*"
)
BARE_START_FORBIDDEN = set("-?:,[]{}#&*!|>'\"%@`")
BARE_FORBIDDEN = set('"[]{}\t\r\n')
HEADING = re.compile(r"(#{1,2}) +(.*?) *$")
FENCE = re.compile(r" {0,3}(```|~~~)")


class ParseError(Exception):
    def __init__(self, path, errors):
        self.path = path
        self.errors = errors
        super().__init__(f"{path}: " + "; ".join(f"line {line}: {message}" for line, message in errors))


class Doc:
    """One plan doc as read. `keys` maps each front matter key to an int, a string or a list of strings, in file order.
    `errors` holds (line, message) for every line outside the subset. store never writes a doc with errors."""

    def __init__(self, path, text):
        self.path = path
        self.text = text
        self.keys = {}
        self.key_lines = {}
        self.errors = []
        # Set when the file could not be read at all: the cause, as the CLI and the board print it.
        self.unread_cause = None
        self.head_lines = []
        self.body = ""
        self.body_first_line = 1
        self._parse()

    @property
    def file_id(self):
        return os.path.splitext(os.path.basename(self.path))[0]

    @property
    def id(self):
        return self.keys.get("id", self.file_id)

    def value(self, key):
        return self.body if key == BODY else self.keys.get(key)

    def _parse(self):
        lines = self.text.splitlines(keepends=True)
        if not lines or lines[0].rstrip("\n") != "---":
            self.errors.append((1, "no front matter: the file must start with a --- line"))
            self.body = self.text
            return
        close = next((i for i in range(1, len(lines)) if lines[i].rstrip("\n") == "---"), None)
        if close is None:
            self.errors.append((1, "the front matter has no closing --- line"))
            self.body = self.text
            return
        self.head_lines = lines[1:close]
        self.body = "".join(lines[close + 1:])
        self.body_first_line = close + 2
        for index, line in enumerate(self.head_lines):
            self._parse_key_line(index, line.rstrip("\n"))

    def _parse_key_line(self, index, line):
        line_no = index + 2
        match = KEY_LINE.fullmatch(line)
        if not match:
            self.errors.append((line_no, f"not a `key: value` line: {line!r}"))
            return
        key, raw = match.groups()
        if key in self.keys:
            self.errors.append((line_no, f"duplicate key {key}"))
            return
        try:
            self.keys[key] = parse_value(raw)
        except ValueError as error:
            self.errors.append((line_no, f"{key}: {error}"))
            return
        self.key_lines[key] = index

    def sections(self):
        """Each `## ` section of the body, in order: title -> (first file line of its content, content text). Headings
        inside code fences do not count, and a `# ` heading ends a section."""
        found = {}
        title, start, content = None, 0, []
        in_fence = False
        for offset, line in enumerate(self.body.splitlines(keepends=True)):
            if FENCE.match(line):
                in_fence = not in_fence
            heading = None if in_fence else HEADING.fullmatch(line.rstrip("\n"))
            if heading:
                if title is not None and title not in found:
                    found[title] = (start, "".join(content))
                title = heading.group(2) if heading.group(1) == "##" else None
                start, content = self.body_first_line + offset + 1, []
            elif title is not None:
                content.append(line)
        if title is not None and title not in found:
            found[title] = (start, "".join(content))
        return found

    def render(self, changes):
        """The file text with `changes` (key -> value, BODY for the body) applied. Only the changed front matter lines
        change. A new key goes at the end of the front matter, and the body keeps its bytes unless BODY changes."""
        head = list(self.head_lines)
        for key, value in changes.items():
            if key == BODY:
                continue
            line = f"{key}: {format_value(value)}\n"
            if key in self.key_lines:
                head[self.key_lines[key]] = line
            else:
                head.append(line)
        body = changes.get(BODY, self.body)
        return "---\n" + "".join(head) + "---\n" + body


def parse_value(raw):
    if raw.startswith("["):
        return parse_list(raw)
    return parse_scalar(raw, in_list=False)


def parse_scalar(raw, in_list):
    if raw.startswith('"'):
        match = QUOTED.fullmatch(raw)
        if not match:
            raise ValueError(f"bad double-quoted string {raw!r} (only \\\" and \\\\ escapes)")
        return re.sub(r"\\(.)", r"\1", match.group(1))
    problem = bare_problem(raw, in_list)
    if problem:
        raise ValueError(problem)
    return int(raw) if INTEGER.fullmatch(raw) else raw


def parse_list(raw):
    if not raw.endswith("]"):
        raise ValueError(f"a list must be one line, `[a, b]`: {raw!r}")
    inner = raw[1:-1].strip()
    if not inner:
        return []
    items = []
    rest = inner
    while True:
        if rest.startswith('"'):
            match = re.match(r'"(?:[^"\\]|\\["\\])*"', rest)
            if not match:
                raise ValueError(f"bad double-quoted list item in {raw!r}")
            item, rest = match.group(0), rest[match.end():]
        else:
            item, comma, after = rest.partition(",")
            item, rest = item.rstrip(), comma + after
        value = parse_scalar(item, in_list=True)
        items.append(str(value))
        rest = rest.lstrip(" ")
        if not rest:
            return items
        if not rest.startswith(","):
            raise ValueError(f"list items must be separated by commas: {raw!r}")
        rest = rest[1:].lstrip(" ")


def bare_problem(raw, in_list):
    """Why `raw` is no bare value of the subset, or None."""
    if not raw:
        return 'an empty value must be written ""'
    if raw != raw.strip():
        return f"leading or trailing space in {raw!r}"
    if raw[0] in BARE_START_FORBIDDEN:
        return f"quote a value that starts with {raw[0]!r}: {raw!r}"
    if any(char in BARE_FORBIDDEN for char in raw) or (in_list and "," in raw):
        return f"quote {raw!r}"
    if ": " in raw or " #" in raw or raw.endswith(":"):
        return f"quote a value holding `: `, ` #` or a final `:`: {raw!r}"
    if YAML_TYPED.fullmatch(raw):
        return f"YAML reads {raw!r} as a bool, null, float or date: quote it"
    return None


def format_value(value):
    if isinstance(value, list):
        return "[" + ", ".join(format_scalar(str(item), in_list=True) for item in value) + "]"
    if isinstance(value, int):
        return str(value)
    return format_scalar(value, in_list=False)


def format_scalar(text, in_list):
    # A string of digits is quoted, so it reads back as a string and not an int.
    if bare_problem(text, in_list) is None and not INTEGER.fullmatch(text):
        return text
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def read(path):
    with open(path, encoding="utf-8", newline="") as handle:
        return Doc(path, handle.read())


def unreadable(path, failure):
    """A stand-in for a file that cannot be read (no permission, not UTF-8): no keys, one error naming the cause."""
    doc = Doc(path, "")
    if isinstance(failure, UnicodeDecodeError):
        doc.unread_cause = f"not UTF-8 ({failure.reason})"
    else:
        doc.unread_cause = failure.strerror or str(failure)
    doc.errors = [(1, f"cannot be read: {doc.unread_cause}")]
    return doc


def load(path):
    """Read a doc that must be inside the subset, else raise ParseError."""
    doc = read(path)
    if doc.errors:
        raise ParseError(path, doc.errors)
    return doc
