#!/usr/bin/env python3
"""PreToolUse and PostToolUse hook: a lint for the mechanical rules of the plain-writing skill.

Before a Bash call (PreToolUse) it checks the text the call is about to publish:
- The message of `git commit`: from `-m` (one or more), `-F <path>`, or a heredoc for `-F -`. The subject
  line is not linted.
- The body of `gh pr|issue create|edit`: from `--body`, `--body-file <path>`, or a heredoc for `--body-file -`.

A text with hits denies the call once ("deny once, allow retry"). The hook stores a hash of the denied text,
so the identical text sent again goes through, which lets the agent overrule a false positive. Any changed
text is linted fresh.

After a tool call (PostToolUse) it reports hits to the agent as added context, and never blocks:
- A Write, Edit or MultiEdit on a Markdown file: only the paragraphs that hold an added line, so old text
  in a long-lived file does not flood the report.
- A message or body file that the same Bash call wrote before the commit or gh command read it, as in
  `cat > msg <<EOF ... EOF && git commit -F msg`. Before the call, that file holds old text or nothing.

On any error of its own the hook allows the call and exits 0. Judgment rules (lead with the point, gloss a
coined term) stay with the skill's self-check, because a linter cannot see them.
"""
import fnmatch
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time

MAX_REPORTED_HITS = 15
MAX_SENTENCE_WORDS = 25
# How long a denied text stays allowed for its retry.
DENIED_TEXT_SECONDS = 24 * 3600

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

# `gh` must start a shell word: at the start, after a blank, `(`, `=`, an operator or a backtick.
GH_BODY_COMMAND = re.compile(r"(?<![^\s(=;&|`])gh(?:\s|\\\n)+(?P<kind>pr|issue)(?:\s|\\\n)+(?:create|edit)\b")
GIT_COMMIT_COMMAND = re.compile(r"(?<![^\s(=;&|`])git(?:(?:\s|\\\n)+-[Cc](?:\s|\\\n)+\S+)*(?:\s|\\\n)+commit\b")
# Short options of git commit that take a value, attached (`-mText`) or in the next word. `-S` and `-u`
# take only an attached value, so they are not listed.
COMMIT_VALUE_OPTIONS = "mFCct"
# `<<<` is a here-string, not a heredoc.
HEREDOC_OPENER = re.compile(r"(?<!<)<<(?!<)(?P<dash>-?)[ \t]*(?P<quote>['\"]?)(?P<delimiter>\w+)(?P=quote)")
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


def hit_lines(target, hits):
    lines = [f"plain-writing lint: {target} has {len(hits)} hit(s)."]
    for line, category, excerpt in hits[:MAX_REPORTED_HITS]:
        where = f"line {line}, " if line else ""
        lines.append(f"  {where}{category}: {excerpt}")
    if len(hits) > MAX_REPORTED_HITS:
        lines.append(f"  and {len(hits) - MAX_REPORTED_HITS} more.")
    return lines


def report(target, hits, how_to_fix):
    """An advisory report, for text the tool call already wrote or published."""
    lines = hit_lines(target, hits)
    lines.append("Fix each hit that breaks the plain-writing skill. Quoted text, code and names are exempt. " + how_to_fix)
    return "\n".join(lines)


DENY_FOOTER = (
    "The hook blocked this call. Fix each hit and run the call again. Quoted text, code and names are exempt. "
    "If a hit is a false positive, resubmit the identical text unchanged and the hook lets it through."
)
TARGET_NAMES = {"commit": "the commit message", "pr": "the PR body", "issue": "the issue body"}
FIX_AFTER_POST = {
    "commit": "Amend the commit with the corrected message.",
    "pr": "Edit the PR body with `gh pr edit --body-file`.",
    "issue": "Edit the issue body with `gh issue edit --body-file`.",
}


def message_hits(kind, text, filler):
    if kind != "commit":
        return lint_text(text, filler)
    # The subject names commands and scopes without backticks ("add just post-merge"), so only the body counts.
    # Line numbers stay those of the whole message.
    body = text.split("\n", 1)[1] if "\n" in text else ""
    return [(line + 1, category, excerpt) for line, category, excerpt in lint_text(body, filler)]


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


