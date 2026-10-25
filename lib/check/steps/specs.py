#!/usr/bin/env python3
"""Fails a spec or plan whose front matter breaks its schema, or whose body breaks the spec format.

  - every `specs/core/*.md`, TEMPLATE.md included, has front matter that validates against specs/schema/spec.yaml.
  - a spec's `id` is its file name, it has the `# ` title and the headings in REQUIRED_HEADINGS, and each requirement
    line (`- **BAR-01** ...`) carries the id in capitals as its prefix. TEMPLATE.md is exempt from the id and prefix
    rules: its id is a placeholder.
  - every `.plans/**/*.md` has front matter that validates against specs/schema/plan.yaml. `.plans/` is local, so
    where it does not exist (CI, a worktree) there is nothing to check.

Validation is check-jsonschema's, which reads whole YAML files: the front matter is written to a temp file and the
tool run on it. The step fails, not skips, when check-jsonschema is not installed, so a machine without it cannot pass
a spec it never read (packages/pipx.ini installs it).

  python3 -B lib/check/steps/specs.py
"""

import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
REPO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

SPEC_SCHEMA = "specs/schema/spec.yaml"
PLAN_SCHEMA = "specs/schema/plan.yaml"
TEMPLATE = "TEMPLATE.md"
REQUIRED_HEADINGS = ("What it is for", "Requirements", "Not covered")
MISSING_TOOL = "check-jsonschema is not installed (pipx install check-jsonschema); the specs step fails without it rather than pass unread"

FRONT_MATTER = re.compile(r"\A---\n(.*?\n)?---[ \t]*(?:\n|\Z)", re.DOTALL)
# The id as YAML reads it: `id: bar`, `id: "bar"` and `id: 'bar'` are the same value.
TOP_LEVEL_ID = re.compile(r"""^id:[ \t]*(?:"([^"\n]*)"|'([^'\n]*)'|([^\s#]*))""", re.MULTILINE)
REQUIREMENT = re.compile(r"^- \*\*([A-Z]+)-\d{2,}\*\*")
FENCE = re.compile(r"^ {0,3}(```|~~~)")


def split_front_matter(text):
    """(front matter text, body text, number of lines before the body), or None without a leading `---` block."""
    match = FRONT_MATTER.match(text)
    if not match:
        return None
    return match.group(1) or "", text[match.end():], text[:match.end()].count("\n")


def body_lines(body):
    """(line within the body, line) for each line outside a fenced code block."""
    fenced = None
    for number, line in enumerate(body.splitlines(), 1):
        fence = FENCE.match(line)
        if fence and fenced in (None, fence.group(1)):
            fenced = None if fenced else fence.group(1)
        elif not fenced:
            yield number, line


def check_body(path, body, offset, spec_id, is_template):
    """Findings for a spec's body: title, headings and requirement prefixes."""
    findings = []
    lines = list(body_lines(body))
    headings = {line[3:].strip() for _, line in lines if line.startswith("## ")}
    if not any(line.startswith("# ") for _, line in lines):
        findings.append(f"{path}:{offset + 1}: no `# <title>` heading after the front matter")
    for heading in REQUIRED_HEADINGS:
        if heading not in headings:
            findings.append(f"{path}:{offset + 1}: missing the `## {heading}` heading")
    if is_template or not spec_id:
        return findings
    prefix = spec_id.upper()
    for number, line in lines:
        found = REQUIREMENT.match(line)
        if found and found.group(1) != prefix:
            findings.append(f"{path}:{offset + number}: requirement {found.group(1)}-.. does not start with {prefix}, the prefix of spec {spec_id}")
    return findings


def validate(root, schema, front_matters):
    """check-jsonschema findings for {path: front matter text}, with the temp file names turned back into the paths."""
    if not front_matters:
        return []
    with tempfile.TemporaryDirectory() as scratch:
        temp_to_path = {}
        for index, (path, text) in enumerate(sorted(front_matters.items())):
            temp = os.path.join(scratch, f"{index}.yaml")
            with open(temp, "w") as handle:
                handle.write(text)
            temp_to_path[temp] = path
        done = subprocess.run(
            ["check-jsonschema", "--schemafile", os.path.join(os.path.abspath(root), schema), *temp_to_path],
            capture_output=True, text=True, cwd=scratch,
        )
    if done.returncode == 0:
        return []
    output = done.stdout + done.stderr
    for temp, path in temp_to_path.items():
        output = output.replace(temp, path)
    lines = [line for line in output.splitlines() if line.strip() and not line.startswith("Schema validation errors were encountered")]
    return lines or ["schema validation failed"]


def check_specs(root):
    findings, front_matters = [], {}
    for full in sorted(glob.glob(os.path.join(root, "specs", "core", "*.md"))):
        path = os.path.relpath(full, root)
        with open(full) as handle:
            parts = split_front_matter(handle.read())
        if parts is None:
            findings.append(f"{path}:1: no front matter (a spec starts with a `---` block)")
            continue
        front, body, offset = parts
        front_matters[path] = front
        is_template = os.path.basename(path) == TEMPLATE
        found = TOP_LEVEL_ID.search(front)
        spec_id = next((group for group in found.groups() if group is not None), "") if found else ""
        stem = os.path.basename(path)[:-3]
        if not is_template and spec_id and spec_id != stem:
            findings.append(f"{path}:1: id {spec_id} is not the file name {stem}")
        findings.extend(check_body(path, body, offset, spec_id, is_template))
    return findings + validate(root, SPEC_SCHEMA, front_matters)


def check_plans(root):
    findings, front_matters = [], {}
    for full in sorted(glob.glob(os.path.join(root, ".plans", "**", "*.md"), recursive=True)):
        path = os.path.relpath(full, root)
        with open(full) as handle:
            parts = split_front_matter(handle.read())
        if parts is None:
            findings.append(f"{path}:1: no front matter (a plan starts with a `---` block)")
        else:
            front_matters[path] = parts[0]
    return findings + validate(root, PLAN_SCHEMA, front_matters)


def run_checks(root):
    """Every finding for the checkout at root."""
    if not shutil.which("check-jsonschema"):
        return [MISSING_TOOL]
    return check_specs(root) + check_plans(root)


def main(argv):
    if argv:
        print("usage: lib/check/steps/specs.py", file=sys.stderr)
        return 2
    findings = run_checks(REPO_DIR)
    for finding in findings:
        print(finding, file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
