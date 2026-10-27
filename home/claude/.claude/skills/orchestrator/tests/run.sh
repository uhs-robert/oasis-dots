#!/usr/bin/env bash
# Replays reviewers.sh against temp layer files: merge order, removal, shorthand, bad input and the repo root lookup.
# shellcheck disable=SC2016,SC2034 # The check strings are single-quoted on purpose (eval'd later); rc and err are read only inside them.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../reviewers.sh}
builtin_real=$here/../reviewers.json
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
mkdir -p "$root/home" "$root/repo/.claude"
git -C "$root/repo" init -q
export HOME=$root/home
export REVIEWERS_BUILTIN_FILE=$builtin_real
export REVIEWERS_USER_FILE=$root/user.json
export REVIEWERS_SETTINGS_FILE=$root/settings.json
repo_file=$root/repo/.claude/reviewers.json

reset() { rm -f "$REVIEWERS_USER_FILE" "$REVIEWERS_SETTINGS_FILE" "$repo_file"; }
# run [dir]: resolved JSON in $out, stderr in $err, status in $rc
run() {
  out=$("$script" list "${1:-$root/repo}" 2>"$root/err")
  rc=$?
  err=$(<"$root/err")
}
# field NAME JQ_PATH
field() { jq -r --arg n "$1" ".[] | select(.name == \$n) | $2" <<<"$out"; }

echo "== built-in only"
reset
run
check "exit 0" '[ $rc -eq 0 ]'
check "names in file order" '[ "$(jq -r "map(.name) | join(\",\")" <<<"$out")" = codex,coderabbit,claude ]'
check "codex scope all, gate auto" '[ "$(field codex ".local.scope + \"/\" + .gate")" = all/auto ]'
check "coderabbit scope off, gate auto" '[ "$(field coderabbit ".local.scope + \"/\" + .gate")" = off/auto ]'
check "claude scope off, gate never" '[ "$(field claude ".local.scope + \"/\" + .gate")" = off/never ]'
check "claude has no github block" '[ "$(field claude "has(\"github\")")" = false ]'
check "coderabbit keeps default_when_on" '[ "$(field coderabbit ".local.default_when_on")" = public ]'
check "no stderr" '[ -z "$err" ]'

