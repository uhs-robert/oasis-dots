#!/usr/bin/env bash
# Runs spawn-orchestrator.sh against a private tmux server (-L, never the owner's default one) with a stand-in
# `claude`, then checks the window, the claude arguments, the refusals and that the caller's window keeps its name.
set -uo pipefail
skill=$(cd "$(dirname "$0")" && pwd)/../../skills/orchestrator-handoff
pass=0 fail=0

work=$(mktemp -d)
socket=spawn-orch-test-$$
export TMUX_TMPDIR=$work
unset TMUX TMUX_PANE
t() { tmux -L "$socket" "$@"; }
cleanup() {
  t kill-server 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# The stand-in prints what claude was given, one argument per line, then stays alive.
mkdir "$work/bin"
cat >"$work/bin/claude" <<'STANDIN'
#!/bin/sh
echo "standin budget=${CLAUDE_CONTEXT_BUDGET:-none} args=$#"
for a in "$@"; do echo "arg:$a"; done
sleep 60
STANDIN
chmod +x "$work/bin/claude"

check() {
  local label=$1
  shift
  if "$@"; then
    echo "ok   $label"
    pass=$((pass + 1))
  else
    echo "FAIL $label"
    fail=$((fail + 1))
  fi
}
windows() { t list-windows -a -F '#{window_name}' | sort | tr '\n' ' '; }
has_name() { t list-windows -a -F '#{window_name}' | grep -qx "$1"; }
pane_of() { t capture-pane -p -t "$1"; }

PATH=$work/bin:$PATH t new-session -d -s main -c "$work" "sleep 60" || {
  echo "FAIL could not start the private tmux server"
  exit 1
}
git -C "$work" init -q
# shellcheck disable=SC2016 # the dollar sign is literal test text
printf '/orchestrator Start on the piece. Line one.\nsecond line with "quotes" and $dollar\n' >"$work/prompt.txt"

caller=$(t new-window -d -P -F '#{pane_id}' -n caller "sleep 60")
# spawn [env...] -- args: runs the script from the repo as the pane of the caller window
spawn() { (cd "$work" && TMUX=$(t display-message -p '#{socket_path},#{pid},0') TMUX_PANE=$caller PATH=$work/bin:$PATH "$skill/spawn-orchestrator.sh" "$@"); }
settle() { sleep 1; }

# A plain spawn: no model, no budget, no permission mode
spawn df-one "$work/prompt.txt" >/dev/null 2>&1
check "a good spawn exits 0" test $? -eq 0
settle
check "the window has the given name" has_name df-one
pane=$(pane_of '=main:=df-one')
check "claude gets -n <name> and the prompt as the only arguments" grep -q "standin budget=none args=3" <<<"$pane"
check "claude gets the name" grep -qx "arg:df-one" <<<"$pane"
# shellcheck disable=SC2016 # the dollar sign is literal test text
check "the prompt arrives as one argument, quotes and dollar intact" grep -qF 'second line with "quotes" and $dollar' <<<"$pane"
check "no permission mode flag" bash -c '! grep -q -e "--permission-mode" <<<"$1"' _ "$pane"
check "the window opens in the repo root" test "$(t display-message -p -t '=main:=df-one' '#{pane_current_path}')" = "$(realpath "$work")"
check "the caller keeps its name" test "$(t display-message -p -t "$caller" '#{window_name}')" = caller
check "the new window is not made active" test "$(t display-message -p -t '=main:=df-one' '#{window_active}')" = 0

# A bracketed model must not glob against a file in the cwd
touch "$work/opus1"
spawn df-six "$work/prompt.txt" --model 'opus[1m]' >/dev/null 2>&1
settle
check "a bracketed model reaches --model unglobbed" grep -qx "arg:opus\[1m\]" <<<"$(pane_of '=main:=df-six')"
rm "$work/opus1"

# Run from a linked worktree, the window still opens in the main checkout
git -C "$work" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$work" worktree add -q "$work/wt" -b wt-branch
(cd "$work/wt" && TMUX=$(t display-message -p '#{socket_path},#{pid},0') TMUX_PANE=$caller PATH=$work/bin:$PATH "$skill/spawn-orchestrator.sh" df-seven "$work/prompt.txt" >/dev/null 2>&1)
settle
check "from a linked worktree the window opens in the main checkout" test "$(t display-message -p -t '=main:=df-seven' '#{pane_current_path}')" = "$(realpath "$work")"

# With a model and a budget
spawn df-two "$work/prompt.txt" --model opus --budget 424242 >/dev/null 2>&1
check "a spawn with model and budget exits 0" test $? -eq 0
settle
pane=$(pane_of '=main:=df-two')
check "the budget reaches claude's environment" grep -q "standin budget=424242 args=5" <<<"$pane"
check "the model reaches --model" grep -A1 -x "arg:--model" <<<"$pane" | grep -qx "arg:opus"
spawn df-three "$work/prompt.txt" --budget 1000 --model sonnet >/dev/null 2>&1
settle
check "the flags work in either order" grep -q "standin budget=1000 args=5" <<<"$(pane_of '=main:=df-three')"

# A model name with brackets
spawn df-five "$work/prompt.txt" --model "opus[1m]" >/dev/null 2>&1
check "a model name with brackets is accepted" test $? -eq 0

# A prompt path with a space and a quote
mkdir "$work/dir with 'q' and space"
printf '/orchestrator odd path prompt.\n' >"$work/dir with 'q' and space/p.txt"
spawn df-four "$work/dir with 'q' and space/p.txt" >/dev/null 2>&1
settle
check "an odd prompt path reaches claude intact" grep -q "odd path prompt" <<<"$(pane_of '=main:=df-four')"

# Refusals create nothing and leave the caller alone
before=$(windows)
refused() { # <label> <expected rc> <args...>
  local label=$1 want=$2
  shift 2
  spawn "$@" >/dev/null 2>&1
  local rc=$?
  check "$label" test "$rc" -eq "$want" -a "$(windows)" = "$before"
}
refused "an existing window name is refused" 2 df-one "$work/prompt.txt"
refused "an uppercase name is refused" 2 DF-x "$work/prompt.txt"
refused "a name without a hyphen is refused" 2 dfx "$work/prompt.txt"
refused "a name with a space is refused" 2 "df x" "$work/prompt.txt"
refused "a name with a colon is refused" 2 "df:x" "$work/prompt.txt"
refused "a name starting with a dash is refused" 2 -x "$work/prompt.txt"
refused "a missing prompt file is refused" 2 df-x "$work/none.txt"
refused "a relative prompt path is refused" 2 df-x prompt.txt
printf '\n\n' >"$work/empty.txt"
refused "a prompt file with no text is refused" 2 df-x "$work/empty.txt"
refused "a non-numeric budget is refused" 2 df-x "$work/prompt.txt" --budget lots
refused "a zero budget is refused" 2 df-x "$work/prompt.txt" --budget 0
refused "a model with a shell character is refused" 2 df-x "$work/prompt.txt" --model 'a;b'
refused "a model starting with a dash is refused" 2 df-x "$work/prompt.txt" --model -x
refused "--model without a value is refused" 2 df-x "$work/prompt.txt" --model
refused "an unknown flag is refused" 2 df-x "$work/prompt.txt" --yolo
refused "a missing prompt argument is refused" 2 df-x
refused "no arguments are refused" 2
nogit=$(mktemp -d)
(cd "$nogit" && TMUX=$(t display-message -p '#{socket_path},#{pid},0') TMUX_PANE=$caller "$skill/spawn-orchestrator.sh" df-x "$work/prompt.txt" >/dev/null 2>&1)
check "a spawn outside a git repository is refused and creates nothing" test $? -eq 2 -a "$(windows)" = "$before"
rm -rf "$nogit"
check "the caller still has its name after the refusals" test "$(t display-message -p -t "$caller" '#{window_name}')" = caller

# Outside tmux
(cd "$work" && env -u TMUX -u TMUX_PANE "$skill/spawn-orchestrator.sh" df-x "$work/prompt.txt" >/dev/null 2>&1)
check "outside tmux it exits 3 and creates nothing" test $? -eq 3 -a "$(windows)" = "$before"

# A failing tmux: exit 4, nothing created, the caller keeps its name
mkdir "$work/failbin"
real_tmux=$(command -v tmux)
# shellcheck disable=SC2016 # $1 is for the wrapper to expand
printf '#!/bin/sh\n[ "$1" = new-window ] && exit 1\nexec %s "$@"\n' "$real_tmux" >"$work/failbin/tmux"
chmod +x "$work/failbin/tmux"
(cd "$work" && TMUX=$(t display-message -p '#{socket_path},#{pid},0') TMUX_PANE=$caller PATH=$work/failbin:$work/bin:$PATH "$skill/spawn-orchestrator.sh" df-x "$work/prompt.txt" >/dev/null 2>&1)
check "a failed new-window exits 4 and creates nothing" test $? -eq 4 -a "$(windows)" = "$before"
check "the caller keeps its name after a failed spawn" test "$(t display-message -p -t "$caller" '#{window_name}')" = caller

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