def heredoc_bodies(command, newline, openers, bodies_end_by_line):
    """The bodies of the heredocs opened on the line that ends at index `newline`, and the index after the
    last one. `openers` holds (delimiter, strip_tabs). The bodies follow each other, so the first opener on a
    line starts right after it, and a later call for the same line goes on where the last body ended."""
    position = bodies_end_by_line.get(newline, newline + 1)
    bodies = []
    for delimiter, strip_tabs in openers:
        start = body_end = position
        while position < len(command):
            line_end = command.find("\n", position)
            line_end = len(command) if line_end == -1 else line_end
            line = command[position:line_end]
            line = line.lstrip("\t") if strip_tabs else line
            if line.strip() == delimiter:
                position = line_end + 1
                break
            # Agents write `EOF && next command`. The shell keeps that line in the body, but the agent meant
            # the heredoc to end there, so the search goes on with the command after the delimiter.
            tail = line.lstrip()
            if tail.startswith(delimiter) and tail[len(delimiter):].lstrip().startswith(("&&", "||", ";", "|")):
                position = line_end - len(tail) + len(delimiter)
                break
            body_end = line_end
            position = line_end + 1
        else:
            # No closing delimiter: the shell takes the rest of the text.
            body_end = len(command)
        body = command[start:body_end]
        # `<<-` strips leading tabs from the body too. Kept, they would read as indented code.
        bodies.append(re.sub(r"(?m)^\t+", "", body) if strip_tabs else body)
    bodies_end_by_line[newline] = position
    return bodies, position


def read_command_words(command, start, bodies_end_by_line):
    """Read the shell words of the command at `start`, up to the first unquoted operator, newline or closing
    `)`. Returns (words, heredocs, end). `heredocs` maps a word index to the body of a heredoc
    opened inside that word, as in `--body "$(cat <<'EOF'`, and None to the command's own stdin heredoc.
    The bodies it reads are noted in `bodies_end_by_line`, so the caller skips them at the newline."""
    words, heredocs, openers = [], {}, []
    word, in_word = [], False
    nesting = []  # open quotes and substitutions, innermost last: "'", '"' or "("
    index = start

    def end_word():
        nonlocal word, in_word
        if word or in_word:
            words.append("".join(word))
        word, in_word = [], False

    def take_bodies(newline):
        nonlocal openers
        bodies, after = heredoc_bodies(command, newline, [opener[:2] for opener in openers], bodies_end_by_line)
        for (_, _, owner), body in zip(openers, bodies):
            heredocs.setdefault(owner, body)
        openers = []
        return after

    while index < len(command):
        char = command[index]
        inner = nesting[-1] if nesting else None
        if inner == "'":
            if char == "'":
                nesting.pop()
            else:
                word.append(char)
            index += 1
            continue
        if char == "\\" and index + 1 < len(command):
            # A backslash-newline joins two lines and leaves nothing.
            if command[index + 1] != "\n":
                word.append(command[index + 1])
            index += 2
            continue
        if inner == '"':
            if char == '"':
                nesting.pop()
            elif command.startswith("$(", index):
                nesting.append("(")
                word.append("$(")
                index += 1  # with the step below, past both characters
            else:
                word.append(char)
            index += 1
            continue
        if char == "\n" and openers:
            after = take_bodies(index)
            if inner is None:
                break
            # Inside `$(`, the shell reads on after the bodies, up to the closing `)`.
            word.append(char)
            index = after
            continue
        opener = HEREDOC_OPENER.match(command, index) if char == "<" else None
        if opener:
            owner = None if inner is None else len(words)
            openers.append((opener.group("delimiter"), opener.group("dash") == "-", owner))
            if inner is None:
                end_word()
            else:
                word.append(opener.group(0))
            index = opener.end()
            continue
        if char in "'\"":
            nesting.append(char)
            in_word = True
        elif command.startswith("$(", index):
            nesting.append("(")
            word.append("$(")
            index += 1
        elif inner == "(":
            if char == ")":
                nesting.pop()
            elif char == "(":
                nesting.append("(")
            word.append(char)
        elif char in " \t":
            end_word()
        elif char == "#" and not word and not in_word:
            break  # a comment ends the command
        elif char in ";|\n)`" or (char == "&" and command[index - 1] not in "<>"):
            break
        else:
            word.append(char)
        index += 1
    end_word()
    if openers:
        # The command ended before its line did, as in `<<'EOF' && echo done`: the bodies follow that line.
        newline = command.find("\n", index)
        if newline != -1:
            take_bodies(newline)
    return words, heredocs, index


