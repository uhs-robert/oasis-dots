#!/usr/bin/env python3
"""PostToolUse hook: an advisory lint for the mechanical rules of the plain-writing skill.

It checks three kinds of new prose and reports the hits to the agent as added context:
- A commit that a Bash call just made: the message of HEAD.
- The body of `gh pr|issue create|edit`: from `--body`, `--body-file <path>`, or a heredoc for `--body-file -`.
- A Write, Edit or MultiEdit on a Markdown file: only the paragraphs that hold an added line, so old text
  in a long-lived file does not flood the report.

It never blocks and always exits 0. Judgment rules (lead with the point, gloss a coined term) stay with the
skill's self-check, because a linter cannot see them.
"""
import fnmatch
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import time

MAX_REPORTED_HITS = 15
MAX_SENTENCE_WORDS = 25
# A commit older than this was not made by the Bash call that fired the hook (the commit failed, or the
# command only mentioned git commit), so its message is not linted.
FRESH_COMMIT_SECONDS = 120

CONTRACTION = re.compile(r"\b\w+n['’]t\b|\b\w+['’](re|ll|ve|d)\b|\b(it|that|there|what|here|who|let|he|she)['’]s\b", re.I)
HEDGING_MODAL = re.compile(r"\b(should|would|may|might|could)\b", re.I)
PRESENT_PERFECT = re.compile(r"\b(has|have|had) been\b", re.I)
SPLICE = re.compile(r"—|;|\s--\s|\w\s-\s\w")
BOLD_LABEL = re.compile(r"^\s*(?:[-*+]|\d+\.)\s+\*\*[^*]+?:?\*\*:?")
ING_AFTER_COMMA = re.compile(r",\s+(\w+ing)\b", re.I)
# -ing words that are not a verb hanging off a clause.
ING_NOT_VERB = {"during", "including", "according", "nothing", "something", "anything", "everything", "string",
                "thing", "things", "morning", "evening", "pending", "remaining", "existing", "following", "missing",
                "ring", "king", "spring", "bring", "sing", "wing", "ceiling", "heading", "setting", "settings",
                "building", "padding", "spacing", "warning", "warnings", "logging", "naming", "routing", "testing"}

GH_BODY_COMMAND = re.compile(r"\bgh\s+(pr|issue)\s+(create|edit)\b")
GIT_COMMIT_COMMAND = re.compile(r"\bgit\b(?:\s+-C\s+\S+)?[^|;&\n]*?\bcommit\b")
COMMAND_SEPARATORS = {"&&", "||", ";", "|", "&"}
# Open `--body "$(cat ` at the end of the text before a heredoc: the same as `--body-file -`.
BODY_FROM_CAT = re.compile(r"(?:--body|-b)\s+\"?\$\(\s*cat\s+$")
# CommonMark HTML blocks of kind 6 end at a blank line. Kind 1 (pre, script, style, textarea) ends at its close tag.
HTML_BLOCK_TAGS = (
    "address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|"
    "fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|"
    "menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|"
    "track|ul"
)
HTML_BLOCK_START = re.compile(rf"^ {{0,3}}</?(?:{HTML_BLOCK_TAGS})(?:\s|/?>|$)", re.I)
HTML_RAW_START = re.compile(r"^ {0,3}<(pre|script|style|textarea)(?:\s|>|$)", re.I)
SETEXT_UNDERLINE = re.compile(r"^ {0,3}(?:=+|-+)\s*$")
# A footnote `[^1]:` is prose, so the label may not start with a caret.
LINK_DEFINITION = re.compile(r"^ {0,3}\[[^\]^][^\]]*\]:\s")
LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+\.)\s")
# `rest` is the shell text after the delimiter on the opening line, which can hold more commands.
HEREDOC = re.compile(r"<<-?\s*(?P<quote>['\"]?)(?P<delimiter>\w+)(?P=quote)(?P<rest>[^\n]*)\n(?P<body>.*?)\n\s*(?P=delimiter)\s*$", re.S | re.M)
# What closes a `--body "$(cat <<'EOF' ... EOF` substitution after the heredoc.
SUBSTITUTION_END = re.compile(r"\s*\)\s*\"?")
ENV_ASSIGNMENT = re.compile(r"\w+=")


