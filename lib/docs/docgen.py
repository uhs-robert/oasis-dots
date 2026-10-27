"""What the doc generators (gen-keybinds, gen-ipc) share: the marked block, table cells, the lua runner and the --write/--check flow."""

import argparse
import difflib
import os
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
BEGIN = "<!-- BEGIN generated -->"
END = "<!-- END generated -->"


class GenError(Exception):
    pass


def run_lua(script, *args):
    """stdout of `lua script args` run in the repo root."""
    done = subprocess.run(["lua", script, *args], capture_output=True, text=True, encoding="utf-8", cwd=ROOT)
    if done.returncode != 0:
        raise GenError(f"{script} failed: {(done.stderr or done.stdout).strip()}")
    return done.stdout


def cell(text, code=False):
    """One table cell: whitespace runs collapse to a space so a label cannot start a new row, and `|` is escaped."""
    text = " ".join(text.split()).replace("|", "\\|")
    return f"`{text}`" if code and text else text


def splice(doc, table):
    """doc with the text between the markers replaced by table."""
    if doc.count(BEGIN) != 1 or doc.count(END) != 1:
        raise GenError(f"the doc needs exactly one {BEGIN} and one {END} line")
    head, rest = doc.split(BEGIN, 1)
    if END not in rest:
        raise GenError(f"{END} must come after {BEGIN}")
    _, tail = rest.split(END, 1)
    return f"{head}{BEGIN}\n{table}{END}{tail}"


def main(prog, description, default_doc, stale_what, add_arguments, render_table):
    """Parses --write/--check/--doc plus the generator's own arguments, then writes the doc or reports it stale.
    render_table(args) returns the table text; stale_what names it in the failure message."""
    parser = argparse.ArgumentParser(prog=prog, description=description)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--doc", default=default_doc)
    add_arguments(parser)
    args = parser.parse_args()
    try:
        table = render_table(args)
        with open(args.doc, encoding="utf-8") as file:
            current = file.read()
        wanted = splice(current, table)
    except (GenError, OSError) as error:
        print(f"{prog}: {error}", file=sys.stderr)
        return 1
    if args.write:
        if wanted != current:
            with open(args.doc, "w", encoding="utf-8") as file:
                file.write(wanted)
        return 0
    if wanted != current:
        sys.stdout.writelines(difflib.unified_diff(current.splitlines(True), wanted.splitlines(True), "current", "generated", n=1))
        print(f"{prog}: the generated {stale_what} is stale; run `just docs-gen`", file=sys.stderr)
        return 1
    return 0
