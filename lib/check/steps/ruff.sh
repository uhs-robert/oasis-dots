#!/bin/sh
# Lints the tracked Python files with ruff.toml: every `*.py` and every extensionless script with a python shebang.
# `--baseline` prints the [lint.per-file-ignores] entries for the current hits instead (paste them into ruff.toml).
set -u

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
cd "$repo_dir" || exit 1

if ! command -v ruff >/dev/null 2>&1; then
  echo "skip: ruff not installed"
  exit 0
fi

list=$(mktemp) || exit 1
trap 'rm -f "$list"' EXIT
git ls-files -z '*.py' | tr '\0' '\n' >"$list"
# A shebang counts only on the first line, which `git grep` cannot tell, so each candidate is checked.
git grep -lIE '^#!.*python' -- ':!*.py' ':!*.md' | while IFS= read -r file; do
  head -n 1 -- "$file" | grep -q '^#!.*python' && printf '%s\n' "$file"
done >>"$list"

if [ "${1-}" = "--baseline" ]; then
  # Rules per file from ruff's JSON, as TOML lines.
  xargs -d '\n' ruff check --no-cache --config 'lint.per-file-ignores = {}' --output-format json <"$list" | python3 -c '
import json, os, sys
by_file = {}
for hit in json.load(sys.stdin):
    path = os.path.relpath(hit["filename"])
    by_file.setdefault(path, set()).add(hit["code"])
for path in sorted(by_file):
    print("\"%s\" = [%s]" % (path, ", ".join("\"%s\"" % code for code in sorted(by_file[path]))))
'
  exit 0
fi

xargs -d '\n' ruff check --no-cache <"$list"
