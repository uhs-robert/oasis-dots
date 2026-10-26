#!/usr/bin/env bash
# Checks the test bar ownership claim, the branch status and the Codex review requests (with the fake gh) against a
# temp cache dir; touches no bar, link or qs.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export XDG_CACHE_HOME=$root/cache
unset CLAUDE_CODE_SESSION_ID CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN
pass=0 fail=0
check() { if eval "$2"; then
  echo "ok   $1"
  pass=$((pass + 1))
else
  echo "FAIL $1"
  fail=$((fail + 1))
fi; }
show() { while IFS= read -r line; do printf '   | %s\n' "$line"; done <<<"$1"; }
# as <session> <socket> <function> <args>...: runs one function of the sourced script as that session.
as() {
  local session=$1 socket=$2
  shift 2
  # shellcheck disable=SC1091
  CLAUDE_CODE_SESSION_ID=$session CLAUDE_CODE_MESSAGING_SOCKET=$socket CLAUDE_CODE_MESSAGING_TOKEN=secret-token \
    bash -c 'source "$1"; shift; "$@"' _ "$here/../owner-test-bar.sh" "$@" 2>&1
}
owner_file=$XDG_CACHE_HOME/dotfiles/test-bars/.owner
sock_a=$root/a.sock
touch "$sock_a"

echo "== no claim"
out=$(as b "$root/b.sock" guard_owner 0)
code=$?
check "passes" "[[ $code == 0 && -z \$out ]]"

echo "== a live claim by another session"
as a "$sock_a" record_owner clicks feat/x fix/y >/dev/null
check "records the address, session and branches" "jq -e '.address == \"uds:$sock_a\" and .session == \"a\" and .branches == [\"feat/x\", \"fix/y\"] and .bar == \"clicks\"' '$owner_file' >/dev/null"
check "never records the token" "! grep -q secret-token '$owner_file'"
out=$(as b "$root/b.sock" guard_owner 0)
code=$?
show "$out"
check "refuses" "[[ $code != 0 ]]"
check "says whom to message" "grep -qF \"test bar 'clicks' (feat/x fix/y) is owned by another session since\" <<<\"\$out\" && grep -qF 'SendMessage to uds:$sock_a to coordinate, or pass --take' <<<\"\$out\""
as a "$sock_a" guard_owner 0 >/dev/null
check "lets the owner session through" "[[ $? == 0 ]]"
as "" "$sock_a" guard_owner 0 >/dev/null
check "matches by socket without a session id" "[[ $? == 0 ]]"
out=$(as b "$root/b.sock" guard_owner 1)
code=$?
show "$out"
check "--take overrides" "[[ $code == 0 ]] && grep -q 'taking test bar' <<<\"\$out\""
out=$(as b "$root/b.sock" owner_status)
check "status says live" "grep -qF \"owner: session a at uds:$sock_a, test bar 'clicks' since\" <<<\"\$out\" && grep -q 'live$' <<<\"\$out\""

echo "== a stale claim"
rm "$sock_a"
out=$(as b "$root/b.sock" guard_owner 0)
code=$?
show "$out"
check "proceeds" "[[ $code == 0 ]]"
check "says it is stale" "grep -q 'is stale' <<<\"\$out\""
out=$(as b "$root/b.sock" owner_status)
check "status says stale" "grep -q 'stale$' <<<\"\$out\""

echo "== branch status"
repo=$root/repo
git init -q -b main "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
g commit -q --allow-empty -m A
g branch kept
g branch moved
g branch gone
g worktree add -q --detach "$root/bar" main
printf '%s\n' kept moved gone >"$root/bar.branches"
out=$(as "" "" branches_state "$root/bar")
check "current while every branch is merged in" "[[ \$out == current ]]"
g switch -q moved
g commit -q --allow-empty -m B
g switch -q main
g branch -q -D gone
out=$(as "" "" branches_state "$root/bar")
show "$out"
check "names the moved and deleted branches" "[[ \$out == 'stale (moved has new commits), branch gone deleted' ]]"

echo "== codex review requests"
export FAKE_GH=$root/gh
mkdir "$FAKE_GH"
echo 7 >"$FAKE_GH/pr-feat-unreviewed"
echo 8 >"$FAKE_GH/pr-feat-reviewed"
echo 9 >"$FAKE_GH/pr-feat-asked"
commits='"commits": [{"committedDate": "2026-10-01T10:00:00Z"}]'
# shellcheck disable=SC2016 # Codex's comment, backticks and all
summary='<!-- codex-pull-request-review-summary --> **Completed** | `abc1234` |'
printf '{"headRefOid": "def5678", %s, "comments": [{"body": "%s", "createdAt": "2026-10-01T11:00:00Z"}]}' \
  "$commits" "$summary" >"$FAKE_GH/view-7.json"
printf '{"headRefOid": "abc1234ff", %s, "comments": [{"body": "%s", "createdAt": "2026-10-01T11:00:00Z"}]}' \
  "$commits" "$summary" >"$FAKE_GH/view-8.json"
printf '{"headRefOid": "aaa", %s, "comments": [{"body": "@codex review", "createdAt": "2026-10-01T11:00:00Z"}]}' \
  "$commits" >"$FAKE_GH/view-9.json"
out=$(PATH="$here:$PATH" as "" "" request_codex_reviews origin/feat-unreviewed feat-reviewed feat-asked feat-no-pr)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "requests a review only of the head nobody reviewed or asked about" "[[ \$(cat '$FAKE_GH/commented') == '7 @codex review' ]]"
check "says what it requested" "[[ \$out == 'codex: requested a review of #7 (feat-unreviewed)' ]]"
out=$(FAKE_GH_DOWN=1 PATH="$here:$PATH" as "" "" request_codex_reviews feat-unreviewed)
code=$?
check "is silent when gh fails" "[[ $code == 0 && -z \$out ]]"

echo "== voxcmd debug log"
export HOME=$root/home XDG_RUNTIME_DIR=$root/run
mkdir -p "$HOME"
debug_log=$XDG_RUNTIME_DIR/voxcmd/debug.log
out=$(as "" "" voxcmd_debug_start)
show "$out"
check "a swap creates the log and prints its path" "[[ -f $debug_log && \$out == 'voxcmd: debug log at $debug_log' ]]"
as "" "" voxcmd_restore >/dev/null
check "restore deletes a log the swap created" "[[ ! -e $debug_log ]]"
mkdir -p "$XDG_RUNTIME_DIR/voxcmd"
echo owner >"$debug_log"
as "" "" voxcmd_debug_start >/dev/null
as "" "" voxcmd_restore >/dev/null
check "restore keeps a log the owner turned on" "[[ \$(cat $debug_log) == owner ]]"
rm -f "$debug_log"

echo "== try"
bar=$XDG_CACHE_HOME/dotfiles/test-bars/clicks/home/voxcmd
mkdir -p "$bar/.local/bin" "$bar/.config/voxcmd" "$HOME/.local/bin"
# shellcheck disable=SC2016 # the stub's own variables, not this script's
stub='#!/usr/bin/env bash
echo "config ${VOXCMD_CONFIG_DIR:-none}" >&2
case $2 in *toolong*) echo "result:      refused, too many steps" ;; *nowhere*) echo "result:      no match" ;; *) echo "result:      run"; echo "option 1:    Keybinds (keybinds.sh) action=run" ;; esac'
printf '%s\n' "$stub" >"$HOME/.local/bin/voxcmd"
chmod +x "$HOME/.local/bin/voxcmd"
out=$(as "" "" try_phrases "focus workspace 3" "go nowhere")
code=$?
show "$out"
check "uses the main install and says so" "grep -q 'using the main install' <<<\"\$out\""
check "prints one line per phrase" "grep -qF '\"focus workspace 3\": run -> Keybinds' <<<\"\$out\" && grep -qF '\"go nowhere\": no match' <<<\"\$out\""
check "exits 1 on a no match" "[[ $code == 1 ]]"
out=$(as "" "" try_phrases "focus workspace 3")
check "exits 0 when every phrase matches" "[[ \$? == 0 ]]"
cp "$HOME/.local/bin/voxcmd" "$bar/.local/bin/voxcmd"
rm "$HOME/.local/bin/voxcmd"
ln -s "$bar/.local/bin/voxcmd" "$HOME/.local/bin/voxcmd"
mkdir -p "$HOME/.config"
ln -s "$bar/.config/voxcmd" "$HOME/.config/voxcmd"
echo clicks >"$XDG_CACHE_HOME/dotfiles/test-bars/.voxcmd_bar"
out=$(as "" "" try_phrases "go nowhere")
code=$?
show "$out"
check "uses the live test build and its config" "grep -q 'try: test build clicks' <<<\"\$out\" && [[ $code == 1 ]]"