def text_source(heredocs, index, value):
    """("text", the text) of an inline value. A `$(...)` without a heredoc in it is left out, because only
    the shell knows what it prints."""
    if index in heredocs:
        return ("text", heredocs[index])
    if "$(" in value or "`" in value:
        return None
    return ("text", value)


def file_source(heredocs, value):
    """The source a file argument names: the command's stdin heredoc for `-`, else ("file", the path)."""
    if value == "-":
        return ("text", heredocs[None]) if None in heredocs else None
    return ("file", value)


def gh_command_source(words, heredocs):
    """The source of the body that `--body`, `-b`, `--body-file` or `-F` gives, or None."""
    for index, word in enumerate(words[:-1]):
        value = words[index + 1]
        if word in ("--body", "-b"):
            return text_source(heredocs, index + 1, value)
        if word in ("--body-file", "-F"):
            return file_source(heredocs, value)
    for index, word in enumerate(words):
        if word.startswith("--body="):
            return text_source(heredocs, index, word[len("--body="):])
        if word.startswith("--body-file="):
            return file_source(heredocs, word[len("--body-file="):])
    return None


def commit_source(words, heredocs):
    """The source of the message a `git commit` gives with `-m` or `-F`, or None. With no such flag git
    reuses a message (`--no-edit`, `-C`) or opens an editor, and there is no new text to check."""
    index = 1
    while index < len(words) and words[index] != "commit":
        index += 2 if words[index] in ("-C", "-c") else 1
    messages, file_value = [], None
    index += 1
    while index < len(words):
        word = words[index]
        value, value_index = None, index + 1
        if word == "--":
            break
        if word in ("--message", "--file") and index + 1 < len(words):
            value = words[index + 1]
            option = word[2]
        elif word.startswith(("--message=", "--file=")):
            option, value, value_index = word[2], word.split("=", 1)[1], index
        elif word.startswith("-") and not word.startswith("--"):
            for position, letter in enumerate(word[1:], 1):
                if letter in COMMIT_VALUE_OPTIONS:
                    option = letter
                    if position + 1 < len(word):
                        value, value_index = word[position + 1:], index
                    elif index + 1 < len(words):
                        value = words[index + 1]
                    break
        if value is not None:
            if option == "m":
                messages.append(text_source(heredocs, value_index, value))
            elif option in ("F", "f"):
                file_value = value
            index = value_index + 1
            continue
        index += 1
    if file_value is not None:
        return file_source(heredocs, file_value)
    if not messages or None in messages:
        return None
    # git joins several -m values as separate paragraphs.
    return ("text", "\n\n".join(text for _, text in messages))


def read_body_file(value, cwd):
    try:
        return pathlib.Path(cwd, os.path.expanduser(value)).read_text(encoding="utf-8")
    except (OSError, ValueError):  # ValueError: a NUL byte in the path
        return None


def piped_in(command, index):
    """Whether a single `|` comes right before index, blanks aside."""
    before = index - 1
    while before >= 0 and command[before] in " \t":
        before -= 1
    return before >= 0 and command[before] == "|" and (before == 0 or command[before - 1] != "|")


