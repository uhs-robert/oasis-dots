#!/usr/bin/env bash
# Replays the local review scripts and the runner against stub claude, coderabbit, codex and gh on PATH; no real service is called.
# shellcheck disable=SC2016,SC2034 # The check strings are single-quoted on purpose (eval'd later); rc and out are read only inside them.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
skill=$(cd "$here/.." && pwd)
pass=0 fail=0
check() { if eval "$2"; then
  echo "ok   $1"
  pass=$((pass + 1))
else
  echo "FAIL $1"
  fail=$((fail + 1))
fi; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin" "$root/home" "$root/cache" "$root/state"
export HOME=$root/home XDG_CACHE_HOME=$root/cache
export REVIEWERS_USER_FILE=$root/user.json REVIEWERS_SETTINGS_FILE=$root/settings.json
export CODEX_POLL_S=0.1
PATH=$root/bin:$PATH
unset REVIEW_SCOPE REVIEW_MODEL

# Stubs: behaviour comes from files under $root/state, calls are appended to $root/calls.
cat >"$root/bin/gh" <<'S'
#!/usr/bin/env bash
echo "gh $*" >>"$STUB_ROOT/calls"
[ ! -e "$STUB_ROOT/state/gh_fail" ] || exit 1
cat "$STUB_ROOT/state/gh_visibility"
S
cat >"$root/bin/coderabbit" <<'S'
#!/usr/bin/env bash
echo "coderabbit $*" >>"$STUB_ROOT/calls"
if [ "$1" = usage ]; then
  printf 'CodeRabbit Usage\nRemaining  : %s of 10\n' "$(cat "$STUB_ROOT/state/cr_remaining")"
  exit 0
fi
[ ! -e "$STUB_ROOT/state/cr_fail" ] || { echo "rate limit exceeded" >&2; exit 1; }
echo "coderabbit finding"
S
cat >"$root/bin/claude" <<'S'
#!/usr/bin/env bash
echo "claude $*" >>"$STUB_ROOT/calls"
cat >"$STUB_ROOT/claude_stdin"
case $(cat "$STUB_ROOT/state/claude_mode") in
  ok) echo "claude finding" ;;
  notlogged) echo "Not logged in" ;;
  empty) ;;
  quote) printf '%s\n' 'Finding 1: login' 'The code prints "Not logged in" when auth fails.' ;;
  hang) exec sleep 30 ;;
  fail) echo "boom" >&2; exit 1 ;;
esac
S
cat >"$root/bin/codex" <<'S'
#!/usr/bin/env bash
echo "codex $*" >>"$STUB_ROOT/calls"
out=""
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
if [ -e "$STUB_ROOT/state/codex_fail" ]; then echo "usage limit reached" >&2; exit 1; fi
echo "codex finding" >"$out"
S
chmod +x "$root/bin/"*
export STUB_ROOT=$root

repo=$root/repo
git init -q -b main "$repo"
git -C "$repo" config user.email t@t
git -C "$repo" config user.name t
git -C "$repo" remote add origin https://example.invalid/o/r.git
echo a >"$repo/a.txt"
git -C "$repo" add a.txt
git -C "$repo" commit -qm base
git -C "$repo" checkout -qb feature
echo b >>"$repo/a.txt"
git -C "$repo" commit -qam change
cd "$repo" || exit 1

