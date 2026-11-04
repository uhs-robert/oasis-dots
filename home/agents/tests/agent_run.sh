#!/usr/bin/env bash
# Tests .local/bin/agent-run through the package's own shims, against a stub systemd-run and stub agents on a PATH
# with no system folders, so the real systemd-run and any installed agent stay out of it. A fake cgroup file and a
# fake runtime dir stand in for /proc/self/cgroup and the user manager's socket.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
package=$here/..
launcher=$package/.local/bin/agent-run
shims=$package/.local/share/agent-shims/bin
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

fail() {
  failures=$((failures + 1))
  echo "FAIL $*" >&2
}

# Only the tools agent-run and the stubs call, so a missing stub cannot fall through to a real program.
mkdir "$work/tools" "$work/stubs" "$work/agents" "$work/cwd" "$work/runtime" "$work/runtime/systemd"
timeout_bin=$(command -v timeout)
for tool in bash env id; do
  ln -s "$(command -v "$tool")" "$work/tools/$tool"
done

# Records its arguments, then runs what follows `--` in this process, as `systemd-run --scope` does.
cat >"$work/stubs/systemd-run" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$SCOPE_LOG"
while [[ $# -gt 0 && $1 != -- ]]; do shift; done
shift
exec "$@"
STUB
# Prints its own path, working directory and arguments, then exits with AGENT_EXIT.
cat >"$work/agents/claude" <<'STUB'
#!/usr/bin/env bash
printf 'real %s\n' "$0"
printf 'cwd %s\n' "$PWD"
printf 'arg %s\n' "$@"
exit "${AGENT_EXIT:-0}"
STUB
chmod +x "$work/stubs/systemd-run" "$work/agents/claude"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$work/runtime/systemd/private"

echo '0::/user.slice/user-1000.slice/user@1000.service/tmux-spawn-1.scope' >"$work/outside"
echo '0::/user.slice/user-1000.slice/user@1000.service/agents.slice/run-r1.scope' >"$work/inside"

# run <cgroup file> <runtime dir> <PATH> <shim> [args...]: runs the shim from $work/cwd, setting $out, $err and $status.
run() {
  local cgroup=$1 runtime=$2 path=$3 shim=$4
  shift 4
  rm -f "$work/scope.log"
  out=$(
    cd "$work/cwd" &&
      AGENT_RUN_CGROUP_FILE=$cgroup XDG_RUNTIME_DIR=$runtime SCOPE_LOG=$work/scope.log PATH=$path \
        "$timeout_bin" 10 "$shim" "$@" 2>"$work/err"
  )
  status=$?
  err=$(cat "$work/err")
}

full_path="$shims:$work/stubs:$work/agents:$work/tools"
want_out="real $work/agents/claude
cwd $work/cwd
arg a b
arg c"

# Outside the slice: one scope through systemd-run, with the arguments, working directory and exit code kept.
AGENT_EXIT=3 run "$work/outside" "$work/runtime" "$full_path" "$shims/claude" "a b" c
[[ $status == 3 ]] || fail "scope: exit $status, want 3 ($err)"
[[ $out == "$want_out" ]] || fail "scope: output '$out'"
want_scope="--user
--scope
--slice=agents.slice
--quiet
--collect
-p
OOMPolicy=continue
--
$work/agents/claude
a b
c"
[[ $(cat "$work/scope.log" 2>/dev/null) == "$want_scope" ]] || fail "scope: systemd-run got '$(cat "$work/scope.log" 2>/dev/null)'"

# AGENT_RUN_SLICE names another slice.
AGENT_RUN_SLICE=test.slice run "$work/outside" "$work/runtime" "$full_path" "$shims/claude"
grep -qx -- '--slice=test.slice' "$work/scope.log" 2>/dev/null || fail "slice override: no --slice=test.slice"

# Already in the slice (Claude starting Codex): the real program directly, no new scope.
AGENT_EXIT=4 run "$work/inside" "$work/runtime" "$full_path" "$shims/claude" "a b" c
[[ $status == 4 && $out == "$want_out" ]] || fail "in slice: exit $status, output '$out'"
[[ ! -e "$work/scope.log" ]] || fail "in slice: systemd-run ran"

# No systemd-run on PATH, or no user manager: the real program runs uncapped.
AGENT_EXIT=5 run "$work/outside" "$work/runtime" "$shims:$work/agents:$work/tools" "$shims/claude" "a b" c
[[ $status == 5 && $out == "$want_out" ]] || fail "no systemd-run: exit $status, output '$out' ($err)"
AGENT_EXIT=6 run "$work/outside" "$work/cwd" "$full_path" "$shims/claude" "a b" c
[[ $status == 6 && $out == "$want_out" ]] || fail "no user manager: exit $status, output '$out'"
[[ ! -e "$work/scope.log" ]] || fail "no user manager: systemd-run ran"

# A second shim folder ahead of the agent is skipped too, so the shims never run each other in a loop.
mkdir "$work/more-shims"
ln -s "$launcher" "$work/more-shims/claude"
run "$work/inside" "$work/runtime" "$shims:$work/more-shims:$work/agents:$work/tools" "$shims/claude"
[[ $status == 0 && $out == "real $work/agents/claude"* ]] || fail "second shim folder: exit $status, output '$out'"

# No real program: exit 127 with a message naming the agent.
run "$work/outside" "$work/runtime" "$full_path" "$shims/aider"
[[ $status == 127 ]] || fail "missing: exit $status, want 127"
[[ $err == "aider: not installed"* ]] || fail "missing: message '$err'"
[[ ! -e "$work/scope.log" ]] || fail "missing: systemd-run ran"

# By its own name it refuses, since it would not know which agent to run.
run "$work/outside" "$work/runtime" "$full_path" "$launcher"
[[ $status == 2 ]] || fail "own name: exit $status, want 2"

# The shim folder is the list of agents: every entry must be a symlink that resolves to agent-run.
count=0
for shim in "$shims"/* "$shims"/.[!.]*; do
  [[ -e $shim || -L $shim ]] || continue
  count=$((count + 1))
  [[ -L $shim && $shim -ef $launcher ]] || fail "shim ${shim##*/} is not a symlink to agent-run"
done
[[ $count -gt 0 ]] || fail "no shims in $shims"

if [[ $failures -gt 0 ]]; then
  echo "agent-run: $failures failed" >&2
  exit 1
fi
echo "agent-run: ok"