out=$(as "" "" try_phrases "toolong phrase")
check "a refused sequence exits 1" "[[ \$? == 1 ]] && grep -q 'refused' <<<\"\$out\""
rm "$XDG_CACHE_HOME/dotfiles/test-bars/.voxcmd_bar"
out=$(as "" "" try_phrases "focus workspace 3")
code=$?
check "half swapped refuses and names restore" "[[ $code == 1 ]] && grep -q 'half swapped; run restore' <<<\"\$out\" && ! grep -q 'main install' <<<\"\$out\""

echo "== debug marker after a reboot"
rm -rf "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_RUNTIME_DIR/voxcmd"
echo owner >"$debug_log"
as "" "" voxcmd_debug_stop >/dev/null
check "a stale marker cannot delete the owner's later log" "[[ \$(cat $debug_log) == owner ]]"

echo "== rs-swap"
# A throwaway HOME with a stowed fake voxcmd package and stubbed systemd-run, systemctl and Rust voxcmd; the real
# stow runs, since the risk is stow aborting on the foreign link.
rs_home=$root/rs_home
rs_repo=$root/rs_repo
stubs=$root/stubs
calls=$root/calls
bars_dir=$XDG_CACHE_HOME/dotfiles/test-bars
export XDG_RUNTIME_DIR=$root/rs_run
mkdir -p "$rs_home/.local/bin" "$rs_home/.config" "$XDG_RUNTIME_DIR/voxcmd" "$stubs" \
  "$rs_repo/home/voxcmd/.local/bin" "$rs_repo/home/voxcmd/.config/voxcmd"
touch "$rs_repo/home/voxcmd/.local/bin/voxcmd" "$rs_repo/home/voxcmd/.config/voxcmd/keybinds.sh"
stow -d "$rs_repo/home" -t "$rs_home" voxcmd
# rs-swap requires the script to be the main checkout's own copy, which resolves through this symlink.
# It is a git repo so the sourced script finds its main checkout the way it does for real.
git init -q "$rs_repo"
mkdir -p "$rs_repo/.claude/skills/owner-test-bar"
rs_script=$rs_repo/.claude/skills/owner-test-bar/owner-test-bar.sh
ln -s "$here/../owner-test-bar.sh" "$rs_script"
rs_bin=$rs_home/.local/share/voxcmd-rs/bin/voxcmd
stow_target=$rs_repo/home/voxcmd/.local/bin/voxcmd
cat >"$stubs/systemd-run" <<STUB
#!/usr/bin/env bash
echo "systemd-run \$*" >>"$calls"
[[ -z \${FAKE_TIMER_FAIL:-} ]] || exit 1
touch "$root/timer_active"
STUB
cat >"$stubs/systemctl" <<STUB
#!/usr/bin/env bash
echo "systemctl \$*" >>"$calls"
case \$* in
*is-active*) [[ -f "$root/timer_active" ]] ;;
*stop*) rm -f "$root/timer_active" ;;
esac
STUB
chmod +x "$stubs/systemd-run" "$stubs/systemctl"
# rsx <function> <args>...: one function of the sourced script, with the fake repo, HOME and stubs.
rsx() {
  PATH="$stubs:$PATH" HOME=$rs_home bash -c 'source "$1"; repo=$2; shift 2; "$@"' _ \
    "$rs_script" "$rs_repo" "$@" 2>&1
}
link_is() { [[ $(readlink -m "$rs_home/.local/bin/voxcmd") == "$1" ]]; }
calls_count() { if [[ -f $calls ]]; then wc -l <"$calls"; else echo 0; fi; }
reset_calls() { rm -f "$calls" "$root/timer_active"; }

reset_calls
out=$(rsx main rs-swap)
code=$?
show "$out"
check "refuses while voxcmd-rs is not built" "[[ $code != 0 ]] && grep -q 'is not built' <<<\"\$out\" && link_is '$stow_target' && [[ ! -e $bars_dir/.voxcmd_rs && \$(calls_count) == 0 ]]"

mkdir -p "${rs_bin%/*}"
printf '#!/usr/bin/env bash\necho "rs voxcmd $*" >>"%s"\n' "$calls" >"$rs_bin"
chmod +x "$rs_bin"
touch "$XDG_RUNTIME_DIR/voxcmd/session.json"
out=$(rsx main rs-swap)
code=$?
check "refuses while a voxcmd session is open" "[[ $code != 0 ]] && grep -q 'voxcmd stop' <<<\"\$out\" && link_is '$stow_target'"
rm "$XDG_RUNTIME_DIR/voxcmd/session.json"

out=$(rsx main rs-swap)
code=$?
show "$out"
check "swaps with the default of 60 minutes" "[[ $code == 0 ]] && link_is '$rs_bin' && grep -q -- '--on-active=60m' '$calls' && grep -q 'rs-restore' '$calls'"
check "leaves the helper links and the config link alone" "[[ -L $rs_home/.config/voxcmd ]] && [[ \$(readlink -m $rs_home/.config/voxcmd) == $rs_repo/home/voxcmd/.config/voxcmd ]]"
out=$(rsx voxcmd_status)
check "status shows Rust and the time left" "[[ \$out == 'voxcmd: Rust (restores in 60 min)' ]]"

check "the timer unit gets the cache and runtime paths" "grep -qF -- '--setenv=XDG_CACHE_HOME=$XDG_CACHE_HOME' '$calls' && grep -qF -- '--setenv=XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR' '$calls'"

timers_started() { grep -c '^systemd-run' "$calls" || true; }
before=$(timers_started)
out=$(rsx main rs-swap 5)
code=$?
check "a second swap is refused and starts no second timer" "[[ $code != 0 ]] && grep -q 'already swapped' <<<\"\$out\" && [[ \$(timers_started) == $before ]]"
out=$(rsx main try 'x')
code=$?
check "try refuses while swapped" "[[ $code != 0 ]] && grep -q 'Rust build' <<<\"\$out\""

echo "== rs restore"
: >"$calls"
out=$(rsx voxcmd_restore)
code=$?
show "$out"
check "restore relinks the stow link despite the foreign link" "[[ $code == 0 ]] && link_is '$stow_target' && [[ ! -e $bars_dir/.voxcmd_rs ]]"
check "restore stops the Rust session and the timer" "grep -q 'rs voxcmd stop' '$calls' && grep -q 'systemctl --user stop voxcmd-rs-restore.timer' '$calls' && [[ ! -f $root/timer_active ]]"
check "status is main again" "[[ \$(rsx voxcmd_status) == 'voxcmd: main' ]]"

: >"$calls"
out=$(rsx voxcmd_restore)
code=$?
check "restore with no swap is a no-op" "[[ $code == 0 && \$out == 'voxcmd: main' && \$(calls_count) == 0 ]] && link_is '$stow_target'"

echo "== rs timer fired"
reset_calls
rsx main rs-swap 5 >/dev/null
# the timer has fired: its unit is gone and the deadline is past
rm -f "$root/timer_active"
echo $(($(date +%s) - 10)) >"$bars_dir/.voxcmd_rs"
out=$(rsx voxcmd_status)
check "status says the restore is overdue" "grep -q 'Rust (restore overdue' <<<\"\$out\""
out=$(rsx main rs-restore)
check "the timer's restore command puts main back" "[[ \$? == 0 ]] && link_is '$stow_target' && [[ ! -e $bars_dir/.voxcmd_rs ]]"
out=$(rsx voxcmd_restore)
check "restore after the timer fired is a no-op" "[[ \$? == 0 && \$out == 'voxcmd: main' ]] && link_is '$stow_target'"

echo "== rs crash: link on rs, no timer"
reset_calls
rsx main rs-swap 5 >/dev/null
rm -f "$root/timer_active"
out=$(rsx voxcmd_status)
check "status says the timer is lost" "grep -q 'Rust (restore timer lost, [45] min left' <<<\"\$out\""
rm -f "$bars_dir/.voxcmd_rs"
out=$(rsx voxcmd_status)
check "status says half swapped when the marker is gone too" "grep -q 'half swapped' <<<\"\$out\""
out=$(rsx main rs-swap 5)
check "a new swap is refused until restore" "[[ \$? != 0 ]] && grep -q 'restore first' <<<\"\$out\""
out=$(rsx voxcmd_restore)
check "restore recovers it" "[[ \$? == 0 ]] && link_is '$stow_target' && [[ \$(rsx voxcmd_status) == 'voxcmd: main' ]]"