reset() {
  rm -rf "$root/out" "$root/cache/code-reviewers" "$root/calls" "$root"/state/* "$REVIEWERS_USER_FILE" "$REVIEWERS_SETTINGS_FILE"
  : >"$root/calls"
  echo PUBLIC >"$root/state/gh_visibility"
  echo 10 >"$root/state/cr_remaining"
  echo ok >"$root/state/claude_mode"
  git checkout -q -- . 2>/dev/null
}
# run SCRIPT_BASENAME [ENV=VAL...]: stdout in $out, status in $rc
run() {
  local s=$1
  shift
  out=$(env "$@" "$skill/$s" main "$root/out" 2>"$root/err")
  rc=$?
}
called() { grep -q -e "$1" "$root/calls"; }

echo "== coderabbit-review.sh"
reset
run coderabbit-review.sh REVIEW_SCOPE=public
check "public scope on a public repo: exit 0, path printed" '[ $rc -eq 0 ] && [ "$out" = "$root/out/coderabbit-review.md" ] && grep -q "coderabbit finding" "$out"'
check "runs committed review against the base, no credits" 'called "coderabbit review --base main --committed" && ! called "--use-credits"'
reset
run coderabbit-review.sh REVIEW_SCOPE=off
check "scope off: exit 4, nothing called" '[ $rc -eq 4 ] && [ ! -s "$root/calls" ] && [ -s "$root/out/coderabbit-skipped.txt" ]'
reset
echo PRIVATE >"$root/state/gh_visibility"
run coderabbit-review.sh REVIEW_SCOPE=public
check "scope public on a private repo: exit 4 with reason" '[ $rc -eq 4 ] && grep -q "skipped: scope public and the repo is private" <<<"$out" && ! called "coderabbit"'
reset
touch "$root/state/gh_fail"
run coderabbit-review.sh REVIEW_SCOPE=public
check "scope public with a failed lookup fails closed (exit 4)" '[ $rc -eq 4 ] && grep -q "lookup failed" <<<"$out" && ! called "coderabbit"'
reset
echo garbage >"$root/state/gh_visibility"
run coderabbit-review.sh REVIEW_SCOPE=public
check "scope public with an unrecognised answer fails closed" '[ $rc -eq 4 ]'
reset
touch "$root/state/gh_fail"
run coderabbit-review.sh REVIEW_SCOPE=all
check "scope all needs no lookup" '[ $rc -eq 0 ] && ! called "^gh"'
reset
run coderabbit-review.sh REVIEW_SCOPE=public
echo PRIVATE >"$root/state/gh_visibility"
run coderabbit-review.sh REVIEW_SCOPE=public
check "a repo that went private is seen on the next run (no cached public)" '[ $rc -eq 4 ] && [ "$(grep -c "^gh" "$root/calls")" = 2 ]'
reset
echo dirty >>"$repo/a.txt"
run coderabbit-review.sh REVIEW_SCOPE=all
check "uncommitted changes: exit 3, no review" '[ $rc -eq 3 ] && ! called "coderabbit review"'
git -C "$repo" checkout -q -- .
reset
echo 0 >"$root/state/cr_remaining"
run coderabbit-review.sh REVIEW_SCOPE=all
check "usage with 0 left: exit 2, no review attempted" '[ $rc -eq 2 ] && grep -q "unavailable" <<<"$out" && ! called "coderabbit review"'
reset
touch "$root/state/cr_fail"
run coderabbit-review.sh REVIEW_SCOPE=all
check "review failure: exit 2 with the CLI reason, no file left" '[ $rc -eq 2 ] && grep -q "rate limit exceeded" <<<"$out" && [ ! -e "$root/out/coderabbit-review.md" ]'
reset
run coderabbit-review.sh REVIEW_SCOPE=all PATH="$root/nobin:/usr/bin:/bin"
check "coderabbit not installed: exit 2" '[ $rc -eq 2 ] && grep -q "not installed" <<<"$out"'

echo "== claude-review.sh"
reset
run claude-review.sh REVIEW_SCOPE=all REVIEW_MODEL=sonnet
check "exit 0 and path printed" '[ $rc -eq 0 ] && [ "$out" = "$root/out/claude-review.md" ] && grep -q "claude finding" "$out"'
check "read-only flags passed, no --bare" 'called "claude -p --restricted --strict-mcp-config --tools Read,Grep,Glob --permission-mode dontAsk --permission-prompts none --no-session-persistence --model sonnet" && ! called "--bare"'
check "the diff is on stdin" 'grep -q "^+b" "$root/claude_stdin"'
reset
run claude-review.sh REVIEW_SCOPE=all
check "no --model without REVIEW_MODEL" '! called "--model"'
reset
echo notlogged >"$root/state/claude_mode"
run claude-review.sh REVIEW_SCOPE=all
check "Not logged in output: exit 2 and no review file" '[ $rc -eq 2 ] && grep -q "not logged in" <<<"$out" && [ ! -e "$root/out/claude-review.md" ]'
reset
echo quote >"$root/state/claude_mode"
run claude-review.sh REVIEW_SCOPE=all
check "a real review quoting the phrase is kept" '[ $rc -eq 0 ] && grep -q "Finding 1" "$out"'
reset
echo hang >"$root/state/claude_mode"
run claude-review.sh REVIEW_SCOPE=all REVIEW_TIMEOUT_S=1
check "a hung claude is cut off by the timeout: exit 2, reason exit 124" '[ $rc -eq 2 ] && grep -q "exit 124" <<<"$out"'
reset
echo empty >"$root/state/claude_mode"
run claude-review.sh REVIEW_SCOPE=all
check "empty output: exit 2" '[ $rc -eq 2 ] && grep -q "empty output" <<<"$out"'
reset
echo fail >"$root/state/claude_mode"
run claude-review.sh REVIEW_SCOPE=all
check "CLI error: exit 2 with its stderr" '[ $rc -eq 2 ] && grep -q "boom" <<<"$out"'
reset
run claude-review.sh REVIEW_SCOPE=off
check "scope off: exit 4, claude not called" '[ $rc -eq 4 ] && [ ! -s "$root/calls" ]'
reset
echo dirty >>"$repo/a.txt"
run claude-review.sh REVIEW_SCOPE=all
check "uncommitted changes: exit 3" '[ $rc -eq 3 ] && ! called "claude"'
git -C "$repo" checkout -q -- .
reset
echo PRIVATE >"$root/state/gh_visibility"
run claude-review.sh REVIEW_SCOPE=public
check "scope public on a private repo: exit 4" '[ $rc -eq 4 ]'

echo "== codex-review.sh"
reset
run codex-review.sh REVIEW_SCOPE=all
check "exit 0 and path printed" '[ $rc -eq 0 ] && [ "$out" = "$root/out/codex-review.md" ] && grep -q "codex finding" "$out"'
reset
run codex-review.sh REVIEW_SCOPE=off
check "scope off: exit 4, codex not called" '[ $rc -eq 4 ] && ! called "codex"'
reset
echo PRIVATE >"$root/state/gh_visibility"
run codex-review.sh REVIEW_SCOPE=public
check "scope public on a private repo: exit 4" '[ $rc -eq 4 ]'
reset
echo dirty >>"$repo/a.txt"
run codex-review.sh REVIEW_SCOPE=all
check "uncommitted changes: exit 3" '[ $rc -eq 3 ]'
git -C "$repo" checkout -q -- .
reset
touch "$root/state/codex_fail"
run codex-review.sh REVIEW_SCOPE=all
check "usage limit: exit 2 with the reason" '[ $rc -eq 2 ] && grep -q "codex unavailable:.*usage limit" <<<"$out"'
reset
run codex-review.sh
check "without REVIEW_SCOPE the registry decides (codex defaults to all)" '[ $rc -eq 0 ]'
reset
echo '{"reviewers":{"codex":{"local":"off"}}}' >"$REVIEWERS_SETTINGS_FILE"
run codex-review.sh
check "without REVIEW_SCOPE a Settings off skips it" '[ $rc -eq 4 ]'

echo "== run-local-reviews.sh"
reset
echo '{"reviewers":{"codex":{"local":"all"},"coderabbit":{"local":"off"},"claude":{"local":"off"}}}' >"$REVIEWERS_SETTINGS_FILE"
run run-local-reviews.sh
check "only the enabled reviewer runs" '[ $rc -eq 0 ] && [ "$out" = "codex: $root/out/codex-review.md" ] && ! called "coderabbit" && ! called "claude"'
reset
echo '{"reviewers":{"codex":{"local":"all"},"coderabbit":{"local":"public"},"claude":{"local":"all"}}}' >"$REVIEWERS_SETTINGS_FILE"
echo PRIVATE >"$root/state/gh_visibility"
run run-local-reviews.sh
check "one line per enabled reviewer, private repo skips public-scope CodeRabbit" '[ $rc -eq 0 ] && [ "$(wc -l <<<"$out")" = 3 ] &&
  grep -q "^codex: $root/out/codex-review.md$" <<<"$out" && grep -q "^claude: $root/out/claude-review.md$" <<<"$out" &&
  grep -q "^coderabbit: coderabbit skipped: scope public and the repo is private$" <<<"$out"'
check "REVIEW_SCOPE reaches the scripts (public passes on a public repo)" '
  reset; echo "{\"reviewers\":{\"codex\":{\"local\":\"off\"},\"coderabbit\":{\"local\":\"public\"}}}" >"$REVIEWERS_SETTINGS_FILE"
  run run-local-reviews.sh; [ "$out" = "coderabbit: $root/out/coderabbit-review.md" ]'
reset
echo '{"reviewers":{"codex":{"local":"all"},"claude":{"local":"all"}}}' >"$REVIEWERS_SETTINGS_FILE"
touch "$root/state/codex_fail"
run run-local-reviews.sh
check "one reviewer unavailable does not stop the others" '[ $rc -eq 0 ] && grep -q "^codex: codex unavailable:" <<<"$out" && grep -q "^claude: $root/out/claude-review.md$" <<<"$out"'

# Two custom reviewers that each wait for the other's start marker prove they overlap.
mkdir -p "$root/custom"
for n in one two; do
  other=two
  [ $n = two ] && other=one
  cat >"$root/custom/$n.sh" <<S
#!/usr/bin/env bash
touch "$root/custom/$n.started"
for _ in \$(seq 1 50); do [ -e "$root/custom/$other.started" ] && break; sleep 0.1; done
[ -e "$root/custom/$other.started" ] || { echo "$n ran alone"; exit 2; }
echo "\$2/$n-review.md"
S
done
cat >"$root/custom/boom.sh" <<'S'
#!/usr/bin/env bash
echo "partial" ; exit 1
S
cat >"$root/custom/dirty.sh" <<'S'
#!/usr/bin/env bash
exit 3
S
chmod +x "$root"/custom/*.sh
reset
rm -f "$root"/custom/*.started
cat >"$REVIEWERS_USER_FILE" <<J
{"reviewers":[
 {"name":"one","local":{"command":"$root/custom/one.sh","default":"all"}},
 {"name":"two","local":{"command":"$root/custom/two.sh","default":"all"}},
 {"name":"boom","local":{"command":"$root/custom/boom.sh","default":"all"}},
 {"name":"dirty","local":{"command":"$root/custom/dirty.sh","default":"all"}},
 {"name":"nocmd","local":{"default":"all"}}
]}
J
echo '{"reviewers":{"codex":{"local":"off"}}}' >"$REVIEWERS_SETTINGS_FILE"
run run-local-reviews.sh
check "reviewers run in parallel" 'grep -q "^one: $root/out/one-review.md$" <<<"$out" && grep -q "^two: $root/out/two-review.md$" <<<"$out"'
check "a crashing reviewer is reported and the others still finish" 'grep -q "^boom: failed (exit 1) partial$" <<<"$out" && grep -q "^one: " <<<"$out"'
check "exit 3 maps to an uncommitted-changes line" 'grep -q "^dirty: uncommitted changes" <<<"$out"'
check "an entry without a command is reported, not run" 'grep -q "^nocmd: no local command configured$" <<<"$out"'
check "runner exits 0 whatever the reviewers did" '[ $rc -eq 0 ]'
reset
echo '{"reviewers":{"codex":{"local":"off"},"claude":{"local":"all"}}}' >"$REVIEWERS_SETTINGS_FILE"
echo '{"reviewers":[{"name":"claude","local":{"model":"my model"}}]}' >"$REVIEWERS_USER_FILE"
run run-local-reviews.sh
check "local.model reaches claude as REVIEW_MODEL, spaces intact" 'called "--model my model "'
reset
mkdir -p "$root/odd|dir x"
printf '#!/usr/bin/%s\necho "$2/odd-review.md"\n' "env bash" >"$root/odd|dir x/odd.sh"
chmod +x "$root/odd|dir x/odd.sh"
echo '{"reviewers":{"codex":{"local":"off"},"coderabbit":{"local":"off"},"claude":{"local":"off"}}}' >"$REVIEWERS_SETTINGS_FILE"
jq -n --arg c "$root/odd|dir x/odd.sh" '{reviewers:[{name:"odd",local:{command:$c,default:"all"}}]}' >"$REVIEWERS_USER_FILE"
run run-local-reviews.sh
check "a command path with a pipe and a space survives" '[ "$out" = "odd: $root/out/odd-review.md" ]'
reset
echo '{"reviewers":{"codex":{"local":"off"},"coderabbit":{"local":"off"},"claude":{"local":"off"}}}' >"$REVIEWERS_SETTINGS_FILE"
echo "{\"reviewers\":[{\"name\":\"../evil\",\"local\":{\"command\":\"$root/custom/one.sh\",\"default\":\"all\"}}]}" >"$REVIEWERS_USER_FILE"
run run-local-reviews.sh
check "an unsafe reviewer name is skipped with a warning, never run" '[ $rc -eq 0 ] && grep -q "unsafe name" "$root/err" && grep -q "^../evil: skipped" <<<"$out"'
reset
mkdir -p "$root/out"
echo stale >"$root/out/claude-review.md"
echo stale >"$root/out/claude-skipped.txt"
echo '{"reviewers":{"codex":{"local":"off"},"coderabbit":{"local":"off"},"claude":{"local":"all"}}}' >"$REVIEWERS_SETTINGS_FILE"
echo fail >"$root/state/claude_mode"
run run-local-reviews.sh
check "stale review and skipped files from an earlier run are cleared" '[ ! -e "$root/out/claude-review.md" ] && [ ! -e "$root/out/claude-skipped.txt" ]'
reset
cat >"$root/custom/long.sh" <<S
#!/usr/bin/env bash
echo \$\$ >"$root/custom/long.pid"
timeout 60 sleep 60 &
echo \$! >"$root/custom/child.pid"
wait
S
chmod +x "$root/custom/long.sh"
echo '{"reviewers":{"codex":{"local":"off"},"coderabbit":{"local":"off"},"claude":{"local":"off"}}}' >"$REVIEWERS_SETTINGS_FILE"
echo "{\"reviewers\":[{\"name\":\"long\",\"local\":{\"command\":\"$root/custom/long.sh\",\"default\":\"all\"}}]}" >"$REVIEWERS_USER_FILE"
rm -f "$root/custom/long.pid" "$root/custom/child.pid"
"$skill/run-local-reviews.sh" main "$root/out" >/dev/null 2>&1 </dev/null &
runner=$!
for _ in $(seq 1 50); do
  [ -s "$root/custom/long.pid" ] && break
  sleep 0.1
done
sleep 0.3
long_pid=$(<"$root/custom/long.pid")
child_pid=$(<"$root/custom/child.pid")
kill -TERM "$runner"
wait "$runner" 2>/dev/null
sleep 0.5
check "killing the runner leaves no reviewer or child running" '! kill -0 "$long_pid" 2>/dev/null && ! kill -0 "$child_pid" 2>/dev/null'
reset
cat >"$root/kill_spy.sh" <<S
kill() { echo "\$*" >>"$root/kills"; builtin kill "\$@"; }
S
echo '{"reviewers":{"codex":{"local":"off"},"coderabbit":{"local":"off"},"claude":{"local":"off"}}}' >"$REVIEWERS_SETTINGS_FILE"
echo "{\"reviewers\":[{\"name\":\"one\",\"local\":{\"command\":\"$root/custom/dirty.sh\",\"default\":\"all\"}}]}" >"$REVIEWERS_USER_FILE"
rm -f "$root/kills"
run run-local-reviews.sh BASH_ENV="$root/kill_spy.sh"
check "a normal run signals no (reaped) pid" '[ $rc -eq 0 ] && [ ! -s "$root/kills" ]'
reset
echo '{"reviewers":{"codex":{"local":"off"},"coderabbit":{"local":"off"},"claude":{"local":"off"}}}' >"$REVIEWERS_SETTINGS_FILE"
echo '{"reviewers":[{"name":"../evil","local":{"scope":"off","command":"x.sh"}}]}' >"$REVIEWERS_USER_FILE"
run run-local-reviews.sh
check "a disabled reviewer with an unsafe name draws no warning" '[ -z "$out" ] && ! grep -q "unsafe name" "$root/err"'
reset
echo '{"reviewers":{"codex":{"local":"off"},"coderabbit":{"local":"off"},"claude":{"local":"off"}}}' >"$REVIEWERS_SETTINGS_FILE"
run run-local-reviews.sh
check "all reviewers off: no output, exit 0" '[ $rc -eq 0 ] && [ -z "$out" ] && [ ! -s "$root/calls" ]'
check "bad usage exits 64" '"$skill/run-local-reviews.sh" 2>/dev/null; [ $? -eq 64 ]'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