def word_swaps_path():
    """The skill's word-swap table is the single list of filler words. The hook resolves through its own
    symlink into the dotfiles tree, so the skill sits beside it there."""
    here = pathlib.Path(__file__).resolve().parent
    candidates = [here.parent / "skills" / "plain-writing" / "references" / "word-swaps.md"]
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    candidates.append(pathlib.Path(config_dir) / "skills" / "plain-writing" / "references" / "word-swaps.md")
    return next((p for p in candidates if p.is_file()), None)


def load_filler_words(path):
    """First column of the word-swap table. An entry with a qualifier ("since (meaning because)") needs
    judgment, so it is left to the self-check."""
    if path is None:
        return []
    words = []
    for line in path.read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2 or not line.lstrip().startswith("|") or cells[0] in ("Overused", "") or set(cells[0]) <= {"-"}:
            continue
        for entry in cells[0].split(", "):
            entry = entry.strip()
            if entry and "(" not in entry:
                words.append(entry)
    return words


def filler_pattern(words):
    if not words:
        return None
    alternatives = sorted((re.escape(w) for w in words), key=len, reverse=True)
    return re.compile(r"(?<![\w-])(" + "|".join(alternatives) + r")(?![\w-])", re.I)


def strip_exempt(text):
    """Remove what the rules exempt: code, URLs, quoted text and HTML comments. Inline code becomes one
    placeholder word, because an identifier counts as one word in a sentence."""
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
    # A run of backticks closes only on a run of the same length, so a double-backtick span may hold one.
    text = re.sub(r"(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)", "CODE", text)
    text = re.sub(r"https?://\S+", "URL", text)
    text = re.sub(r"\]\([^)]*\)", "]", text)
    text = re.sub(r"\"[^\"\n]*\"|“[^”\n]*”", "QUOTE", text)
    return text


