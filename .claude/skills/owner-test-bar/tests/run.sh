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
vg switch -q -c tests main
echo t >"$vt_repo/home/voxtype/tests/t.sh"
vg add -A
vg commit -q -m tests
vg switch -q main
vg worktree add -q --detach "$bars_dir/duck" duck
vg worktree add -q --detach "$bars_dir/tests" tests
vg worktree add -q --detach "$bars_dir/plain" main
vg worktree add -q --detach "$bars_dir/deletes" deletes
cat >"$vt_stubs/systemctl" <<STUB
#!/usr/bin/env bash
echo "systemctl \$*" >>"$vt_calls"
case \$* in
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
check "restore disables the follower, then restows, reloads and restarts, in that order" "[[ \$(vt_order 'disable --now voxtype-duck.service') -lt \$(vt_order 'stow') && \$(vt_order 'stow') -lt \$(vt_order 'daemon-reload') && \$(vt_order 'daemon-reload') -lt \$(vt_order 'restart voxtype') ]]"
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
check "restore relinks what was deleted and re-enables the unit after restarting voxtype" "[[ \$out == 'voxtype: main' && -L $vt_home/.local/bin/voxtype-old && -L $vt_units/old.service && -L $vt_units/voxtype.service.d/prompt.conf && ! -e $bars_dir/.voxtype_disabled ]] && [[ \$(vt_order 'restart voxtype') -lt \$(vt_order 'enable --now old.service') ]]"

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

echo "$pass passed, $fail failed"
((fail == 0))
