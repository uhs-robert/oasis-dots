#!/bin/sh
set -u

# Runs every validation step and reports all failures, rather than stopping at
# the first one: a single run should show everything that needs fixing.
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")

cd "$repo_dir" || exit 1

failed=''

record() {
  failed="$failed $1"
}

# Optional tooling: skip when absent so validation stays dependency-light.
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck install.sh uninstall.sh lib/*.sh || record shellcheck
else
  echo 'skip: shellcheck not installed'
fi

if command -v shfmt >/dev/null 2>&1; then
  shfmt -i 2 -d install.sh uninstall.sh lib/*.sh || record shfmt
else
  echo 'skip: shfmt not installed'
fi

if command -v stylua >/dev/null 2>&1; then
  stylua --respect-ignores --check home/hypr/.config/hypr || record stylua
else
  echo 'skip: stylua not installed'
fi

sh ./lib/check-packages.sh || record packages
git diff --check HEAD || record 'git-diff-check'
sh ./lib/check-whitespace.sh || record whitespace

if [ -n "$failed" ]; then
  printf 'FAILED:%s\n' "$failed" >&2
  exit 1
fi

echo 'All checks passed'