echo "== user layer"
reset
cat >"$REVIEWERS_USER_FILE" <<'J'
{"reviewers":[
 {"name":"coderabbit","local":{"scope":"public"},"github":{"start_s":60}},
 {"name":"mine","label":"Mine","local":{"command":"mine.sh","binary":"mine","default":"all"}}
]}
J
run
check "field-by-field merge keeps unspecified fields" '[ "$(field coderabbit ".github.app_slug + \"/\" + (.github.start_s|tostring) + \"/\" + .github.signal")" = coderabbitai/60/check_run ]'
check "user scope wins over built-in default" '[ "$(field coderabbit ".local.scope")" = public ]'
check "new entry appended after built-ins" '[ "$(jq -r "map(.name) | join(\",\")" <<<"$out")" = codex,coderabbit,claude,mine ]'
check "new entry gets default scope and gate" '[ "$(field mine ".local.scope + \"/\" + .gate")" = all/auto ]'
check "arrays are replaced, not concatenated" '
  printf "%s" "{\"reviewers\":[{\"name\":\"coderabbit\",\"github\":{\"logins\":[\"x\"]}}]}" >"$REVIEWERS_USER_FILE"; run
  [ "$(field coderabbit ".github.logins | join(\",\")")" = x ]'

echo "== enabled false"
reset
echo '{"reviewers":[{"name":"claude","enabled":false}]}' >"$REVIEWERS_USER_FILE"
run
check "entry removed" '[ "$(jq -r "map(.name) | join(\",\")" <<<"$out")" = codex,coderabbit ]'
reset
echo '{"reviewers":[{"name":"claude","enabled":false}]}' >"$REVIEWERS_USER_FILE"
echo '{"reviewers":[{"name":"claude","enabled":true}]}' >"$repo_file"
run
check "higher layer enabled true restores it" '[ "$(field claude ".name")" = claude ]'
check "enabled key never leaks into output" '[ "$(jq "map(has(\"enabled\")) | any" <<<"$out")" = false ]'

echo "== settings layer"
reset
echo '{"reviewers":{"codex":{"local":"public","gate":"always"},"ghost":{"local":"all"}}}' >"$REVIEWERS_SETTINGS_FILE"
run
check "settings sets scope and gate" '[ "$(field codex ".local.scope + \"/\" + .gate")" = public/always ]'
check "settings never adds an entry" '[ "$(field ghost ".name")" = "" ]'
check "settings leaves command intact" '[ "$(field codex ".local.command")" = codex-review.sh ]'
echo '{"reviewers":[{"name":"codex","local":{"scope":"all"}}]}' >"$REVIEWERS_USER_FILE"
run
check "settings beats user file" '[ "$(field codex ".local.scope")" = public ]'
echo '{"reviewers":[{"name":"codex","local":"off","gate":"never"}]}' >"$repo_file"
run
check "repo file beats settings (scope shorthand)" '[ "$(field codex ".local.scope + \"/\" + .gate")" = off/never ]'

echo "== repo file lookup"
check "repo file read from the repo root when run in a subdirectory" '
  mkdir -p "$root/repo/sub/dir"; run "$root/repo/sub/dir"
  [ "$(field codex ".gate")" = never ]'
check "outside a git repo the repo file is not read" '
  mkdir -p "$root/plain"; run "$root/plain"
  [ "$(field codex ".gate")" = always ]'

echo "== bad input"
reset
echo '{not json' >"$REVIEWERS_USER_FILE"
run
check "invalid JSON layer skipped, rest resolves" '[ $rc -eq 0 ] && [ "$(jq length <<<"$out")" = 3 ]'
check "invalid JSON layer warns with the path" 'grep -q "user.json is not a single valid JSON value" <<<"$err"'
echo '{"reviewers":"nope"}' >"$REVIEWERS_USER_FILE"
run
check "wrong-typed reviewers skipped with a warning" '[ $rc -eq 0 ] && grep -q "wrong type" <<<"$err"'
echo '[1,2]' >"$REVIEWERS_USER_FILE"
run
check "non-object layer skipped with a warning" '[ $rc -eq 0 ] && grep -q "layer ignored" <<<"$err"'
echo '{"reviewers":[{"label":"no name"},"str",{"name":"codex","gate":"sometimes","local":{"scope":"huge"}}]}' >"$REVIEWERS_USER_FILE"
run
check "nameless entries skipped with a warning" 'grep -q "without a string name" <<<"$err"'
check "invalid gate ignored, built-in value kept" '[ "$(field codex ".gate")" = auto ] && grep -q "invalid gate" <<<"$err"'
check "invalid scope becomes off with a warning" '[ "$(field codex ".local.scope")" = off ] && grep -q "invalid local scope" <<<"$err"'
reset
echo '{bad' >"$REVIEWERS_SETTINGS_FILE"
run
check "invalid Settings file skipped" '[ $rc -eq 0 ] && [ "$(jq length <<<"$out")" = 3 ]'
check "missing layer files are silent" 'reset; run; [ -z "$err" ]'
check "invalid built-in file is fatal" '
  echo "{bad" >"$root/b.json"; out=$(REVIEWERS_BUILTIN_FILE=$root/b.json "$script" list "$root/repo" 2>/dev/null); [ $? -eq 1 ]'
check "missing built-in file is fatal" '
  out=$(REVIEWERS_BUILTIN_FILE=$root/none.json "$script" list "$root/repo" 2>/dev/null); [ $? -eq 1 ]'

echo "== review round 1"
reset
echo '{"reviewers":[{"name":"a","local":{"command":"a.sh","default":"sometimes"}},{"name":"b","local":"public","enabled":"false"},{"name":"c","label":"no local"}]}' >"$REVIEWERS_USER_FILE"
run
check "invalid local.default becomes off with a warning" '[ "$(field a ".local.scope + \"/\" + .local.default")" = off/off ] && grep -q "invalid local default" <<<"$err"'
check "non-boolean enabled is ignored with a warning" '[ "$(field b ".name")" = b ] && grep -q "enabled must be true or false" <<<"$err"'
check "entry without local config gets scope off" '[ "$(field c ".local.scope")" = off ]'
check "built-in entries without local also normalise" '[ "$(field claude ".local.scope")" = off ]'

reset
echo '{"reviewers":{"codex":{"local":"public","label":"X","github":{}},"coderabbit":"on","ghost":{"gate":"never"}}}' >"$REVIEWERS_SETTINGS_FILE"
run
check "Settings keeps local and gate fields" '[ "$(field codex ".local.scope")" = public ]'
check "Settings ignores other fields with a warning" '[ "$(field codex ".label")" = Codex ] && grep -q "Settings may only set local and gate, ignored label" <<<"$err"'
check "Settings non-object value warns" 'grep -q "coderabbit: value is not an object" <<<"$err"'

# builtin_fails JSON: the built-in file holding JSON must exit 1 and say why
builtin_fails() {
  printf "%s" "$1" >"$root/b.json"
  out=$(REVIEWERS_BUILTIN_FILE=$root/b.json "$script" list "$root/repo" 2>"$root/err")
  rc=$?
  err=$(<"$root/err")
  [ $rc -eq 1 ] && [ -n "$err" ]
}
check "built-in with wrong-typed reviewers is fatal" 'builtin_fails "{\"reviewers\":\"x\"}"'
check "built-in with no reviewers key is fatal" 'builtin_fails "{}"'
check "built-in with a nameless entry is fatal" 'builtin_fails "{\"reviewers\":[{\"label\":\"x\"}]}"'
check "built-in with an invalid gate is fatal" 'builtin_fails "{\"reviewers\":[{\"name\":\"x\",\"gate\":\"maybe\"}]}"'
check "built-in with an invalid default is fatal" 'builtin_fails "{\"reviewers\":[{\"name\":\"x\",\"local\":{\"default\":\"all!\"}}]}"'
check "a valid built-in file stays accepted" '! builtin_fails "{\"reviewers\":[{\"name\":\"x\"}]}" && [ $rc -eq 0 ]'

reset
echo '{"reviewers":{"claude":{"local":5}}}' >"$REVIEWERS_SETTINGS_FILE"
echo '{"reviewers":[{"name":"n","github":null},{"name":"coderabbit","github":null}]}' >"$REVIEWERS_USER_FILE"
run
check "non-string, non-object local warns" 'grep -q "claude: local is neither a string nor an object" <<<"$err"'
check "github null is dropped from output" '[ "$(field n "has(\"github\")")" = false ]'
check "github null does not erase a lower layer github block" '[ "$(field coderabbit ".github.app_slug")" = coderabbitai ]'

echo "== empty and multi-value layers"
for content in "" "   " "{\"reviewers\":[]} {\"reviewers\":[]}"; do
  reset
  printf '%s\n' "$content" >"$REVIEWERS_USER_FILE"
  run
  check "user file [$content] is skipped, others resolve" '[ $rc -eq 0 ] && [ "$(jq length <<<"$out")" = 3 ] && grep -q "single valid JSON value" <<<"$err"'
done
check "empty built-in file is fatal" ': >"$root/b.json"; out=$(REVIEWERS_BUILTIN_FILE=$root/b.json "$script" list "$root/repo" 2>/dev/null); [ $? -eq 1 ]'

echo "== usage"
check "unknown subcommand exits 64" '"$script" bogus 2>/dev/null; [ $? -eq 64 ]'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
