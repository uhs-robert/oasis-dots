#!/usr/bin/env bash
# Runs the termfilechooser yazi wrapper with a fake TERMCMD that records its argv, and checks that a hostile save path
# reaches the terminal unchanged and runs nothing, also for a terminal named ghostty (1.2.0 and later take argv directly).
set -u

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
wrapper="$repo_dir/home/xdg-desktop-portal/.config/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh"
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

# Records each argument NUL-terminated.
cat >"$work/fake-term" <<'FAKE'
#!/bin/sh
for a in "$@"; do printf '%s\0' "$a"; done >"$RECORD"
FAKE
chmod +x "$work/fake-term"
cp "$work/fake-term" "$work/ghostty-fake"

failures=0
# $1 case name, $2 terminal, $3 hostile path.
run_case() {
  local name="$1" term="$2" path="$3" out="$work/out" expected got
  rm -f "$work/record" "$work/pwned"
  RECORD="$work/record" TERMCMD="$term" sh "$wrapper" 0 0 1 "$path" "$out" 0 || true
  expected=$(printf '%s\0' yazi "--chooser-file=$out" "$path" | od -An -c)
  got=$(od -An -c <"$work/record" 2>/dev/null)
  if [ "$expected" != "$got" ] || [ -e "$work/pwned" ]; then
    printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$name" "$expected" "$got" >&2
    failures=$((failures + 1))
  else
    printf 'ok   %s\n' "$name"
  fi
}

hostile_paths=(
  "$work/\$(touch $work/pwned).png"
  "$work/\`touch $work/pwned\`.png"
  "$work/a b \$HOME \\n \"q\" 'x'.png"
  "$work/ends-in-newline
"
)
for path in "${hostile_paths[@]}"; do
  run_case "plain terminal: ${path:0:40}" "$work/fake-term" "$path"
  run_case "ghostty: ${path:0:40}" "$work/ghostty-fake" "$path"
done

[ "$failures" -eq 0 ]
