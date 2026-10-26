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

rm -f "$HOME/.local/bin/voxcmd" "$HOME/.config/voxcmd"
ln -s "$root/gone" "$HOME/.local/bin/voxcmd"
out=$(as "" "" try_phrases "focus workspace 3")
code=$?
check "a dangling main link is named instead of reporting no result" "[[ $code == 1 ]] && grep -q 'missing or dangling' <<<\"\$out\""
rm -f "$HOME/.local/bin/voxcmd"

echo "== debug marker after a reboot"
rm -rf "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_RUNTIME_DIR/voxcmd"
echo owner >"$debug_log"
as "" "" voxcmd_debug_stop >/dev/null
check "a stale marker cannot delete the owner's later log" "[[ \$(cat $debug_log) == owner ]]"

bars_dir=$XDG_CACHE_HOME/dotfiles/test-bars

echo "== voxtype swap and restore"
# Main's voxcmd is the built binary, linked by `just voxcmd-build`, not a stowed file. A branch's test build builds the
# crate in the bar (stub cargo) and links its binary; restore must put main's build back.
echo "== rust-only voxcmd test build"
rr_repo=$root/rr_repo
rr_home=$root/rr_home
rr_stubs=$root/rr_stubs
rr_calls=$root/rr_calls
rr_dir=$bars_dir/rustbar
rr_main_bin=$rr_home/.local/share/voxcmd-rs/bin/voxcmd
mkdir -p "$rr_stubs" "${rr_main_bin%/*}" "$rr_home/.local/bin" "$rr_home/.config" "$rr_repo/home/voxcmd/.local/bin" \
  "$rr_repo/home/voxcmd/.config/voxcmd" "$rr_repo/.claude/skills/owner-test-bar"
git init -q -b main "$rr_repo"
rg() { git -C "$rr_repo" -c user.name=t -c user.email=t@t "$@"; }
# Main's build: no shebang, as a compiled binary has none.
# shellcheck disable=SC2016 # the stub's own variables
printf 'echo "main voxcmd $*" >>"%s"\necho "result: main"\n' "$rr_calls" >"$rr_main_bin"
chmod +x "$rr_main_bin"
echo main >"$rr_repo/home/voxcmd/.local/bin/voxcmd-autostop"
echo main >"$rr_repo/home/voxcmd/.config/voxcmd/keybinds.sh"
ln -s "$here/../owner-test-bar.sh" "$rr_repo/.claude/skills/owner-test-bar/owner-test-bar.sh"
rg add -A
rg commit -q -m main
rg update-ref refs/remotes/origin/main HEAD
rg switch -q -c rust
mkdir -p "$rr_repo/home/voxcmd/src"
echo '[package]' >"$rr_repo/home/voxcmd/Cargo.toml"
echo rust >"$rr_repo/home/voxcmd/.local/bin/voxcmd-autostop"
rg add -A
rg commit -q -m rust
rg switch -q main
rg worktree add -q --detach "$rr_dir" rust
stow -d "$rr_repo/home" -t "$rr_home" voxcmd
ln -s "$rr_main_bin" "$rr_home/.local/bin/voxcmd"
cat >"$rr_stubs/cargo" <<STUB
#!/usr/bin/env bash
echo "cargo \$* hash=\${VOXCMD_GIT_HASH:-}" >>"$rr_calls"
[[ ! -x $rr_home/.local/bin/voxcmd ]] || echo "voxcmd_link_live_during_build" >>"$rr_calls"
[[ -z \${FAKE_CARGO_FAIL:-} ]] || { echo "error: could not compile" >&2; exit 101; }
[[ ! -f $bars_dir/.owner ]] || echo "owner_claimed_during_build" >>"$rr_calls"
if [[ -n \${FAKE_CARGO_HANG:-} ]]; then
  # Like cargo and rustc: on TERM this process exits without telling its child, which only a group signal reaches.
  trap 'exit 143' TERM
  sleep 30 &
  echo \$! >"$root/rr_hang.pid"
  echo hang_started >>"$rr_calls"
  wait