def prose_units(text):
    """Split Markdown into prose units, as (first line number, last line number, text). A unit is a
    paragraph or one list item. Fenced code, block quotes, HTML blocks, tables, headings (ATX and setext), link
    reference definitions and front matter are skipped."""
    # Blank out HTML comments first, keeping their newlines so line numbers stay true. Split into lines,
    # a multi-line comment would lose its opener and leave its body to be linted.
    text = re.sub(r"<!--.*?-->", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    units, current, start = [], [], 0
    fence = None  # (character, length) of the open code fence
    lines = text.splitlines()
    in_front_matter = bool(lines) and lines[0].strip() == "---"
    html_block_end = None  # "blank" or the close-tag pattern of the open HTML block

    def flush(end):
        nonlocal current
        if current:
            units.append((start, end, " ".join(current)))
            current = []

    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if in_front_matter:
            if number > 1 and stripped == "---":
                in_front_matter = False
            continue
        if html_block_end is not None:
            if html_block_end == "blank":
                if not stripped:
                    html_block_end = None
            elif html_block_end.search(line):
                html_block_end = None
            continue
        marker = re.match(r"(`{3,}|~{3,})(.*)$", stripped)
        if fence is None and marker:
            flush(number - 1)
            fence = (marker.group(1)[0], len(marker.group(1)))
            continue
        if fence is not None:
            # CommonMark: only the same character, at least as long, with nothing after it, closes the fence.
            if marker and marker.group(1)[0] == fence[0] and len(marker.group(1)) >= fence[1] and not marker.group(2).strip():
                fence = None
            continue
        raw_html = HTML_RAW_START.match(line)
        if raw_html or HTML_BLOCK_START.match(line):
            flush(number - 1)
            html_block_end = re.compile(rf"</{raw_html.group(1)}\s*>", re.I) if raw_html else "blank"
            if raw_html and html_block_end.search(line):
                html_block_end = None
            continue
        # A setext underline turns the paragraph above it into a heading. After a list item it is not one.
        if current and SETEXT_UNDERLINE.match(line) and not LIST_ITEM.match(current[0]):
            current = []
            continue
        # A definition cannot interrupt a paragraph.
        if not current and LINK_DEFINITION.match(line):
            continue
        # An indented code block starts after a blank line. Inside a paragraph or list item, indentation is
        # only a continuation.
        indented_code = not current and line.startswith(("    ", "\t"))
        if not stripped or indented_code or stripped.startswith((">", "|", "#", "<")):
            flush(number - 1)
            continue
        if LIST_ITEM.match(line):
            flush(number - 1)
        if not current:
            start = number
        current.append(stripped)
    flush(len(lines))
    return units


def sentences(unit_text):
    body = re.sub(r"^\s*(?:[-*+]|\d+\.)\s+", "", unit_text)
    return [s for s in re.split(r"(?<=[.!?])\s+(?=[A-Z0-9(])", body) if s.strip()]


def lint_unit(raw_text, filler):
    """Hits for one prose unit, as (category, excerpt)."""
    hits = []
    if BOLD_LABEL.match(raw_text):
        hits.append(("bold label on a list item", raw_text[:60]))
    text = strip_exempt(raw_text)
    checks = [
        ("contraction", CONTRACTION),
        ("hedging modal", HEDGING_MODAL),
        ("present perfect", PRESENT_PERFECT),
        ("em-dash, semicolon or spaced hyphen", SPLICE),
    ]
    if filler is not None:
        checks.append(("filler word", filler))
    for category, pattern in checks:
        for match in pattern.finditer(text):
            hits.append((category, match.group(0).strip()))
    for match in ING_AFTER_COMMA.finditer(text):
        if match.group(1).lower() not in ING_NOT_VERB:
            hits.append(("-ing verb after a comma", match.group(0)))
    for sentence in sentences(text):
        count = len(sentence.split())
        if count > MAX_SENTENCE_WORDS:
            hits.append((f"long sentence ({count} words)", " ".join(sentence.split()[:8]) + " ..."))
    return hits


def lint_text(text, filler, keep_lines=None):
    """Hits as (line, category, excerpt). With keep_lines, only units that hold one of those lines count."""
    hits = []
    for first, last, unit in prose_units(text):
        if keep_lines is not None and not any(first <= n <= last for n in keep_lines):
            continue
        hits.extend((first, category, excerpt) for category, excerpt in lint_unit(unit, filler))
    return hits


def report(target, hits, how_to_fix):
    lines = [f"plain-writing lint (advisory): {target} has {len(hits)} hit(s)."]
    for line, category, excerpt in hits[:MAX_REPORTED_HITS]:
        where = f"line {line}, " if line else ""
        lines.append(f"  {where}{category}: {excerpt}")
    if len(hits) > MAX_REPORTED_HITS:
        lines.append(f"  and {len(hits) - MAX_REPORTED_HITS} more.")
    lines.append("Fix each hit that breaks the plain-writing skill. Quoted text, code and names are exempt. " + how_to_fix)
    return "\n".join(lines)


def run_git(cwd, *args):
    result = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5)
    return result.stdout if result.returncode == 0 else None


def command_directory(command, cwd):
    """The directory a git command ran in: a leading `cd <dir> &&`, then `git -C <dir>`."""
    directory = cwd
    cd = re.match(r"\s*cd\s+(\S+)\s*&&", command)
    if cd:
        directory = os.path.join(directory, os.path.expanduser(cd.group(1).strip("'\"")))
    dash_c = re.search(r"\bgit\s+-C\s+(\S+)", command)
    if dash_c:
        directory = os.path.join(directory, os.path.expanduser(dash_c.group(1).strip("'\"")))
    return directory


