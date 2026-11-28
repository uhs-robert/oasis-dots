#!/usr/bin/env bash
# Runs lazygit-edit against a headless nvim on a socket and checks that each awkward file name opens that file, as an
# absolute path, even when the script runs in another directory than the server.
set -u

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
script="$repo_dir/home/lazygit/.config/lazygit/lazygit-edit"
work=$(mktemp -d) || exit 1
server_pid=""
cleanup() {
  [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

mkdir "$work/server_dir" "$work/repo"
sock="$work/nvim.sock"
(cd "$work/server_dir" && exec nvim --headless --clean --listen "$sock") >/dev/null 2>&1 &
server_pid=$!
for _ in $(seq 100); do
  [ -S "$sock" ] && break
  sleep 0.1
done
[ -S "$sock" ] || {
  echo "FAIL: nvim did not start" >&2
  exit 1
}

failures=0
check() {
  local name="$1" file="$2" line="${3:-}" want got
  mkdir -p "$work/repo/$(dirname -- "$file")"
  printf 'one\ntwo\nthree\n' >"$work/repo/$file"
  (cd "$work/repo" && NVIM="$sock" sh "$script" "$file" ${line:+"$line"}) >/dev/null 2>&1
  want="$work/repo/$file"
  got=$(nvim --server "$sock" --remote-expr 'expand("%:p")' 2>&1)
  if [ "$got" != "$want" ]; then
    printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$name" "$want" "$got" >&2
    failures=$((failures + 1))
  elif [ -n "$line" ] && [ "$(nvim --server "$sock" --remote-expr 'line(".")')" != "$line" ]; then
    printf 'FAIL %s: cursor not on line %s\n' "$name" "$line" >&2
    failures=$((failures + 1))
  else
    printf 'ok   %s\n' "$name"
  fi
}

check "plain name" plain.md
check "space" "my file.md"
check "pipe" "a|b.md"
check "quote" "q'x.md"
check "percent" "p%c.md"
check "hash" "h#x.md"
check "key notation" "<CR>x.md"
check "subdirectory" "sub/dir.md"
check "line number" lined.md 2

[ "$failures" -eq 0 ]