def message_sources(command):
    """The (kind, source, start index) of every `gh pr|issue create|edit` body and `git commit` message in a
    command. Kind is "pr", "issue" or "commit". It walks the command once and tracks quotes, `$(...)`,
    arithmetic, comments and heredoc bodies, so it finds a command or a heredoc only where the shell runs
    one: also inside `$(...)` or after another command, but not in quoted text, a comment or a body. Each
    command reads only its own words, so text before it cannot hide it."""
    sources, bodies_end_by_line = [], {}
    # Open contexts, innermost last: "'", '"', "(" for a command substitution or subshell, "((" for arithmetic
    # and "a(" for a parenthesis inside arithmetic.
    nesting = []
    line_openers = []  # (delimiter, strip_tabs) of other commands' heredocs opened on the current line
    last_line_body = None  # body of the last heredoc of another command on this line, for `cat <<EOF | gh ...`
    index = 0

    def take_line_bodies(newline):
        nonlocal line_openers, last_line_body
        line_bodies, _ = heredoc_bodies(command, newline, line_openers, bodies_end_by_line)
        last_line_body = line_bodies[-1]
        line_openers = []

    while index < len(command):
        char = command[index]
        inner = nesting[-1] if nesting else None
        if inner == "'":
            closing = command.find("'", index)
            index = len(command) if closing == -1 else closing + 1
            nesting.pop()
            continue
        if char == "\\":
            index += 2
            continue
        if inner == '"':
            if char == '"':
                nesting.pop()
            elif command.startswith("$((", index):
                nesting.append("((")
                index += 2
            elif command.startswith("$(", index):
                nesting.append("(")
                index += 1
            index += 1
            continue
        if inner in ("((", "a("):
            # Arithmetic: `<<` is a shift and quotes are rare, so only the parentheses count.
            if char == "(":
                nesting.append("a(")
            elif char == ")":
                if inner == "a(":
                    nesting.pop()
                elif command.startswith("))", index):
                    nesting.pop()
                    index += 1
            index += 1
            continue
        if char == "\n":
            if line_openers:
                take_line_bodies(index)
            last_line_body = None
            index = bodies_end_by_line.get(index, index + 1)
            continue
        if char == "#" and (index == 0 or command[index - 1] in " \t\n;&|("):
            comment_end = command.find("\n", index)
            index = len(command) if comment_end == -1 else comment_end
            continue
        opener = HEREDOC_OPENER.match(command, index) if char == "<" else None
        if opener:
            line_openers.append((opener.group("delimiter"), opener.group("dash") == "-"))
            index = opener.end()
            continue
        gh_command = GH_BODY_COMMAND.match(command, index) if char == "g" else None
        commit_command = GIT_COMMIT_COMMAND.match(command, index) if char == "g" and not gh_command else None
        if gh_command or commit_command:
            newline = command.find("\n", index)
            # The bodies of heredocs opened earlier on the line come first, so read them before the command
            # reads its own.
            if line_openers and newline != -1:
                take_line_bodies(newline)
            words, heredocs, end = read_command_words(command, index, bodies_end_by_line)
            if last_line_body is not None and piped_in(command, index):
                heredocs.setdefault(None, last_line_body)
            if gh_command:
                kind, source = gh_command.group("kind"), gh_command_source(words, heredocs)
            else:
                kind, source = "commit", commit_source(words, heredocs)
            if source:
                sources.append((kind, source, index))
            index = max(end, (gh_command or commit_command).end())
            continue
        if command.startswith(("$((", "(("), index):
            nesting.append("((")
            index = command.index("((", index) + 2
            continue
        if command.startswith("$(", index) or char == "(":
            nesting.append("(")
            index += 2 if char == "$" else 1
            continue
        if char in "'\"":
            nesting.append(char)
        elif char == ")" and nesting:
            nesting.pop()
        index += 1
    return sources