def commit_message_hits(command, cwd, filler):
    directory = command_directory(command, cwd)
    stamp = run_git(directory, "log", "-1", "--format=%ct")
    if not stamp or time.time() - int(stamp.strip()) > FRESH_COMMIT_SECONDS:
        return None
    # The subject names commands and scopes without backticks ("add just post-merge"), so only the body counts.
    body = run_git(directory, "log", "-1", "--format=%b") or ""
    # %b starts after the subject and its blank line, so body line 1 is line 3 of the message.
    hits = [(line + 2, category, excerpt) for line, category, excerpt in lint_text(body, filler)]
    if not hits:
        return None
    return report("the commit message", hits, "Amend the commit with the corrected message.")


def command_words(text):
    """Shell words of a command, with `&&`, `||`, `;` and `|` as their own words. None on an open quote."""
    lexer = shlex.shlex(text, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    try:
        return list(lexer)
    except ValueError:
        return None


def segment_body(words, heredoc, cwd):
    """The body of one gh command, given as its words."""
    for index, word in enumerate(words[:-1]):
        value = words[index + 1]
        if word in ("--body", "-b"):
            return value
        if word in ("--body-file", "-F"):
            if value == "-":
                return heredoc
            return read_body_file(value, cwd)
    for word in words:
        if word.startswith("--body="):
            return word[len("--body="):]
        if word.startswith("--body-file="):
            return read_body_file(word[len("--body-file="):], cwd)
    return None


def read_body_file(value, cwd):
    try:
        return pathlib.Path(cwd, os.path.expanduser(value)).read_text(encoding="utf-8")
    except OSError:
        return None


def mark_command_breaks(text):
    """Turn each newline outside quotes into `;`, because shlex reads a newline as a space."""
    out, quote = [], None
    escaped = False
    for char in text:
        if escaped:
            escaped = False
        elif char == "\\" and quote != "'":
            escaped = True
        elif quote:
            quote = None if char == quote else quote
        elif char in "'\"":
            quote = char
        elif char == "\n":
            char = " ; "
        out.append(char)
    return "".join(out)


def gh_bodies_of_chunk(chunk, heredoc, cwd):
    """The (kind, body) of each gh command in shell text. The heredoc, if any, belongs to its last command."""
    words = command_words(mark_command_breaks(chunk.replace("\\\n", " ")))
    if words is None:
        return []
    segments, current = [], []
    for word in words:
        if word in COMMAND_SEPARATORS:
            segments.append(current)
            current = []
        else:
            current.append(word)
    segments.append(current)
    bodies = []
    for number, segment in enumerate(segments):
        while segment and ENV_ASSIGNMENT.match(segment[0]):
            segment = segment[1:]
        if len(segment) > 2 and segment[0] == "gh" and segment[1] in ("pr", "issue") and segment[2] in ("create", "edit"):
            owned = heredoc if number == len(segments) - 1 else None
            body = segment_body(segment, owned, cwd)
            if body:
                bodies.append((segment[1], body))
    return bodies


def gh_bodies(command, cwd):
    """The (kind, body) of every `gh pr|issue create|edit` in a command, a chain included. The text is cut
    at each heredoc: the shell text before it is parsed, its body goes to the command that opened it, and
    parsing resumes after its closing delimiter."""
    bodies, position = [], 0
    while True:
        heredoc = HEREDOC.search(command, position)
        if not heredoc:
            return bodies + gh_bodies_of_chunk(command[position:], None, cwd)
        head = command[position:heredoc.start()]
        chunk = head + " " + heredoc.group("rest")
        position = heredoc.end()
        if command_words(chunk.replace("\\\n", " ")) is None:
            # --body "$(cat <<'EOF' ...)" leaves an open quote before the heredoc.
            opener = BODY_FROM_CAT.search(head)
            if opener:
                chunk = head[:opener.start()] + "--body-file - " + heredoc.group("rest")
                closing = SUBSTITUTION_END.match(command, position)
                position = closing.end() if closing else position
        bodies += gh_bodies_of_chunk(chunk, heredoc.group("body"), cwd)


def gh_body_hits(command, cwd, filler):
    messages = []
    for kind, body in gh_bodies(command, cwd):
        hits = lint_text(body, filler)
        if hits:
            kind_name = "PR" if kind == "pr" else "issue"
            messages.append(report(f"the {kind_name} body", hits, f"Edit the {kind_name} body with `gh {kind} edit --body-file`."))
    return "\n".join(messages) or None


def excluded(path):
    """Agent memory and transcripts, the skill's own files (they quote the banned words as examples), and
    any glob in PLAIN_WRITING_LINT_EXCLUDE (separated by the path separator)."""
    text = str(path)
    if "/skills/plain-writing/" in text or "/.claude/projects/" in text:
        return True
    patterns = [os.path.expanduser(p) for p in os.environ.get("PLAIN_WRITING_LINT_EXCLUDE", "").split(os.pathsep) if p]
    return any(fnmatch.fnmatch(text, p) for p in patterns)


def edits_of(tool_name, tool_input):
    """The edits a tool call made, as dicts with new_string, old_string and replace_all."""
    if tool_name == "Edit":
        return [tool_input]
    if tool_name == "MultiEdit":
        return tool_input.get("edits") or []
    return []


def edited_lines(text, edit):
    """Line numbers of the lines an edit added. It finds where new_string sits in the file, because a line
    of new text can repeat a line elsewhere, and matching by text alone would select that old paragraph."""
    new = edit.get("new_string") or ""
    if not new.strip():
        return set()
    old_lines = {line.strip() for line in (edit.get("old_string") or "").splitlines()}
    lines = set()
    start = text.find(new)
    while start != -1:
        first = text.count("\n", 0, start) + 1
        for offset, line in enumerate(new.splitlines()):
            if line.strip() and line.strip() not in old_lines:
                lines.add(first + offset)
        if not edit.get("replace_all"):
            break
        start = text.find(new, start + len(new))
    return lines


def previous_lines(path):
    """The lines of the committed version of a file, to tell which lines a Write added."""
    directory = str(path.parent)
    root = run_git(directory, "rev-parse", "--show-toplevel")
    if not root:
        return set()
    relative = os.path.relpath(path.resolve(), pathlib.Path(root.strip()).resolve())
    old = run_git(directory, "show", f"HEAD:{relative}")
    return {line.strip() for line in old.splitlines()} if old else set()


def markdown_hits(tool_name, tool_input, cwd, filler):
    file_path = tool_input.get("file_path") or ""
    if not file_path.endswith((".md", ".markdown")):
        return None
    path = pathlib.Path(cwd, os.path.expanduser(file_path))
    if excluded(path.resolve()) or excluded(path):
        return None
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    file_lines = text.splitlines()
    if tool_name == "Write":
        old_lines = previous_lines(path)
        keep = {n for n, line in enumerate(file_lines, 1) if line.strip() and line.strip() not in old_lines}
    else:
        keep = set().union(*(edited_lines(text, edit) for edit in edits_of(tool_name, tool_input)))
    if not keep:
        return None
    hits = lint_text(text, filler, keep)
    if not hits:
        return None
    return report(path.name, hits, "Rewrite the new text. Leave old text alone unless the task covers it.")


def handle(event):
    tool_name = event.get("tool_name") or ""
    tool_input = event.get("tool_input") or {}
    cwd = event.get("cwd") or os.getcwd()
    filler = filler_pattern(load_filler_words(word_swaps_path()))
    if tool_name == "Bash":
        command = tool_input.get("command") or ""
        if GH_BODY_COMMAND.search(command):
            return gh_body_hits(command, cwd, filler)
        if GIT_COMMIT_COMMAND.search(command):
            return commit_message_hits(command, cwd, filler)
        return None
    if tool_name in ("Write", "Edit", "MultiEdit"):
        return markdown_hits(tool_name, tool_input, cwd, filler)
    return None


def main():
    try:
        event = json.load(sys.stdin)
        message = handle(event)
    except Exception:  # an advisory hook must never break the tool call it follows
        return 0
    if message:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": message}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
