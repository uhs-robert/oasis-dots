#!/bin/bash
# Tests lib/check/steps/shaders.sh on a scratch git tree holding a copy of one committed shader, so no real file changes.
# expect takes its condition as a single-quoted string to eval, so the variables must not expand early.
# shellcheck disable=SC2016
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE QSB SHADER_ROOT

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
step=$repo_dir/lib/check/steps/shaders.sh
sample=$(git -C "$repo_dir" ls-files -- 'home/quickshell/*.frag' | head -n 1)
[ -n "$sample" ] || {
  echo 'FAIL: no tracked .frag to use as a fixture' >&2
  exit 1
}
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

failures=0
expect() {
  if eval "$2"; then printf 'ok   %s\n' "$1"; else
    printf 'FAIL %s\n' "$1" >&2
    failures=$((failures + 1))
  fi
}

# A fresh scratch repo with the sample shader and its .qsb committed.
frag=shader.frag
new_tree() {
  rm -rf "$scratch/tree"
  mkdir "$scratch/tree"
  # The header names the file, so it is rewritten for the fixture's name.
  sed "1s|[^ ]*\\.frag\\.qsb|$frag.qsb|; 1s|[^ ]*\\.frag\$|$frag|" "$repo_dir/$sample" >"$scratch/tree/$frag"
  cp "$repo_dir/$sample.qsb" "$scratch/tree/$frag.qsb"
  git -C "$scratch/tree" init -q
  git -C "$scratch/tree" add -A
  export SHADER_ROOT=$scratch/tree
}
run_step() { sh "$step" "$@" >"$scratch/out" 2>&1; }
# Appends to the shader's body, leaving the header line alone.
edit() { printf '%s\n' "$1" >>"$scratch/tree/$frag"; }

expect "the committed shaders pass" 'sh "$step" >"$scratch/out" 2>&1'

new_tree
if ! sh "$step" >"$scratch/out" 2>&1 || grep -q '^skip:' "$scratch/out"; then
  # Without a compiler only the header check and the skip run.
  expect "a header matching the script's command passes" 'run_step'
else
  expect "an untouched copy passes" 'run_step'

  edit '// a trailing comment'
  expect "a line comment edit passes" 'run_step'
  edit '/* a block
     comment */'
  expect "a block comment edit passes" 'run_step'
  edit ''
  sed -i 's/^\(layout\)/   \1/' "$scratch/tree/$frag"
  expect "a whitespace edit passes" 'run_step'

  new_tree
  # A literal change in the shader body; the first float literal is as good as any.
  sed -i '2,$ s/[0-9][0-9]*\.[0-9][0-9]*/9.75/' "$scratch/tree/$frag"
  expect "a changed shader with an old .qsb fails" '! run_step'
  expect "the failure names the file and the fix" 'grep -q "shader.frag: shader.frag.qsb is stale (run: just shaders" "$scratch/out"'
  expect "--write rebuilds it" 'run_step --write'
  expect "the rebuilt .qsb passes the check" 'run_step'
  qsb_stamp() { stat -c %y "$scratch/tree/$frag.qsb"; }
  qsb_stamp >"$scratch/stamp"
  sleep 0.1
  run_step --write
  expect "a second --write leaves the .qsb alone" '[ "$(qsb_stamp)" = "$(cat "$scratch/stamp")" ]'

  new_tree
  rm "$scratch/tree/$frag.qsb"
  expect "a missing .qsb fails" '! run_step'
  expect "the failure says it is missing" 'grep -q "shader.frag: no shader.frag.qsb (run: just shaders)" "$scratch/out"'
  expect "--write creates a missing .qsb" 'run_step --write && run_step'
fi

new_tree
sed -i '1s/--hlsl 50/--hlsl 51/' "$scratch/tree/$frag"
expect "a header that differs from the script's command fails" '! run_step'
expect "the header failure names the file" 'grep -q "FAIL shader.frag: first line" "$scratch/out"'

new_tree
expect "no qsb skips and passes" 'QSB=$scratch/none run_step && grep -q "^skip: qsb not installed" "$scratch/out"'
expect "--write without qsb fails" '! QSB=$scratch/none run_step --write'

[ "$failures" -eq 0 ] || exit 1