def command_texts(command, cwd, phase="pre"):
    """The (kind, text) of every commit message and gh body in a command that the phase can see. Before the
    call ("pre") that is every inline text and every file the command does not name earlier. After it
    ("post") it is only the files the command names earlier, since the command itself likely wrote them."""
    texts = []
    for kind, (source_type, value), start in message_sources(command):
        if source_type == "text":
            if phase == "pre":
                texts.append((kind, value))
            continue
        written_here = value in command[:start]
        if written_here != (phase == "post"):
            continue
        # git reads -F relative to where it runs. gh is never given a directory.
        directory = command_directory(command, cwd) if kind == "commit" else cwd
        text = read_body_file(value, directory)
        if text is not None:
            texts.append((kind, text))
    return [(kind, text) for kind, text in texts if text.strip()]


def denied_texts_path():
    state_home = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return pathlib.Path(state_home, "claude", "plain-writing-lint-denied.json")


def text_digest(kind, text):
    return hashlib.sha256(f"{kind}\0{text}".encode("utf-8")).hexdigest()


def load_denied_texts():
    """{session_id: {digest: time denied}}, with expired entries dropped."""
    try:
        state = json.loads(denied_texts_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    cutoff = time.time() - DENIED_TEXT_SECONDS
    kept = {}
    for session, digests in state.items() if isinstance(state, dict) else ():
        fresh = {d: t for d, t in digests.items() if isinstance(t, (int, float)) and t >= cutoff} if isinstance(digests, dict) else {}
        if fresh:
            kept[session] = fresh
    return kept


def save_denied_texts(state):
    """Write the state in one rename, so a reader never sees half a file. Two sessions that write at once
    can lose one entry. That costs only a second deny of the same text, so the hook takes no lock."""
    path = denied_texts_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(state), encoding="utf-8")
    os.replace(temporary, path)


def pre_tool_use_reason(findings, session):
    """The deny reason, or None to allow. A text denied before in this session passes unchanged."""
    state = load_denied_texts()
    denied = state.setdefault(session, {})
    pending = [(kind, text, hits) for kind, text, hits in findings if text_digest(kind, text) not in denied]
    if not pending:
        return None
    now = time.time()
    for kind, text, _ in pending:
        denied[text_digest(kind, text)] = now
    # Without the stored digest the retry would be denied again, and the agent could not get through.
    # save_denied_texts raises on failure, and main() then allows the call.
    save_denied_texts(state)
    lines = []
    for kind, _, hits in pending:
        lines.extend(hit_lines(TARGET_NAMES[kind], hits))
    lines.append(DENY_FOOTER)
    return "\n".join(lines)


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


def bash_findings(command, cwd, phase, filler):
    findings = []
    for kind, text in command_texts(command, cwd, phase):
        hits = message_hits(kind, text, filler)
        if hits:
            findings.append((kind, text, hits))
    return findings


def handle(event):
    """The hook output as a dict, or None to stay silent."""
    tool_name = event.get("tool_name") or ""
    tool_input = event.get("tool_input") or {}
    cwd = event.get("cwd") or os.getcwd()
    phase = "pre" if event.get("hook_event_name") == "PreToolUse" else "post"
    filler = filler_pattern(load_filler_words(word_swaps_path()))
    if tool_name == "Bash":
        command = tool_input.get("command") or ""
        findings = bash_findings(command, cwd, phase, filler)
        if not findings:
            return None
        if phase == "pre":
            reason = pre_tool_use_reason(findings, str(event.get("session_id") or ""))
            if reason is None:
                return None
            return {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}
        reports = [report(TARGET_NAMES[kind], hits, FIX_AFTER_POST[kind]) for kind, _, hits in findings]
        return {"hookEventName": "PostToolUse", "additionalContext": "\n".join(reports)}
    # Before a Write or Edit the file still holds its old text, so Markdown is linted only after the call.
    if tool_name in ("Write", "Edit", "MultiEdit") and phase == "post":
        message = markdown_hits(tool_name, tool_input, cwd, filler)
        if message:
            return {"hookEventName": "PostToolUse", "additionalContext": message}
    return None


def main():
    try:
        event = json.load(sys.stdin)
        output = handle(event)
    except Exception:  # the hook must never break the tool call on its own error
        return 0
    if output:
        print(json.dumps({"hookSpecificOutput": output}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