fi
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
[[ -z \${FAKE_CARGO_BAD_JSON:-} ]] || { echo '{"reason": not json'; exit 0; }
[[ \$out_dir == "$root"/* ]] || { echo "stub cargo: refusing \$out_dir" >&2; exit 1; }
# A Cargo config build.target puts the binary under a triple dir.
[[ -z \${FAKE_CARGO_TRIPLE:-} ]] || out_dir=\$out_dir/\$FAKE_CARGO_TRIPLE
mkdir -p "\$out_dir/release"
{
  echo '#!/usr/bin/env bash'
  echo 'echo "rust voxcmd \$*" >>"$rr_calls"'
  echo 'echo "result: rust"'
} >"\$out_dir/release/voxcmd"
chmod +x "\$out_dir/release/voxcmd"
# Like cargo's JSON stream: a build script artifact first, then the bin.
echo '{"reason":"compiler-artifact","target":{"name":"build-script-build","kind":["custom-build"]},"executable":null}'
echo '{"reason":"compiler-artifact","target":{"name":"voxcmd","kind":["bin"]},"executable":"'"\$out_dir/release/voxcmd"'"}'
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
    hypr_swap() { echo "hypr_swap" >>"$RR_CALLS"; }
    voxtype_swap() { :; }; main swap rustbar' _ "$rr_repo/.claude/skills/owner-test-bar/owner-test-bar.sh" "$rr_repo" 2>&1
}
# The same swap as a background process whose $! is the bash itself, so a signal sent to it is the one swap receives.
# Python resets SIGINT: a background job of a non-interactive shell starts with it ignored, which traps cannot undo.
# shellcheck disable=SC2016
rr_swap_exec() {
  PATH="$rr_stubs:$PATH" HOME=$rr_home XDG_RUNTIME_DIR=$root/rr_run exec python3 -I -c \
    'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
    bash -c 'source "$1"; repo=$2; shift 2
    require_unlocked() { :; }; launch() { :; }; verify() { :; }; guard_owner() { :; }; guard_live_bar() { :; }
    hypr_swap() { echo "hypr_swap" >>"$RR_CALLS"; }
    voxtype_swap() { :; }; main swap rustbar' _ "$rr_repo/.claude/skills/owner-test-bar/owner-test-bar.sh" "$rr_repo"
}
rr_link_is() { [[ $(readlink -m "$rr_home/.local/bin/$1") == "$2" ]]; }
export RR_CALLS=$rr_calls
echo rustbar >"$bars_dir/rustbar.branches"

rm -f "$rr_calls"
out=$(FAKE_CARGO_FAIL=1 rr_swap_cmd)
code=$?
show "$out"
check "a failed build dies, says nothing was swapped, and leaves main linked" "[[ $code != 0 ]] && grep -q 'cargo build fails' <<<\"\$out\" && rr_link_is voxcmd '$rr_main_bin' && [[ ! -e $bars_dir/.voxcmd_bar && ! -e $bars_dir/.hypr_bar ]]"
check "the failed build ran before Hyprland was touched" "! grep -q '_swap' '$rr_calls'"
check "the failed build leaves the voxcmd status on main" "[[ \$(rrx voxcmd_status) == 'voxcmd: main' ]]"

# A cargo that builds elsewhere (CARGO_TARGET_DIR in the environment) must not leave a dangling link.
rm -f "$rr_calls"
out=$(CARGO_TARGET_DIR=$root/elsewhere CARGO_BUILD_TARGET=x rr_swap_cmd)
code=$?
check "an environment target dir does not move the build output, and the link is real" "[[ $code == 0 && -x $rr_dir/home/voxcmd/target/release/voxcmd && ! -e $root/elsewhere ]] && rr_link_is voxcmd '$rr_dir/home/voxcmd/target/release/voxcmd'"
rrx voxcmd_restore >/dev/null
rm -rf "$rr_dir/home/voxcmd/target"
rm -f "$bars_dir/.owner" "$rr_calls"
# A config `build.target` moves the binary under a triple dir; the path comes from cargo's artifact record.
out=$(FAKE_CARGO_TRIPLE=x86_64-test rr_swap_cmd)
code=$?
check "a config build target does not refuse the swap, and the live link is a real binary" "[[ $code == 0 && -x $rr_dir/home/voxcmd/target/release/voxcmd ]] && rr_link_is voxcmd '$rr_dir/home/voxcmd/target/release/voxcmd' && [[ -x $rr_home/.local/bin/voxcmd ]]"
rrx voxcmd_restore >/dev/null
rm -rf "$rr_dir/home/voxcmd/target"
rm -f "$bars_dir/.owner"
rm -f "$rr_calls"
out=$(FAKE_CARGO_NO_BIN=1 rr_swap_cmd)
code=$?
check "a build that produces no binary dies before anything swaps" "[[ $code != 0 ]] && grep -q 'cargo built no' <<<\"\$out\" && ! grep -q '_swap' '$rr_calls' && rr_link_is voxcmd '$rr_main_bin'"
rm -f "$bars_dir/.owner"

# A binary left in the staging dir by an earlier build must not pass for a build that produced none.
mkdir -p "$rr_dir/home/voxcmd/target/stage/release" "$rr_dir/home/voxcmd/target/release"
printf '#!/usr/bin/env bash\necho stale\n' >"$rr_dir/home/voxcmd/target/stage/release/voxcmd"
chmod +x "$rr_dir/home/voxcmd/target/stage/release/voxcmd"
printf 'live' >"$rr_dir/home/voxcmd/target/release/voxcmd"
rm -f "$rr_calls"
out=$(FAKE_CARGO_NO_BIN=1 rr_swap_cmd)
code=$?
check "a stale staged binary does not pass for a build that produced none, and the live one is untouched" "[[ $code != 0 ]] && grep -q 'cargo built no' <<<\"\$out\" && ! grep -q '_swap' '$rr_calls' && rr_link_is voxcmd '$rr_main_bin' && [[ \$(<$rr_dir/home/voxcmd/target/release/voxcmd) == live ]]"
rm -rf "$rr_dir/home/voxcmd/target"
rrx voxcmd_restore >/dev/null
rm -f "$bars_dir/.owner"

# A build that fails, or whose record cannot be read, leaves no .cargo.json (the log stays), and a failed copy leaves no .new.
rm -f "$rr_calls"
out=$(FAKE_CARGO_FAIL=1 rr_swap_cmd)
check "a failed build removes its .cargo.json and keeps the .cargo.log" "[[ ! -e $rr_dir.cargo.json && -f $rr_dir.cargo.log ]]"
rm -f "$rr_dir.cargo.log"
out=$(FAKE_CARGO_BAD_JSON=1 rr_swap_cmd)
code=$?
show "$out"
check "an unreadable artifact record says no binary was built, removes the .cargo.json, and swaps nothing" "[[ $code != 0 ]] && grep -q 'cargo built no' <<<\"\$out\" && [[ ! -e $rr_dir.cargo.json && -f $rr_dir.cargo.log ]] && rr_link_is voxcmd '$rr_main_bin'"
rm -f "$rr_dir.cargo.log"
mkdir -p "$rr_dir/home/voxcmd/target/release"
: >"$rr_dir/home/voxcmd/target/release/voxcmd.new"
chmod 000 "$rr_dir/home/voxcmd/target/release/voxcmd.new"
out=$(rr_swap_cmd)
code=$?
show "$out"
check "a failed copy dies, removes the stale .new and the .cargo.json, and swaps nothing" "[[ $code != 0 ]] && grep -q 'could not copy' <<<\"\$out\" && [[ ! -e $rr_dir/home/voxcmd/target/release/voxcmd.new && ! -e $rr_dir.cargo.json ]] && rr_link_is voxcmd '$rr_main_bin'"
rm -rf "$rr_dir/home/voxcmd/target"
rm -f "$bars_dir/.owner" "$rr_dir.cargo.log"

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
check "the swap builds with cargo release, locked, on the bar's manifest, with a git hash" "[[ $code == 0 ]] && grep -qE '^cargo build --release --locked --manifest-path $rr_dir/home/voxcmd/Cargo.toml --target-dir $rr_dir/home/voxcmd/target/stage --message-format=json-render-diagnostics hash=.+' '$rr_calls'"
check "the claim is taken before the long build, so a second session meets it" "grep -q '^owner_claimed_during_build' '$rr_calls'"
check "the build runs before the Hyprland swap" "[[ \$(grep -n '^cargo' '$rr_calls' | head -1 | cut -d: -f1) -lt \$(grep -n '_swap' '$rr_calls' | head -1 | cut -d: -f1) ]]"
check "a successful build copies the staged binary over the live path, leaving cargo's output alone" "[[ -x $rr_dir/home/voxcmd/target/stage/release/voxcmd && -x $rr_dir/home/voxcmd/target/release/voxcmd && ! $rr_dir/home/voxcmd/target/stage/release/voxcmd -ef $rr_dir/home/voxcmd/target/release/voxcmd && ! -e $rr_dir/home/voxcmd/target/release/voxcmd.new ]]"
check "voxcmd links into the bar's built binary" "rr_link_is voxcmd '$rr_dir/home/voxcmd/target/release/voxcmd'"
mv "$rr_dir/home/voxcmd/target/release/voxcmd" "$root/rr_bin_aside"
check "status does not report a test build whose voxcmd binary is gone" "[[ \$(rrx voxcmd_status) != 'voxcmd: test build rustbar' ]]"
mv "$root/rr_bin_aside" "$rr_dir/home/voxcmd/target/release/voxcmd"
check "the bar's helper scripts and config are linked too" "rr_link_is voxcmd-autostop '$rr_dir/home/voxcmd/.local/bin/voxcmd-autostop' && [[ \$(readlink -m $rr_home/.config/voxcmd) == $rr_dir/home/voxcmd/.config/voxcmd ]]"
check "status reads test build" "[[ \$(rrx voxcmd_status) == 'voxcmd: test build rustbar' ]]"

# A failed rebuild of the live bar must leave the binary the voxcmd link points at, and the previous owner's claim.
rr_prev_claim='{"address":"","session":"","bar":"previousbar","branches":["x"],"since":"t"}'
echo "$rr_prev_claim" >"$bars_dir/.owner"
rm -f "$rr_calls"
out=$(FAKE_CARGO_FAIL=1 rr_swap_cmd)
code=$?
check "a failed rebuild of the live bar keeps its built binary and link working" "[[ $code != 0 ]] && [[ -x $rr_dir/home/voxcmd/target/release/voxcmd ]] && rr_link_is voxcmd '$rr_dir/home/voxcmd/target/release/voxcmd' && [[ \$(rrx voxcmd_status) == 'voxcmd: test build rustbar' ]]"
check "the live link never dangles while a rebuild runs" "grep -q '^voxcmd_link_live_during_build' '$rr_calls'"
check "a failed rebuild gives the previous claim back" "[[ \$(jq -r .bar '$bars_dir/.owner') == previousbar ]]"

# A signal mid-build: the swap must restore the claim, take the whole build down with it (the stub leaves a child that
# only a group signal reaches), and leave the live binary and link as they were.
for rr_sig in TERM:143 INT:130; do
  rr_status=${rr_sig#*:}
  rr_sig=${rr_sig%:*}
  echo "$rr_prev_claim" >"$bars_dir/.owner"
  rm -f "$rr_calls" "$root/rr_hang.pid"
  FAKE_CARGO_HANG=1 rr_swap_exec >"$root/rr_sig.out" 2>&1 &
  rr_pid=$!
  for _ in $(seq 100); do
    grep -qs hang_started "$rr_calls" && break
    sleep 0.1
  done
  rr_hang_pid=$(<"$root/rr_hang.pid")
  kill -"$rr_sig" "$rr_pid"
  wait "$rr_pid"
  code=$?
  check "SIG$rr_sig mid-build: swap exits $rr_status, binary and link are untouched, claim is the previous one" "[[ $code == $rr_status ]] && grep -q hang_started '$rr_calls' && [[ -x $rr_dir/home/voxcmd/target/release/voxcmd ]] && rr_link_is voxcmd '$rr_dir/home/voxcmd/target/release/voxcmd' && [[ \$(jq -r .bar '$bars_dir/.owner') == previousbar ]]"
  check "SIG$rr_sig mid-build: the build's child process is gone" "! kill -0 $rr_hang_pid 2>/dev/null"
  kill "$rr_hang_pid" 2>/dev/null || true
done

rm -f "$rr_calls"
out=$(rrx try_phrases "go home")
code=$?
show "$out"
check "try runs explain on a Rust test build and reads its result" "[[ $code == 0 ]] && grep -q 'rust voxcmd explain go home' '$rr_calls' && ! grep -q -- '--dry-run' '$rr_calls' && grep -q '\"go home\": rust' <<<\"\$out\""

out=$(rrx voxcmd_restore)
code=$?
check "restore relinks main's built voxcmd and restows the rest" "[[ $code == 0 ]] && rr_link_is voxcmd '$rr_main_bin' && rr_link_is voxcmd-autostop '$rr_repo/home/voxcmd/.local/bin/voxcmd-autostop' && [[ ! -e $bars_dir/.voxcmd_bar ]] && [[ \$(rrx voxcmd_status) == 'voxcmd: main' ]]"
rm -f "$rr_calls"
out=$(rrx try_phrases "go home")
check "try runs explain on main's build" "grep -q 'main voxcmd explain go home' '$rr_calls' && ! grep -q -- '--dry-run' '$rr_calls'"
# A restore with the build gone must say so rather than leave a silent hole where voxcmd was.
rrx voxcmd_swap rustbar "$rr_dir" >/dev/null
mv "$rr_main_bin" "$root/rr_main_aside"
out=$(rrx voxcmd_restore)
check "restore without a built voxcmd warns and names the build recipe" "grep -q 'just voxcmd-build' <<<\"\$out\" && [[ ! -e $rr_home/.local/bin/voxcmd ]]"
mv "$root/rr_main_aside" "$rr_main_bin"
rrx voxcmd_restore >/dev/null
# While main still ships a bash voxcmd (this script run from an unmerged worktree, or after a revert), stow links it and the
# restore must leave that link alone rather than point it at the Rust build.
echo '#!/usr/bin/env bash' >"$rr_repo/home/voxcmd/.local/bin/voxcmd"
chmod +x "$rr_repo/home/voxcmd/.local/bin/voxcmd"
rrx voxcmd_swap rustbar "$rr_dir" >/dev/null
rrx voxcmd_restore >/dev/null
check "restore keeps the link stow made to a bash voxcmd main ships" "rr_link_is voxcmd '$rr_repo/home/voxcmd/.local/bin/voxcmd'"
rm -f "$rr_repo/home/voxcmd/.local/bin/voxcmd" "$rr_home/.local/bin/voxcmd"
ln -s "$rr_main_bin" "$rr_home/.local/bin/voxcmd"
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

echo "== swap command with a failing hypr swap"
# A throwaway HOME and git repo; Hyprland itself is stubbed, only the link, the records and the call order are real.
hy_repo=$root/hy_repo
hy_home=$root/hy_home
mkdir -p "$hy_home/.config" "$hy_repo"
git init -q -b main "$hy_repo"
# The swap command, with hypr_swap failing the way a config error does.
hy_swap_cmd() {
  HOME=$hy_home bash -c 'source "$1"; repo=$2; bars=$3; require_unlocked() { :; }; launch() { :; }; verify() { :; }
    hypr_swap() { echo hypr failed >&2; exit 1; }; hypr_restore() { echo hypr_restore; }; main swap hyprbar' _ "$here/../owner-test-bar.sh" "$hy_repo" "$bars_dir" 2>&1
}
mkdir -p "$bars_dir/hyprbar"
echo hyprbar >"$bars_dir/hyprbar.branches"
out=$(hy_swap_cmd)
code=$?
show "$out"
check "a failed hypr swap restores Hyprland and fails" "[[ $code != 0 ]] && grep -q 'hypr failed' <<<\"\$out\" && grep -q '^hypr_restore\$' <<<\"\$out\""

echo "== swap command: a plain failing command inside the hypr swap"
# Not `exit`: a failed cp or ln is a bare failing command, which set -e must still stop (it is off left of `||`).
hy_swap_plain_fail() {
  HOME=$hy_home bash -c 'source "$1"; repo=$2; bars=$3; require_unlocked() { :; }; launch() { :; }; verify() { :; }
    voxcmd_swap() { echo voxcmd swap ran; }; voxtype_swap() { :; }; hypr_restore() { echo hypr_restore; }
    hypr_swap() { false; echo hypr carried on; }; main swap hyprbar' _ "$here/../owner-test-bar.sh" "$hy_repo" "$bars_dir" 2>&1
}
out=$(hy_swap_plain_fail)
code=$?
show "$out"
check "a failing command in the hypr swap aborts, restores Hyprland and fails" "[[ $code != 0 ]] && ! grep -q 'carried on\|voxcmd swap ran' <<<\"\$out\" && grep -q '^hypr_restore\$' <<<\"\$out\""

echo "== swap command: hypr swap fails after the link moved"
hl_main=$root/hl_main
hl_bar=$root/hl_bar
mkdir -p "$hl_main" "$hl_bar"
# shellcheck disable=SC2016
hl_env='source "$1"; repo=$2; bars=$3; hypr_link=$4; hypr_orig=$bars/.hypr_orig; hypr_bar=$bars/.hypr_bar
  require_unlocked() { :; }; launch() { :; }; verify() { :; }; hyprctl() { :; }; sleep() { :; }; restart_rotator() { :; }
  voxcmd_swap() { :; }; voxtype_swap() { :; }'
ln -sfn "$hl_main" "$root/hl_link"
hy_swap_moved() {
  HOME=$hy_home bash -c "$hl_env"'
    hypr_swap() { echo "$hypr_link_main" >"$hypr_orig"; echo hyprbar >"$hypr_bar"; ln -sfn "'"$hl_bar"'" "$hypr_link"; false; }
    hypr_link_main='"$hl_main"'; main swap hyprbar' _ "$here/../owner-test-bar.sh" "$hy_repo" "$bars_dir" "$root/hl_link" 2>&1
}
out=$(hy_swap_moved)
code=$?
show "$out"
check "a swap that fails after the link moved puts Hyprland back, says it failed and how to finish, and fails" "grep -q 'hypr swap failed' <<<\"\$out\" && grep -q 'run: .*owner-test-bar.sh restore' <<<\"\$out\" && [[ $code != 0 && \$(readlink $root/hl_link) == $hl_main && ! -e $bars_dir/.hypr_orig ]]"

echo "== restore and remove: a failing Hyprland restore is reported and keeps the claim"
hy_restore_fails() {
  HOME=$hy_home bash -c "$hl_env"'
    guard_owner() { :; }; hypr_restore() { echo hypr_restore; false; }
    voxcmd_restore() { echo voxcmd_restore; }; voxtype_restore() { :; }; main "$5"' _ "$here/../owner-test-bar.sh" "$hy_repo" "$bars_dir" "$root/hl_link" "$1" 2>&1
}
touch "$bars_dir/.owner"
out=$(hy_restore_fails restore)
code=$?
show "$out"
check "a failed restore keeps the owner claim" "[[ -e $bars_dir/.owner ]]"
rm -f "$bars_dir/.owner"
check "restore still restores voxcmd after a failing Hyprland restore, and exits non-zero" "[[ $code != 0 ]] && [[ \$(grep -n '^hypr_restore\$' <<<\"\$out\" | cut -d: -f1) -lt \$(grep -n '^voxcmd_restore\$' <<<\"\$out\" | cut -d: -f1) ]] && grep -q 'restore did not finish' <<<\"\$out\""
echo hyprbar >"$bars_dir/.hypr_bar"
hy_remove_restores() {
  HOME=$hy_home bash -c "$hl_env"'
    git() { :; }; hypr_restore() { echo hypr_restore; }
    main remove hyprbar' _ "$here/../owner-test-bar.sh" "$hy_repo" "$bars_dir" "$root/hl_link" 2>&1
}
out=$(hy_remove_restores)
check "remove restores Hyprland when it is on that bar" "grep -q '^hypr_restore\$' <<<\"\$out\""
hy_remove_fails() {
  HOME=$hy_home bash -c "$hl_env"'
    git() { echo "git $*"; }; hypr_restore() { echo hypr_restore; false; }
    main remove hyprbar' _ "$here/../owner-test-bar.sh" "$hy_repo" "$bars_dir" "$root/hl_link" 2>&1
}
out=$(hy_remove_fails)
code=$?
show "$out"
check "remove stops before git worktree remove when the Hyprland restore fails" "[[ $code != 0 ]] && ! grep -q '^git ' <<<\"\$out\" && grep -q 'hypr_restore' <<<\"\$out\""
rm -f "$bars_dir/.hypr_bar"

echo "$pass passed, $fail failed"
((fail == 0))