echo "== rs: bare stow -R while swapped"
reset_calls
rsx main rs-swap 5 >/dev/null
out=$(stow -d "$rs_repo/home" -t "$rs_home" -R voxcmd 2>&1)
check "a bare stow -R aborts on the foreign link, which is why restore removes it first" "[[ \$? != 0 ]] && link_is '$rs_bin'"
out=$(rsx voxcmd_restore)
check "restore's stow -R succeeds while swapped" "[[ \$? == 0 ]] && link_is '$stow_target'"

echo "== rs: the permanent voxcmd-rs alias"
reset_calls
ln -s "$rs_bin" "$rs_home/.local/bin/voxcmd-rs"
check "status stays main when only the alias exists" "[[ \$(rsx voxcmd_status) == 'voxcmd: main' ]]"
rsx voxcmd_restore >/dev/null
check "restore with no swap keeps the alias" "[[ -L $rs_home/.local/bin/voxcmd-rs ]]"
rsx main rs-swap 5 >/dev/null
rsx voxcmd_restore >/dev/null
check "restore after an rs swap keeps the alias and relinks main" "[[ -L $rs_home/.local/bin/voxcmd-rs ]] && link_is '$stow_target'"
rm "$rs_home/.local/bin/voxcmd-rs"

echo "== rs: a symlinked data dir"
reset_calls
ln -s "$rs_home/.local/share" "$root/data_link"
XDG_DATA_HOME=$root/data_link rsx main rs-swap 5 >/dev/null
out=$(XDG_DATA_HOME=$root/data_link rsx voxcmd_status)
check "status recognises the Rust link" "[[ \$out == 'voxcmd: Rust (restores in '* ]]"
XDG_DATA_HOME=$root/data_link rsx voxcmd_restore >/dev/null
check "restore leaves voxcmd on main" "[[ \$? == 0 ]] && link_is '$stow_target' && [[ ! -e $bars_dir/.voxcmd_rs ]]"
rm "$root/data_link"

echo "== rs: the data dir and the checkout"
reset_calls
XDG_DATA_HOME=$rs_home/.local/share rsx main rs-swap 5 >/dev/null
check "the timer unit gets a caller's XDG_DATA_HOME" "grep -qF -- '--setenv=XDG_DATA_HOME=$rs_home/.local/share' '$calls'"
rsx voxcmd_restore >/dev/null
reset_calls
ln -sfn "$root/stale/voxcmd" "$rs_home/.local/bin/voxcmd"
out=$(rsx main rs-swap 5)
code=$?
check "rs-swap refuses a link that is not main's voxcmd, and leaves it" "[[ $code != 0 ]] && grep -q 'main checkout' <<<\"\$out\" && link_is '$root/stale/voxcmd' && [[ \$(calls_count) == 0 ]]"
ln -sfn "$stow_target" "$rs_home/.local/bin/voxcmd"
other_script=$root/worktree/owner-test-bar.sh
mkdir -p "${other_script%/*}"
cp "$here/../owner-test-bar.sh" "$other_script"
out=$(PATH="$stubs:$PATH" HOME=$rs_home bash -c 'source "$1"; repo=$2; shift 2; "$@"' _ "$other_script" "$rs_repo" main rs-swap 2>&1)
code=$?
check "rs-swap refuses a script outside the main checkout" "[[ $code != 0 ]] && grep -q 'from the main checkout' <<<\"\$out\" && link_is '$stow_target' && [[ \$(calls_count) == 0 && ! -e $bars_dir/.voxcmd_rs ]]"

echo "== rs: test-bar commands while swapped"
reset_calls
rsx main rs-swap 5 >/dev/null
for cmd in "swap clicks" "up clicks feat/x" "rebuild clicks"; do
  rm -f "$bars_dir/.owner"
  # shellcheck disable=SC2086
  out=$(PATH="$stubs:$PATH" HOME=$rs_home bash "$rs_script" $cmd 2>&1)
  code=$?
  check "'$cmd' is refused before it claims the bar" "[[ $code != 0 ]] && grep -q 'runs the Rust build' <<<\"\$out\" && [[ ! -e $bars_dir/.owner ]] && link_is '$rs_bin'"
done
rsx voxcmd_restore >/dev/null

echo "== rs: a voxcmd test bar is up"
reset_calls
bar_bin=$bars_dir/clicks/home/voxcmd/.local/bin
mkdir -p "$bar_bin"
touch "$bar_bin/voxcmd"
ln -sfn "$bar_bin/voxcmd" "$rs_home/.local/bin/voxcmd"
ln -sfn "$bars_dir/clicks/home/voxcmd/.config/voxcmd" "$rs_home/.config/voxcmd"
echo clicks >"$bars_dir/.voxcmd_bar"
out=$(rsx main rs-swap)
code=$?
show "$out"
check "rs-swap refuses and leaves the test build linked" "[[ $code != 0 ]] && grep -q 'not on main' <<<\"\$out\" && link_is '$bar_bin/voxcmd' && [[ \$(calls_count) == 0 ]]"
out=$(rsx voxcmd_restore)
check "restore of the test build is unchanged" "[[ \$? == 0 ]] && link_is '$stow_target' && [[ ! -e $bars_dir/.voxcmd_bar ]]"

echo "== rs: the timer cannot start"
reset_calls
FAKE_TIMER_FAIL=1 rsx main rs-swap 5 >/dev/null
check "the swap is undone" "[[ \$? != 0 ]] && link_is '$stow_target' && [[ ! -e $bars_dir/.voxcmd_rs ]]"

echo "== voxtype swap and restore"
# A fork that deleted the bash voxcmd: the swap builds the crate in the bar (stub cargo) and links the built binary.
echo "== rust-only voxcmd test build"
rr_repo=$root/rr_repo
rr_home=$root/rr_home
rr_stubs=$root/rr_stubs
rr_calls=$root/rr_calls
rr_dir=$bars_dir/rustbar
rr_main_bin=$rr_repo/home/voxcmd/.local/bin/voxcmd
mkdir -p "$rr_stubs" "$rr_home/.local/bin" "$rr_home/.config" "$rr_repo/home/voxcmd/.local/bin" \
  "$rr_repo/home/voxcmd/.config/voxcmd" "$rr_repo/.claude/skills/owner-test-bar"
git init -q -b main "$rr_repo"
rg() { git -C "$rr_repo" -c user.name=t -c user.email=t@t "$@"; }
# shellcheck disable=SC2016 # the stub's own variables
printf '#!/usr/bin/env bash\necho "bash voxcmd $*" >>"%s"\necho "result: bash"\n' "$rr_calls" >"$rr_main_bin"
chmod +x "$rr_main_bin"
echo main >"$rr_repo/home/voxcmd/.local/bin/voxcmd-alarm"
echo main >"$rr_repo/home/voxcmd/.config/voxcmd/keybinds.sh"
ln -s "$here/../owner-test-bar.sh" "$rr_repo/.claude/skills/owner-test-bar/owner-test-bar.sh"
rg add -A
rg commit -q -m main
rg update-ref refs/remotes/origin/main HEAD
rg switch -q -c rust
rg rm -q home/voxcmd/.local/bin/voxcmd
mkdir -p "$rr_repo/home/voxcmd/src"
echo '[package]' >"$rr_repo/home/voxcmd/Cargo.toml"
echo rust >"$rr_repo/home/voxcmd/.local/bin/voxcmd-alarm"
rg add -A
rg commit -q -m rust
rg switch -q main
rg worktree add -q --detach "$rr_dir" rust
stow -d "$rr_repo/home" -t "$rr_home" voxcmd
cat >"$rr_stubs/cargo" <<STUB
#!/usr/bin/env bash
echo "cargo \$* hash=\${VOXCMD_GIT_HASH:-}" >>"$rr_calls"
[[ -z \${FAKE_CARGO_FAIL:-} ]] || { echo "error: could not compile" >&2; exit 101; }
all_args="\$*"
manifest_dir=\${all_args#*--manifest-path }
manifest_dir=\$(dirname "\${manifest_dir%% *}")
# Never write outside the test's temp dir, whatever the arguments were.
[[ \$manifest_dir == "$root"/* ]] || { echo "stub cargo: refusing \$manifest_dir" >&2; exit 1; }
# Like cargo: --target-dir wins over CARGO_TARGET_DIR, which wins over the crate's own target.
out_dir=\$manifest_dir/target
[[ -z \${CARGO_TARGET_DIR:-} ]] || out_dir=\$CARGO_TARGET_DIR
[[ \$all_args != *--target-dir* ]] || { out_dir=\${all_args#*--target-dir }; out_dir=\${out_dir%% *}; }
[[ -z \${FAKE_CARGO_NO_BIN:-} ]] || exit 0
[[ \$out_dir == "$root"/* ]] || { echo "stub cargo: refusing \$out_dir" >&2; exit 1; }
mkdir -p "\$out_dir/release"
{
  echo '#!/usr/bin/env bash'
  echo 'echo "rust voxcmd \$*" >>"$rr_calls"'
  echo 'echo "result: rust"'
} >"\$out_dir/release/voxcmd"
chmod +x "\$out_dir/release/voxcmd"
STUB
chmod +x "$rr_stubs/cargo"
# rrx <function> <args>...: the sourced script against the fake repo and HOME; the stubs go first on PATH.
rrx() {
  PATH="$rr_stubs:$PATH" HOME=$rr_home XDG_RUNTIME_DIR=$root/rr_run bash -c 'source "$1"; repo=$2; shift 2; "$@"' _ \
    "$rr_repo/.claude/skills/owner-test-bar/owner-test-bar.sh" "$rr_repo" "$@" 2>&1
}
# The swap command with the desktop-touching steps stubbed to log, so the order against the build is visible.
# shellcheck disable=SC2016
rr_swap_cmd() {
  PATH="$rr_stubs:$PATH" HOME=$rr_home XDG_RUNTIME_DIR=$root/rr_run bash -c 'source "$1"; repo=$2; shift 2
    require_unlocked() { :; }; launch() { :; }; verify() { :; }; guard_owner() { :; }; guard_live_bar() { :; }
    djinn_swap() { echo "djinn_swap" >>"$RR_CALLS"; }; hypr_swap() { echo "hypr_swap" >>"$RR_CALLS"; }
    voxtype_swap() { :; }; main swap rustbar' _ "$rr_repo/.claude/skills/owner-test-bar/owner-test-bar.sh" "$rr_repo" 2>&1
}
rr_link_is() { [[ $(readlink -m "$rr_home/.local/bin/$1") == "$2" ]]; }
export RR_CALLS=$rr_calls
echo rustbar >"$bars_dir/rustbar.branches"

rm -f "$rr_calls"
out=$(FAKE_CARGO_FAIL=1 rr_swap_cmd)
code=$?
show "$out"
check "a failed build dies, says nothing was swapped, and leaves main linked" "[[ $code != 0 ]] && grep -q 'cargo build fails' <<<\"\$out\" && rr_link_is voxcmd '$rr_main_bin' && [[ ! -e $bars_dir/.voxcmd_bar && ! -e $bars_dir/.hypr_bar ]]"
check "the failed build ran before Hyprland and the manifest were touched" "! grep -q '_swap' '$rr_calls'"
check "the failed build leaves the voxcmd status on main" "[[ \$(rrx voxcmd_status) == 'voxcmd: main' ]]"

# A cargo that builds elsewhere (CARGO_TARGET_DIR in the environment) must not leave a dangling link.
rm -f "$rr_calls"
out=$(CARGO_TARGET_DIR=$root/elsewhere CARGO_BUILD_TARGET=x rr_swap_cmd)
code=$?
check "an environment target dir does not move the build output, and the link is real" "[[ $code == 0 && -x $rr_dir/home/voxcmd/target/release/voxcmd && ! -e $root/elsewhere ]] && rr_link_is voxcmd '$rr_dir/home/voxcmd/target/release/voxcmd'"
rrx voxcmd_restore >/dev/null
rm -rf "$rr_dir/home/voxcmd/target"
rm -f "$bars_dir/.owner"
rm -f "$rr_calls"
out=$(FAKE_CARGO_NO_BIN=1 rr_swap_cmd)
code=$?
check "a build that produces no binary dies before anything swaps" "[[ $code != 0 ]] && grep -q 'cargo built no' <<<\"\$out\" && ! grep -q '_swap' '$rr_calls' && rr_link_is voxcmd '$rr_main_bin'"
rm -f "$bars_dir/.owner"

# A binary left by an earlier build must not pass for this build's output.
mkdir -p "$rr_dir/home/voxcmd/target/release"
printf '#!/usr/bin/env bash\necho stale\n' >"$rr_dir/home/voxcmd/target/release/voxcmd"
chmod +x "$rr_dir/home/voxcmd/target/release/voxcmd"
rm -f "$rr_calls"
out=$(FAKE_CARGO_NO_BIN=1 rr_swap_cmd)
code=$?
check "a stale binary from an earlier build does not pass for a build that produced none" "[[ $code != 0 ]] && grep -q 'cargo built no' <<<\"\$out\" && ! grep -q '_swap' '$rr_calls' && rr_link_is voxcmd '$rr_main_bin'"
rm -rf "$rr_dir/home/voxcmd/target"
rrx voxcmd_restore >/dev/null
rm -f "$bars_dir/.owner"

# A failed build must not leave a claim for a bar that was never swapped in.
check "a failed build leaves no owner claim" "[[ ! -e $bars_dir/.owner ]]"

# A regular file at the link slot is never clobbered.
mv "$rr_home/.local/bin/voxcmd" "$root/voxcmd_aside"
echo "user file" >"$rr_home/.local/bin/voxcmd"
rm -f "$rr_calls"
out=$(rr_swap_cmd)
code=$?
check "a regular file at the voxcmd link slot is refused before the build, and kept" "[[ $code != 0 ]] && grep -q 'not a symlink' <<<\"\$out\" && [[ -f $rr_home/.local/bin/voxcmd && ! -L $rr_home/.local/bin/voxcmd && \$(<$rr_home/.local/bin/voxcmd) == 'user file' ]] && ! grep -q '^cargo' '$rr_calls' 2>/dev/null"
rm "$rr_home/.local/bin/voxcmd"
mv "$root/voxcmd_aside" "$rr_home/.local/bin/voxcmd"

rm -f "$rr_calls"
out=$(rr_swap_cmd)
code=$?
show "$out"
check "the swap builds with cargo release, locked, on the bar's manifest, with a git hash" "[[ $code == 0 ]] && grep -qE '^cargo build --release --locked --manifest-path $rr_dir/home/voxcmd/Cargo.toml --target-dir $rr_dir/home/voxcmd/target hash=.+' '$rr_calls'"
check "the build runs before the Hyprland and manifest swap" "[[ \$(grep -n '^cargo' '$rr_calls' | head -1 | cut -d: -f1) -lt \$(grep -n '_swap' '$rr_calls' | head -1 | cut -d: -f1) ]]"
check "voxcmd links into the bar's built binary" "rr_link_is voxcmd '$rr_dir/home/voxcmd/target/release/voxcmd'"
check "the bar's helper scripts and config are linked too" "rr_link_is voxcmd-alarm '$rr_dir/home/voxcmd/.local/bin/voxcmd-alarm' && [[ \$(readlink -m $rr_home/.config/voxcmd) == $rr_dir/home/voxcmd/.config/voxcmd ]]"
check "status reads test build" "[[ \$(rrx voxcmd_status) == 'voxcmd: test build rustbar' ]]"

rm -f "$rr_calls"
out=$(rrx try_phrases "go home")
code=$?
show "$out"
check "try runs explain on a Rust test build and reads its result" "[[ $code == 0 ]] && grep -q 'rust voxcmd explain go home' '$rr_calls' && ! grep -q -- '--dry-run' '$rr_calls' && grep -q '\"go home\": rust' <<<\"\$out\""

out=$(rrx voxcmd_restore)
code=$?
check "restore restows main's bash voxcmd" "[[ $code == 0 ]] && rr_link_is voxcmd '$rr_main_bin' && rr_link_is voxcmd-alarm '$rr_repo/home/voxcmd/.local/bin/voxcmd-alarm' && [[ ! -e $bars_dir/.voxcmd_bar ]] && [[ \$(rrx voxcmd_status) == 'voxcmd: main' ]]"
rm -f "$rr_calls"
out=$(rrx try_phrases "go home")
check "try keeps --dry-run for the bash voxcmd" "grep -q 'bash voxcmd --dry-run go home' '$rr_calls' && ! grep -q 'explain' '$rr_calls'"
rm -f "$bars_dir/.owner" "$bars_dir/rustbar.branches"

# A throwaway HOME and git repo with a stowed voxtype and systemd package; the real stow runs, and systemctl is a fake that
# logs every call in order next to the stow calls, so the lifecycle order is checked. Nothing here reaches the user manager.
vt_repo=$root/vt_repo
vt_home=$root/vt_home
vt_stubs=$root/vt_stubs
vt_calls=$root/vt_calls
vt_units=$vt_home/.config/systemd/user
vt_dir=$bars_dir/duck
real_stow=$(command -v stow)
mkdir -p "$vt_stubs" "$vt_home/.local/bin" "$vt_units"
git init -q -b main "$vt_repo"
vg() { git -C "$vt_repo" -c user.name=t -c user.email=t@t "$@"; }
mkdir -p "$vt_repo/home/voxtype/.local/bin" "$vt_repo/home/voxtype/.config/voxtype" "$vt_repo/home/voxtype/tests" \
  "$vt_repo/home/systemd/.config/systemd/user/voxtype.service.d" "$vt_repo/.claude/skills/owner-test-bar"
echo main >"$vt_repo/home/voxtype/.local/bin/voxtype-daemon"
echo main >"$vt_repo/home/voxtype/.local/bin/voxtype-old"
echo main >"$vt_repo/home/systemd/.config/systemd/user/old.service"
echo main >"$vt_repo/home/systemd/.config/systemd/user/other.service"
echo main >"$vt_repo/home/voxtype/.config/voxtype/config.toml"
echo main >"$vt_repo/home/systemd/.config/systemd/user/hyprland-session.target"
echo main >"$vt_repo/home/systemd/.config/systemd/user/voxtype.service.d/prompt.conf"
ln -s "$here/../owner-test-bar.sh" "$vt_repo/.claude/skills/owner-test-bar/owner-test-bar.sh"
vg add -A
vg commit -q -m main
vg update-ref refs/remotes/origin/main HEAD
# The branches: one adds a follower unit and script and changes the config, one only touches voxtype's tests.
vg switch -q -c duck
echo duck >"$vt_repo/home/voxtype/.local/bin/voxtype-duck"
echo duck >"$vt_repo/home/voxtype/.config/voxtype/config.toml"
echo duck >"$vt_repo/home/systemd/.config/systemd/user/voxtype-duck.service"
echo duck >"$vt_repo/home/systemd/.config/systemd/user/voxtype.service.d/duck.conf"
vg add -A
vg commit -q -m duck
vg switch -q -c deletes main
vg rm -q home/voxtype/.local/bin/voxtype-old home/systemd/.config/systemd/user/old.service \
  home/systemd/.config/systemd/user/voxtype.service.d/prompt.conf
vg commit -q -m deletes
vg switch -q -c mod main
echo mod >"$vt_repo/home/systemd/.config/systemd/user/other.service"
echo mod >"$vt_repo/home/systemd/.config/systemd/user/voxtype.service.d/prompt.conf"
mkdir "$vt_repo/home/systemd/.config/systemd/user/third.service.d"
echo mod >"$vt_repo/home/systemd/.config/systemd/user/third.service.d/x.conf"
vg add -A
vg commit -q -m mod
vg switch -q -c tests main
echo t >"$vt_repo/home/voxtype/tests/t.sh"
vg add -A
vg commit -q -m tests
vg switch -q main
vg worktree add -q --detach "$bars_dir/duck" duck
vg worktree add -q --detach "$bars_dir/tests" tests
vg worktree add -q --detach "$bars_dir/plain" main
vg worktree add -q --detach "$bars_dir/deletes" deletes
vg worktree add -q --detach "$bars_dir/mod" mod
cat >"$vt_stubs/systemctl" <<STUB
#!/usr/bin/env bash
echo "systemctl \$*" >>"$vt_calls"
case \$* in
# A plain restart starts a stopped unit; try-restart leaves it alone, which is what keeps this marker absent.
"--user restart voxtype") touch "$root/voxtype_started" ;;
*"is-enabled"*) [[ -z \${FAKE_NOT_ENABLED:-} ]] || exit 1 ;;
*"disable --now "*) [[ -z \${FAKE_DISABLE_FAIL:-} || \$* != *"\$FAKE_DISABLE_FAIL" ]] || exit 1 ;;
*"enable --now "*) [[ -z \${FAKE_ENABLE_FAIL:-} || \$* != *"\$FAKE_ENABLE_FAIL" ]] || exit 1 ;;
esac
STUB
cat >"$vt_stubs/stow" <<STUB
#!/usr/bin/env bash
echo "stow \$*" >>"$vt_calls"
exec "$real_stow" "\$@"
STUB
chmod +x "$vt_stubs/systemctl" "$vt_stubs/stow"
# vtx <function> <args>...: the sourced script against the fake repo and HOME; the stubs go first on PATH.
vtx() {
  PATH="$vt_stubs:$PATH" HOME=$vt_home bash -c 'source "$1"; repo=$2; shift 2; "$@"' _ \
    "$vt_repo/.claude/skills/owner-test-bar/owner-test-bar.sh" "$vt_repo" "$@" 2>&1
}
vt_link_is() { [[ $(readlink -m "$1") == "$2" ]]; }
vt_order() { grep -n "$1" "$vt_calls" | head -1 | cut -d: -f1; }
vt_reset() { rm -f "$vt_calls" "$bars_dir/.voxtype_bar" "$bars_dir/.voxtype_enabled"; }
vt_main() {
  stow -d "$vt_repo/home" -t "$vt_home" voxtype
  stow -d "$vt_repo/home" -t "$vt_home" --no-folding systemd
}
rm -rf "$vt_home/.config/voxtype" "$vt_home/.local/bin/voxtype-"* "$vt_units"
vt_main
vt_main_config=$vt_repo/home/voxtype/.config/voxtype
vt_main_bin=$vt_repo/home/voxtype/.local/bin/voxtype-daemon

vt_reset
out=$(vtx voxtype_swap plain "$bars_dir/plain")
check "a branch without voxtype or systemd changes does nothing" "[[ \$out == 'voxtype: unchanged' && ! -e $vt_calls && ! -e $bars_dir/.voxtype_bar ]] && vt_link_is $vt_home/.config/voxtype $vt_main_config"
out=$(vtx voxtype_swap tests "$bars_dir/tests")
check "a change only to voxtype's tests does nothing" "[[ \$out == 'voxtype: unchanged' && ! -e $vt_calls ]]"
out=$(vtx voxtype_restore)
check "restore with nothing swapped touches nothing" "[[ -z \$out && ! -e $vt_calls ]]"
out=$(vtx voxtype_status)
check "status is main" "[[ \$out == 'voxtype: main' ]]"

out=$(vtx voxtype_swap duck "$bars_dir/duck")
code=$?
show "$out"
check "swap succeeds and names the enabled unit" "[[ $code == 0 && \$out == 'voxtype: test build duck (enabled voxtype-duck.service)' ]]"
check "links the config, the scripts and the changed units into the test build" "vt_link_is $vt_home/.config/voxtype $vt_dir/home/voxtype/.config/voxtype && vt_link_is $vt_home/.local/bin/voxtype-duck $vt_dir/home/voxtype/.local/bin/voxtype-duck && vt_link_is $vt_home/.local/bin/voxtype-daemon $vt_dir/home/voxtype/.local/bin/voxtype-daemon && vt_link_is $vt_units/voxtype-duck.service $vt_dir/home/systemd/.config/systemd/user/voxtype-duck.service && vt_link_is $vt_units/voxtype.service.d/duck.conf $vt_dir/home/systemd/.config/systemd/user/voxtype.service.d/duck.conf"
check "leaves units the branch did not change on main" "vt_link_is $vt_units/hyprland-session.target $vt_repo/home/systemd/.config/systemd/user/hyprland-session.target"
check "reloads, restarts voxtype, and only then enables the follower" "[[ \$(vt_order 'daemon-reload') -lt \$(vt_order 'try-restart voxtype') && \$(vt_order 'try-restart voxtype') -lt \$(vt_order 'enable --now voxtype-duck.service') ]]"
check "records the bar and the enabled unit" "[[ \$(cat $bars_dir/.voxtype_bar) == duck && \$(cat $bars_dir/.voxtype_enabled) == voxtype-duck.service ]]"
out=$(vtx voxtype_status)
check "status shows the test build" "[[ \$out == 'voxtype: test build duck (enabled: voxtype-duck.service)' ]]"

: >"$vt_calls"
out=$(vtx voxtype_restore)
code=$?
show "$out"
check "restore succeeds" "[[ $code == 0 && \$out == 'voxtype: main' ]]"
check "restore disables the follower, then restows, reloads and restarts, in that order" "[[ \$(vt_order 'disable --now voxtype-duck.service') -lt \$(vt_order 'stow') && \$(vt_order 'stow') -lt \$(vt_order 'daemon-reload') && \$(vt_order 'daemon-reload') -lt \$(vt_order 'try-restart voxtype') ]]"
check "restore puts main's links back and removes the test ones" "vt_link_is $vt_home/.config/voxtype $vt_main_config && vt_link_is $vt_home/.local/bin/voxtype-daemon $vt_main_bin && [[ ! -e $vt_home/.local/bin/voxtype-duck && ! -e $vt_units/voxtype-duck.service && ! -e $vt_units/voxtype.service.d/duck.conf && -L $vt_units/voxtype.service.d/prompt.conf ]]"
check "restore clears the records" "[[ ! -e $bars_dir/.voxtype_bar && ! -e $bars_dir/.voxtype_enabled ]]"
: >"$vt_calls"
out=$(vtx voxtype_restore)
check "a second restore is a no-op" "[[ -z \$out && ! -s $vt_calls ]] && vt_link_is $vt_home/.config/voxtype $vt_main_config"

echo "== voxtype: a swap that fails partway"
vt_reset
out=$(FAKE_ENABLE_FAIL=voxtype-duck.service vtx voxtype_swap duck "$bars_dir/duck")
code=$?
check "swap fails and says to restore" "[[ $code != 0 ]] && grep -q 'run restore' <<<\"\$out\""
out=$(vtx voxtype_status)
check "status reports the test build with the unit recorded" "grep -q 'duck' <<<\"\$out\" && [[ \$(cat $bars_dir/.voxtype_enabled) == voxtype-duck.service ]]"
: >"$vt_calls"
out=$(vtx voxtype_restore)
check "restore undoes it, disabling the unit it may have enabled" "[[ \$out == 'voxtype: main' ]] && grep -q 'disable --now voxtype-duck.service' '$vt_calls' && vt_link_is $vt_home/.config/voxtype $vt_main_config && [[ ! -e $vt_units/voxtype-duck.service ]]"

echo "== voxtype: a swap stopped before the enable"
vt_reset
vtx voxtype_swap duck "$bars_dir/duck" >/dev/null
# the process died after linking and before the enabled record was written
rm "$bars_dir/.voxtype_enabled"
: >"$vt_calls"
out=$(vtx voxtype_restore)
check "restore from links alone still relinks main and restarts" "[[ \$out == 'voxtype: main' ]] && vt_link_is $vt_home/.config/voxtype $vt_main_config && ! grep -q disable '$vt_calls' && grep -q 'restart voxtype' '$vt_calls'"
vt_reset
vtx voxtype_swap duck "$bars_dir/duck" >/dev/null
rm -f "$bars_dir/.voxtype_bar"
out=$(vtx voxtype_status)
check "status says half swapped when the record is gone" "grep -q 'half swapped' <<<\"\$out\""
vtx voxtype_restore >/dev/null
check "restore recovers from the links with no record" "vt_link_is $vt_home/.config/voxtype $vt_main_config && [[ ! -e $vt_units/voxtype-duck.service ]]"

echo "== voxtype: swapping to a build without voxtype changes"
vt_reset
vtx voxtype_swap duck "$bars_dir/duck" >/dev/null
: >"$vt_calls"
out=$(vtx voxtype_swap plain "$bars_dir/plain")
check "restores main instead of leaving the old test build" "[[ \$out == 'voxtype: main' ]] && vt_link_is $vt_home/.config/voxtype $vt_main_config && grep -q 'disable --now voxtype-duck.service' '$vt_calls'"

echo "== voxtype: a real file in the way"
vt_reset
echo mine >"$vt_units/voxtype-duck.service"
out=$(vtx voxtype_swap duck "$bars_dir/duck")
code=$?
check "refuses before moving anything" "[[ $code != 0 ]] && grep -q 'is not a symlink' <<<\"\$out\" && vt_link_is $vt_home/.config/voxtype $vt_main_config && [[ ! -e $bars_dir/.voxtype_bar ]] && ! grep -qE 'restart|daemon-reload|enable' '$vt_calls'"
rm "$vt_units/voxtype-duck.service"

echo "== voxtype: a branch that deletes scripts and units"
vt_reset
out=$(vtx voxtype_swap deletes "$bars_dir/deletes")
code=$?
show "$out"
check "a deletion-only branch swaps" "[[ $code == 0 && \$out == 'voxtype: test build deletes' ]]"
check "main's copies of what it deletes are unlinked" "[[ ! -e $vt_home/.local/bin/voxtype-old && ! -e $vt_units/old.service && ! -e $vt_units/voxtype.service.d/prompt.conf ]]"
check "a deleted unit is stopped before its link goes" "grep -q 'disable --now old.service' '$vt_calls' && [[ \$(cat $bars_dir/.voxtype_disabled) == old.service ]]"
out=$(vtx voxtype_status)
check "status reports the test build" "grep -q 'test build deletes' <<<\"\$out\""
: >"$vt_calls"
out=$(vtx voxtype_restore)
check "restore relinks what was deleted and re-enables the unit after restarting voxtype" "[[ \$out == 'voxtype: main' && -L $vt_home/.local/bin/voxtype-old && -L $vt_units/old.service && -L $vt_units/voxtype.service.d/prompt.conf && ! -e $bars_dir/.voxtype_disabled ]] && [[ \$(vt_order 'try-restart voxtype') -lt \$(vt_order 'enable --now old.service') ]]"

echo "== voxtype: a unit that will not stop"
vt_reset
vtx voxtype_swap duck "$bars_dir/duck" >/dev/null
out=$(FAKE_DISABLE_FAIL=voxtype-duck.service vtx voxtype_restore)
code=$?
show "$out"
check "restore fails and says to rerun" "[[ $code != 0 ]] && grep -q 'rerun restore' <<<\"\$out\""
check "the entry, the record and the links stay for the retry" "[[ \$(cat $bars_dir/.voxtype_enabled) == voxtype-duck.service && -f $bars_dir/.voxtype_bar && -L $vt_units/voxtype-duck.service ]]"
out=$(vtx voxtype_restore)
check "a rerun finishes" "[[ \$out == 'voxtype: main' && ! -e $bars_dir/.voxtype_bar ]] && vt_link_is $vt_home/.config/voxtype $vt_main_config"

echo "== voxtype: status after a partial swap"
vt_reset
vtx voxtype_swap duck "$bars_dir/duck" >/dev/null
rm "$vt_units/voxtype-duck.service"
out=$(vtx voxtype_status)
check "a missing unit link reads as half swapped" "grep -q 'half swapped' <<<\"\$out\""
vtx voxtype_restore >/dev/null
vt_reset
vtx voxtype_swap duck "$bars_dir/duck" >/dev/null
rm "$vt_home/.local/bin/voxtype-duck"
out=$(vtx voxtype_status)
check "a missing script link reads as half swapped" "grep -q 'half swapped' <<<\"\$out\""
vtx voxtype_restore >/dev/null

echo "== voxtype: a changed unit that stays"
vt_reset
out=$(vtx voxtype_swap mod "$bars_dir/mod")
code=$?
show "$out"
check "swap succeeds without enabling anything" "[[ $code == 0 && \$out == 'voxtype: test build mod' ]] && ! grep -q 'enable' '$vt_calls'"
check "restarts a modified unit and the unit of a changed drop-in after the reload" "[[ \$(vt_order 'daemon-reload') -lt \$(vt_order 'try-restart other.service') && \$(vt_order 'daemon-reload') -lt \$(vt_order 'try-restart third.service') ]]"
check "voxtype is restarted once, not again for its own drop-in" "[[ \$(grep -c 'try-restart voxtype' '$vt_calls') == 1 ]]"
: >"$vt_calls"
vtx voxtype_restore >/dev/null
check "restore restarts them onto main's definition after its reload" "[[ \$(vt_order 'daemon-reload') -lt \$(vt_order 'try-restart other.service') && \$(vt_order 'daemon-reload') -lt \$(vt_order 'try-restart third.service') && ! -e $bars_dir/.voxtype_restarted ]]"

echo "== voxtype: a deleted unit that runs without being enabled"
vt_reset
out=$(FAKE_NOT_ENABLED=1 vtx voxtype_swap deletes "$bars_dir/deletes")
check "swap stops it without disabling" "grep -q 'systemctl --user stop old.service' '$vt_calls' && ! grep -q 'disable --now old.service' '$vt_calls' && [[ ! -e $vt_units/old.service ]]"
: >"$vt_calls"
vtx voxtype_restore >/dev/null
check "restore starts it again after restarting voxtype" "[[ \$(vt_order 'try-restart voxtype') -lt \$(vt_order 'start old.service') && -L $vt_units/old.service && ! -e $bars_dir/.voxtype_stopped ]]"

echo "== voxtype: voxtype was stopped before the test"
vt_reset
rm -f "$root/voxtype_started"
vtx voxtype_swap duck "$bars_dir/duck" >/dev/null
vtx voxtype_restore >/dev/null
check "swap and restore never use a plain restart, which would start it" "[[ ! -e $root/voxtype_started ]] && grep -q 'try-restart voxtype' '$vt_calls' && ! grep -qx 'systemctl --user restart voxtype' '$vt_calls'"

echo "== shadow source and ignored assets"
shadow_sh=$here/../../shadow/shadow.sh
other=$root/other
git init -q "$other"
out=$(cd "$other" && bash -c 'source "$1"; from=; worktree_source' _ "$shadow_sh" 2>&1)
code=$?
show "$out"
check "up without --from inside an unrelated repo falls back to the main checkout" "[[ $code == 0 && \$out == */home/quickshell/.config/quickshell ]] && [[ \$out != $other* ]]"
out=$(cd "$other" && bash -c 'f=$2; source "$1"; from=$f; worktree_source' _ "$shadow_sh" "$other" 2>&1)
code=$?
check "an explicit --from in another repo is still refused" "[[ $code != 0 ]] && grep -q 'another repository' <<<\"\$out\""

out=$(cd "$root" && bash -c 'source "$1"; from=; worktree_source' _ "$shadow_sh" 2>&1)
check "outside any repo the main checkout is used" "[[ $? == 0 && \$out == */home/quickshell/.config/quickshell && \$out != $root* ]]"
main_repo=$(bash -c 'source "$1"; echo "$repo"' _ "$shadow_sh")
git -C "$main_repo" worktree add -q --detach "$root/linked" HEAD
out=$(cd "$root/linked" && bash -c 'source "$1"; from=; worktree_source' _ "$shadow_sh" 2>&1)
code=$?
git -C "$main_repo" worktree remove --force "$root/linked"
check "inside a linked worktree of this repo that worktree is the source" "[[ $code == 0 && \$out == $root/linked/home/quickshell/.config/quickshell ]]"

fake=$root/fake
qs=home/quickshell/.config/quickshell
git init -q "$fake"
mkdir -p "$fake/$qs/assets" "$fake/$qs/__pycache__"
printf 'assets/\ntheme.json\n__pycache__/\n' >"$fake/.gitignore"
echo a >"$fake/$qs/assets/a.ogg"
echo b >"$fake/$qs/assets/b c.ogg"
echo t >"$fake/$qs/theme.json"
echo p >"$fake/$qs/__pycache__/x.pyc"
git -C "$fake" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
dest=$root/dest
mkdir -p "$dest/assets"
echo mine >"$dest/assets/a.ogg"
echo target >"$root/target.ogg"
ln -s "$root/target.ogg" "$fake/$qs/assets/link.ogg"
ln -s "$root/missing.ogg" "$fake/$qs/assets/dangling.ogg"
out=$(bash -c 'source "$1"; repo=$2; copy_assets "$3"' _ "$here/../owner-test-bar.sh" "$fake" "$dest" 2>&1)
code=$?
check "copy_assets skips a dangling ignored link with a warning and succeeds" "[[ $code == 0 && ! -e $dest/assets/dangling.ogg && ! -L $dest/assets/dangling.ogg ]] && grep -q 'skipping dangling asset' <<<\"\$out\""
check "copy_assets dereferences a valid linked asset" "[[ -f $dest/assets/link.ogg && ! -L $dest/assets/link.ogg && \$(cat $dest/assets/link.ogg) == target ]]"
check "copy_assets fills the files a partly filled ignored directory lacks, spaces included" "[[ -f '$dest/assets/b c.ogg' && -f '$dest/theme.json' ]]"
check "copy_assets never overwrites an existing file" "[[ \$(cat $dest/assets/a.ogg) == mine ]]"
check "copy_assets skips __pycache__" "[[ ! -e $dest/__pycache__ ]]"

git -C "$fake" worktree add -q --detach "$root/bars/tb"
touch "$root/bars/tb.branches" "$root/bars/tb.check.log"
bash -c 'source "$1"; repo=$2; bars=$3; main remove tb' _ "$here/../owner-test-bar.sh" "$fake" "$root/bars" >/dev/null 2>&1
check "remove deletes the build's branches record and check log" "[[ ! -e $root/bars/tb && ! -e $root/bars/tb.branches && ! -e $root/bars/tb.check.log ]]"

echo "== oasis-djinn swap and restore"
# A throwaway HOME and git repo with a stowed oasis-djinn package (folded, like the real one); the real stow runs.
dj_repo=$root/dj_repo
dj_home=$root/dj_home
dj_dir=$bars_dir/djinn
dj_rel=home/oasis-djinn/.config/oasis-djinn
dj_main=$dj_repo/$dj_rel
mkdir -p "$dj_home/.config" "$dj_repo/$dj_rel" "$dj_repo/home/hypr/.config/hypr" "$dj_repo/home/voxtype"
git init -q -b main "$dj_repo"
djg() { git -C "$dj_repo" -c user.name=t -c user.email=t@t "$@"; }
echo main >"$dj_repo/$dj_rel/actions.json"
echo main >"$dj_repo/home/hypr/.config/hypr/init.lua"
echo main >"$dj_repo/home/voxtype/x"
djg add -A
djg commit -q -m main
djg update-ref refs/remotes/origin/main HEAD
djg switch -q -c dj-action
echo dictate >"$dj_repo/$dj_rel/actions.json"
djg commit -q -am action
djg switch -q -c dj-hypr main
echo hypr >"$dj_repo/home/hypr/.config/hypr/init.lua"
djg commit -q -am hypr
djg switch -q -c dj-other main
echo other >"$dj_repo/home/voxtype/x"
djg commit -q -am other
djg switch -q main
djg worktree add -q --detach "$bars_dir/djinn" dj-action
djg worktree add -q --detach "$bars_dir/djhypr" dj-hypr
djg worktree add -q --detach "$bars_dir/djother" dj-other
stow -d "$dj_repo/home" -t "$dj_home" oasis-djinn
# djx <function> <args>...: the sourced script against the fake repo and HOME.
djx() {
  HOME=$dj_home bash -c 'source "$1"; repo=$2; shift 2; "$@"' _ "$here/../owner-test-bar.sh" "$dj_repo" "$@" 2>&1
}
dj_link_is() { [[ $(readlink -m "$dj_home/.config/oasis-djinn") == "$1" ]]; }

out=$(djx djinn_swap other "$bars_dir/djother")
check "a branch touching neither oasis-djinn nor hypr leaves main's link" "[[ \$out == 'oasis-djinn: main' ]] && dj_link_is $dj_main && [[ ! -e $bars_dir/.djinn_bar ]]"
out=$(djx djinn_swap djinn "$bars_dir/djinn")
code=$?
show "$out"
check "swap points the link at the test build's manifest and says so" "[[ $code == 0 && \$out == 'oasis-djinn: test build djinn' ]] && dj_link_is $dj_dir/$dj_rel && [[ \$(cat $dj_home/.config/oasis-djinn/actions.json) == dictate ]]"
out=$(djx djinn_status)
check "status shows the test build" "[[ \$out == 'oasis-djinn: test build djinn' ]]"
out=$(djx djinn_restore)
code=$?
show "$out"
check "restore restows main's link" "[[ $code == 0 && \$out == 'oasis-djinn: main' ]] && dj_link_is $dj_main && [[ ! -e $bars_dir/.djinn_bar ]]"
out=$(djx djinn_status)
check "status is main again" "[[ \$out == 'oasis-djinn: main' ]]"
out=$(djx djinn_swap djhypr "$bars_dir/djhypr")
check "a hypr-only branch swaps too, since hypr reads the manifest" "[[ \$out == 'oasis-djinn: test build djhypr' ]] && dj_link_is $bars_dir/djhypr/$dj_rel"
out=$(djx djinn_swap other "$bars_dir/djother")
check "swapping to a build with neither change restores main" "[[ \$out == 'oasis-djinn: main' ]] && dj_link_is $dj_main"
djx djinn_swap djinn "$bars_dir/djinn" >/dev/null
rm "$bars_dir/.djinn_bar"
out=$(djx djinn_status)
check "status says half swapped when the record is gone" "grep -q 'half swapped' <<<\"\$out\""
djx djinn_restore >/dev/null
check "restore recovers from the link with no record" "dj_link_is $dj_main"
out=$(djx djinn_restore)
check "a second restore is a no-op" "[[ \$out == 'oasis-djinn: main' ]] && dj_link_is $dj_main"

echo "== oasis-djinn: absent or unstowed link"
mv "$dj_home/.config/oasis-djinn" "$root/dj_link_aside"
out=$(djx djinn_swap djinn "$bars_dir/djinn")
code=$?
check "an absent link is skipped with a note, not a failure" "[[ $code == 0 && \$out == 'oasis-djinn: not stowed here, skipped' && ! -e $bars_dir/.djinn_bar && ! -e $dj_home/.config/oasis-djinn ]]"
mkdir "$dj_home/.config/oasis-djinn"
out=$(djx djinn_swap djinn "$bars_dir/djinn")
code=$?
check "a real directory is refused and left alone" "[[ $code != 0 ]] && grep -q 'not a symlink' <<<\"\$out\" && [[ -d $dj_home/.config/oasis-djinn && ! -L $dj_home/.config/oasis-djinn && ! -e $bars_dir/.djinn_bar ]]"
rmdir "$dj_home/.config/oasis-djinn"
out=$(djx djinn_status)
check "status says not stowed, not main, when there is no link" "[[ \$out == 'oasis-djinn: not stowed here' ]]"
mv "$root/dj_link_aside" "$dj_home/.config/oasis-djinn"

echo "== oasis-djinn: swap command with a failing hypr swap"
# The swap command, with hypr_swap failing the way a config error does; the manifest must go back to main.
dj_swap_cmd() {
  HOME=$dj_home bash -c 'source "$1"; repo=$2; bars=$3; require_unlocked() { :; }; launch() { :; }; verify() { :; }
    hypr_swap() { echo hypr failed >&2; exit 1; }; main swap djinn' _ "$here/../owner-test-bar.sh" "$dj_repo" "$bars_dir" 2>&1
}
echo djinn >"$bars_dir/djinn.branches"
out=$(dj_swap_cmd)
code=$?
show "$out"
check "a failed hypr swap restores the manifest and fails" "[[ $code != 0 ]] && grep -q 'hypr failed' <<<\"\$out\" && dj_link_is $dj_main && [[ ! -e $bars_dir/.djinn_bar ]]"

echo "== swap command: a plain failing command inside the hypr swap"
# Not `exit`: a failed cp or ln is a bare failing command, which set -e must still stop (it is off left of `||`).
dj_swap_plain_fail() {
  HOME=$dj_home bash -c 'source "$1"; repo=$2; bars=$3; require_unlocked() { :; }; launch() { :; }; verify() { :; }
    voxcmd_swap() { echo voxcmd swap ran; }; voxtype_swap() { :; }
    hypr_swap() { false; echo hypr carried on; }; main swap djinn' _ "$here/../owner-test-bar.sh" "$dj_repo" "$bars_dir" 2>&1
}
out=$(dj_swap_plain_fail)
code=$?
show "$out"
check "a failing command in the hypr swap aborts, restores the manifest and fails" "[[ $code != 0 ]] && ! grep -q 'carried on\|voxcmd swap ran' <<<\"\$out\" && dj_link_is $dj_main && [[ ! -e $bars_dir/.djinn_bar ]]"

echo "== restore: manifest back before the hypr reload"
dj_restore_order() {
  HOME=$dj_home bash -c 'source "$1"; repo=$2; bars=$3; require_unlocked() { :; }; launch() { :; }; verify() { :; }
    guard_owner() { :; }; hypr_restore() { echo hypr_restore; }; djinn_restore() { echo djinn_restore; }
    voxcmd_restore() { :; }; voxtype_restore() { :; }; main restore' _ "$here/../owner-test-bar.sh" "$dj_repo" "$bars_dir" 2>&1
}
out=$(dj_restore_order)
check "restore swaps the manifest back before reloading Hyprland" "[[ \$(head -1 <<<\"\$out\") == djinn_restore && \$(sed -n 2p <<<\"\$out\") == hypr_restore ]]"

echo "== swap command: hypr swap fails after the link moved"
hl_main=$root/hl_main
hl_bar=$root/hl_bar
mkdir -p "$hl_main" "$hl_bar"
# Hyprland itself is stubbed: only the link, the records and the call order are real.
# shellcheck disable=SC2016
hl_env='source "$1"; repo=$2; bars=$3; hypr_link=$4; hypr_orig=$bars/.hypr_orig; hypr_bar=$bars/.hypr_bar
  require_unlocked() { :; }; launch() { :; }; verify() { :; }; hyprctl() { :; }; sleep() { :; }; restart_rotator() { :; }
  voxcmd_swap() { :; }; voxtype_swap() { :; }'
ln -sfn "$hl_main" "$root/hl_link"
dj_swap_moved() {
  HOME=$dj_home bash -c "$hl_env"'
    hypr_swap() { echo "$hypr_link_main" >"$hypr_orig"; echo djinn >"$hypr_bar"; ln -sfn "'"$hl_bar"'" "$hypr_link"; false; }
    hypr_link_main='"$hl_main"'; main swap djinn' _ "$here/../owner-test-bar.sh" "$dj_repo" "$bars_dir" "$root/hl_link" 2>&1
}
out=$(dj_swap_moved)
code=$?
show "$out"
check "a swap that fails after the link moved puts Hyprland and the manifest back, says it failed and how to finish, and fails" "grep -q 'hypr swap failed' <<<\"\$out\" && grep -q 'run: .*owner-test-bar.sh restore' <<<\"\$out\" && [[ $code != 0 && \$(readlink $root/hl_link) == $hl_main && ! -e $bars_dir/.hypr_orig ]] && dj_link_is $dj_main && [[ ! -e $bars_dir/.djinn_bar ]]"

echo "== restore and remove: a failing manifest restore does not skip Hyprland"
dj_restore_fails() {
  HOME=$dj_home bash -c "$hl_env"'
    guard_owner() { :; }; djinn_restore() { echo djinn_restore; false; }; hypr_restore() { echo hypr_restore; }
    voxcmd_restore() { :; }; voxtype_restore() { :; }; main "$5"' _ "$here/../owner-test-bar.sh" "$dj_repo" "$bars_dir" "$root/hl_link" "$1" 2>&1
}
touch "$bars_dir/.owner"
out=$(dj_restore_fails restore)
code=$?
show "$out"
check "a failed restore keeps the owner claim" "[[ -e $bars_dir/.owner ]]"
rm -f "$bars_dir/.owner"
check "restore still restores Hyprland after a failing manifest restore, and exits non-zero" "[[ $code != 0 ]] && [[ \$(sed -n 1p <<<\"\$out\") == djinn_restore && \$(sed -n 2p <<<\"\$out\") == hypr_restore ]] && grep -q 'restore did not finish' <<<\"\$out\""
echo djinn >"$bars_dir/.hypr_bar"
dj_remove_order() {
  HOME=$dj_home bash -c "$hl_env"'
    git() { :; }; djinn_restore() { echo djinn_restore; }; hypr_restore() { echo hypr_restore; }
    main remove djinn' _ "$here/../owner-test-bar.sh" "$dj_repo" "$bars_dir" "$root/hl_link" 2>&1
}
out=$(dj_remove_order)
check "remove restores the manifest before Hyprland" "[[ \$(sed -n 1p <<<\"\$out\") == djinn_restore && \$(sed -n 2p <<<\"\$out\") == hypr_restore ]]"
dj_remove_fails() {
  HOME=$dj_home bash -c "$hl_env"'
    git() { echo "git $*"; }; djinn_restore() { false; }; hypr_restore() { echo hypr_restore; }
    main remove djinn' _ "$here/../owner-test-bar.sh" "$dj_repo" "$bars_dir" "$root/hl_link" 2>&1
}
out=$(dj_remove_fails)
code=$?
show "$out"
check "remove stops before git worktree remove when a restore fails" "[[ $code != 0 ]] && ! grep -q '^git ' <<<\"\$out\" && grep -q 'hypr_restore' <<<\"\$out\""
rm -f "$bars_dir/.hypr_bar"

echo "== restore prints not stowed when there is nothing to restore"
mv "$dj_home/.config/oasis-djinn" "$root/dj_link_aside"
out=$(djx djinn_restore)
check "djinn_restore says not stowed here, like status" "[[ \$out == 'oasis-djinn: not stowed here' ]]"
mv "$root/dj_link_aside" "$dj_home/.config/oasis-djinn"

echo "$pass passed, $fail failed"
((fail == 0))
