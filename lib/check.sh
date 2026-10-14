#!/bin/sh
set -u

# Runs the validation steps and reports all failures, rather than stopping at
# the first one: a single run should show everything that needs fixing.
#
#   lib/check.sh                  every step
#   lib/check.sh --changed <base> only the steps the files changed since <base> can affect
#   lib/check.sh --paths-from <file|-> like --changed, but the changed paths are the lines of the file (or stdin), relative to the
#                                 repository root, instead of `git diff <base>`: a commit's staged paths, say
#   lib/check.sh --plan [--changed <base>|--paths-from <file|->] prints the plan (the summary line, then each shellcheck list) and exits 0, running nothing
#
# A step that passes is recorded (lib/check-passed.sh) under a key hashing the content of the files it reads, the same
# files whose change makes --changed pick it (step_scope); a later run skips a step whose key already passed, uncommitted and
# untracked content included. A run that leaves the tree clean also records the tree: when every step passed for its
# content, or for --changed <base> on top of a base recorded as passed; and a --changed run records that it passed
# against <base>, which is what the PR hook looks up.
#
# CHECK_FULL=1 makes --changed run everything, and runs every step whatever passed before. CHECK_JOBS sets how many steps
# run at once (default min(cores/2, 4)); 1 runs them one after another with live output. CHECK_SKIP_STEPS="step ..." drops
# those steps whatever the scope says (the summary line lists them). Everything runs at nice 19 in the idle IO class, and
# the voxcmd suites each hold one of CHECK_HEAVY_SLOTS machine-wide slots (lib/check-lock.sh), waiting at most
# CHECK_LOCK_WAIT_SECS (default 1200) for one; CHECK_NO_LOCK=1 runs them without a slot, for a check that must never
# wait (the commit hook).
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
self=$script_dir/check.sh

cd "$repo_dir" || exit 1

# Every step, longest first. The voxcmd steps are timing-sensitive, so they run one after another in a slot
# of their own, ahead of the rest.
voxcmd_steps='voxcmd-phrases voxcmd-click voxcmd-calendar voxcmd-wake voxcmd-firefox'
other_steps='check-scope check-cache firefox-policy qmllint shellcheck calendar-sync owner-test-bar ship-batch merge-prs shfmt stylua luacheck lock-skins style-exports time-format calendar-sync-syntax agent-hooks stale-shells-hook notification-markup packages symlinks git-diff-check whitespace conflicts'

# Shell files by the group they are linted in. Symlinks are skipped (their target is linted itself).
# worktrees/ holds other agents' scratch copies and skills/synced/ is vendored.
plain_shell_files() {
  printf '%s\n' install.sh uninstall.sh lib/*.sh demo/*.sh home/hypr/.config/hypr/scripts/state-write home/voxcmd/tests/*.sh home/calendar/tests/*.sh lib/tests/*.sh
}
# Linted with -x, which follows `source`, so each is checked together with its libraries.
sourcing_shell_files() {
  qs_scripts=home/quickshell/.config/quickshell/scripts
  printf '%s\n' "$qs_scripts"/lib/*.sh "$qs_scripts/ff7-audio" "$qs_scripts/goldeneye-audio" "$qs_scripts/mgs2-audio" "$qs_scripts/ocarina-audio"
}
# Tracked *.sh plus extension-less files with a sh/bash shebang.
agent_shell_files() {
  git ls-files -- .claude home/claude/.claude ':!:.claude/worktrees' ':!:home/claude/.claude/skills/synced' |
    while IFS= read -r file; do
      [ -f "$file" ] && [ ! -L "$file" ] || continue
      case "${file##*/}" in
      *.sh) printf '%s\n' "$file" ;;
      *.*) ;;
      *) head -n 1 "$file" | grep -Eq '^#!.*[/ ](ba|da|z)?sh( |$)' && printf '%s\n' "$file" ;;
      esac
    done
}

# One step's work, run by its own `check.sh --run-step`; the lists are the files to lint.
step_body() {
  case $1 in
  shellcheck)
    status=0
    [ ! -s "$logs/plain.list" ] || xargs shellcheck <"$logs/plain.list" || status=1
    [ ! -s "$logs/sourcing.list" ] || xargs shellcheck -x -P SCRIPTDIR <"$logs/sourcing.list" || status=1
    [ ! -s "$logs/agent.list" ] || xargs shellcheck -x -P SCRIPTDIR <"$logs/agent.list" || status=1
    return $status
    ;;
  shfmt)
    status=0
    cat "$logs/plain.fmt.list" "$logs/sourcing.fmt.list" | grep . | xargs -r shfmt -i 2 -d || status=1
    [ ! -s "$logs/agent.fmt.list" ] || xargs shfmt -i 2 -d <"$logs/agent.fmt.list" || status=1
    return $status
    ;;
  check-scope) bash ./lib/tests/check-scope.sh ;;
  check-cache) bash ./lib/tests/check-cache.sh && bash ./lib/tests/check-lock.sh ;;
  firefox-policy) bash ./lib/tests/firefox-policy.sh ;;
  stylua) stylua --respect-ignores --check home/hypr/.config/hypr ;;
  luacheck) sh ./lib/check-lua.sh ;;
  qmllint) sh ./lib/check-qml.sh ;;
  lock-skins) sh ./lib/check-lock-skins.sh ;;
  style-exports) sh ./lib/check-style-exports.sh ;;
  time-format) sh ./lib/check-time-format.sh ;;
  voxcmd-phrases) bash ./home/voxcmd/tests/run-phrases.sh ;;
  voxcmd-click) bash ./home/voxcmd/tests/run.sh ;;
  voxcmd-calendar) bash ./home/voxcmd/tests/run-calendar.sh ;;
  voxcmd-wake) bash ./home/voxcmd/tests/run-wake.sh ;;
  voxcmd-firefox) bash ./home/voxcmd/tests/run-firefox-extension.sh ;;
  # py_compile would drop a __pycache__ into the stow package, so this parses instead.
  calendar-sync-syntax) python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' ./home/calendar/.local/bin/calendar-sync ;;
  calendar-sync) bash ./home/calendar/tests/run.sh ;;
  agent-hooks) bash ./home/claude/.claude/hooks/tests/guard-masked-checks.sh && bash ./.claude/hooks/tests/check-before-pr.sh ;;
  stale-shells-hook) bash ./home/claude/.claude/hooks/tests/stale-shells.sh ;;
  owner-test-bar) bash ./.claude/skills/owner-test-bar/tests/run.sh ;;
  ship-batch) bash ./.claude/skills/ship-batch/tests/run.sh ;;
  merge-prs) bash ./home/claude/.claude/skills/merge-prs/tests/run.sh ;;
  notification-markup) node ./home/quickshell/tests/notification_markup.js ;;
  packages) sh ./lib/check-packages.sh ;;
  symlinks) sh ./lib/check-symlinks.sh ;;
  git-diff-check) git diff --check HEAD ;;
  whitespace) sh ./lib/check-whitespace.sh ;;
  conflicts) sh ./lib/check-conflicts.sh ;;
  esac
}

# Runs one step with its output buffered in $logs, so parallel steps never interleave; a failing step
# drops a marker file. Serial runs show the output live instead.
run_step() {
  name=$1
  started=$(date +%s)
  if [ "$jobs" -le 1 ]; then
    printf '== %s\n' "$name"
    { step_body "$name" 2>&1 || echo "$?" >"$logs/$name.failed"; } | tee "$logs/$name.log"
    return 0
  fi
  step_body "$name" >"$logs/$name.log" 2>&1 || echo "$?" >"$logs/$name.failed"
  took=$(($(date +%s) - started))
  until mkdir "$logs/print.lock" 2>/dev/null; do sleep 0.05; done
  if [ -e "$logs/$name.failed" ]; then
    printf '== %s FAILED (%ss)\n' "$name" "$took"
    cat "$logs/$name.log"
  else
    printf '== %s ok (%ss)\n' "$name" "$took"
  fi
  rmdir "$logs/print.lock"
}

if [ "${1:-}" = --run-step ]; then
  logs=$CHECK_LOGS jobs=$CHECK_JOBS
  run_step "$2"
  exit 0
fi

usage='usage: lib/check.sh [--plan] [--changed <base> | --paths-from <file|->]'
changed_base='' plan_only='' paths_from=''
while [ $# -gt 0 ]; do
  case $1 in
  --plan) plan_only=1 ;;
  --changed)
    [ $# -ge 2 ] || {
      echo "$usage" >&2
      exit 2
    }
    changed_base=$2
    shift
    ;;
  --paths-from)
    [ $# -ge 2 ] || {
      echo "$usage" >&2
      exit 2
    }
    paths_from=$2
    shift
    ;;
  *)
    echo "$usage" >&2
    exit 2
    ;;
  esac
  shift
done

# shellcheck source-path=SCRIPTDIR source=check-lock.sh
. "$script_dir/check-lock.sh"
[ -n "$plan_only" ] || check_lower_priority

logs=$(mktemp -d) || exit 1
trap 'rm -rf "$logs"' EXIT
trap 'exit 1' INT TERM

jobs=${CHECK_JOBS:-$(($(nproc 2>/dev/null || echo 2) / 2))}
[ "$jobs" -le 4 ] || jobs=4
[ "$jobs" -ge 1 ] || jobs=1

# What a path can affect: path_scopes leaves the scopes it reaches in $scopes. A step is dropped only when every changed
# path is claimed by some rule here and none of them reaches it, so a path nobody claimed ("all") runs everything. The same
# rules decide what a step's pass record covers: the files of its scope (step_scope) and every "all" file.
path_scopes() {
  scopes=''
  case $1 in
  lib/check-*.sh | lib/tests/check-*.sh) scopes=checkscope ;;
  esac
  case $1 in
  lib/check.sh | lib/check-lock.sh | lib/check-passed.sh | justfile | .claude/check-commands) scopes="$scopes all" ;;
  lib/check-lua.sh | .luacheckrc | home/hypr/*) scopes="$scopes lua" ;;
  # Ahead of the greeter's QML arm, since case takes only the first match.
  system/etc/greetd/*.lua) scopes="$scopes lua qml" ;;
  lib/check-qml.sh | lib/check-lock-skins.sh | lib/check-style-exports.sh | lib/check-time-format.sh | system/etc/greetd/quickshell/*) scopes="$scopes qml" ;;
  home/quickshell/tests/*) scopes="$scopes node" ;;
  home/quickshell/*) scopes="$scopes qml node" ;;
  home/voxcmd/* | extras/voxcmd-firefox/*) scopes="$scopes voxcmd" ;;
  # The installer and the justfile call it, but those already run everything.
  lib/firefox-policy.sh | lib/tests/firefox-policy.sh) scopes="$scopes policy" ;;
  home/calendar/*) scopes="$scopes calendar" ;;
  home/claude/.claude/hooks/* | .claude/hooks/*) scopes="$scopes hooks" ;;
  .claude/skills/owner-test-bar/*) scopes="$scopes bar" ;;
  .claude/skills/ship-batch/* | home/claude/.claude/skills/merge-prs/*) scopes="$scopes ship" ;;
  system/etc/greetd/*) scopes="$scopes lua" ;;
  # Only the steps that always run (whitespace, conflicts, symlinks, packages, git diff) look at these,
  # plus the shell linters for the shell files among them.
  lib/* | install.sh | uninstall.sh | demo/* | packages/* | docs/* | extras/* | system/* | home/* | .claude/* | *.md | LICENSE) ;;
  *) scopes="$scopes all" ;;
  esac
}

# The scope each step reads, which decides both when a change reaches it and what its pass record covers. "tree": the
# cheap steps that scan the whole checkout, always run. "shell": the files in the shell lists below.
step_scope() {
  case $1 in
  packages | symlinks | git-diff-check | whitespace | conflicts) step_scope=tree ;;
  check-scope | check-cache) step_scope=checkscope ;;
  firefox-policy) step_scope=policy ;;
  shellcheck | shfmt) step_scope=shell ;;
  stylua | luacheck) step_scope=lua ;;
  qmllint | lock-skins | style-exports | time-format) step_scope=qml ;;
  voxcmd-*) step_scope=voxcmd ;;
  calendar-sync | calendar-sync-syntax) step_scope=calendar ;;
  agent-hooks | stale-shells-hook) step_scope=hooks ;;
  owner-test-bar) step_scope=bar ;;
  ship-batch | merge-prs) step_scope=ship ;;
  notification-markup) step_scope=node ;;
  esac
}

reached=' '
reaches() {
  case $reached in *" $1 "*) return 0 ;; esac
  return 1
}
scope_changed_files() {
  while IFS= read -r path; do
    path_scopes "$path"
    for scope in $scopes; do reaches "$scope" || reached="$reached$scope "; done
  done
}

if [ -n "$paths_from" ] && [ -z "${CHECK_FULL:-}" ]; then
  # A path list is trusted as given (no untracked files added); a listed path that is gone counts as deleted.
  if [ "$paths_from" = - ]; then cat >"$logs/changed.raw"; else cat -- "$paths_from" >"$logs/changed.raw" || exit 1; fi
  grep . "$logs/changed.raw" | sort -u >"$logs/changed"
  while IFS= read -r path; do [ -e "$path" ] || [ -L "$path" ] || printf '%s\n' "$path"; done <"$logs/changed" >"$logs/deleted"
  scope_changed_files <"$logs/changed"
  scope_label="scoped to $(wc -l <"$logs/changed" | tr -d ' ') listed files"
elif [ -n "$changed_base" ] && [ -z "${CHECK_FULL:-}" ] && git rev-parse --verify -q "$changed_base^{commit}" >/dev/null &&
  { git diff --name-only --no-renames "$changed_base" -- && git ls-files -o --exclude-standard; } >"$logs/changed.raw" 2>/dev/null; then
  sort -u "$logs/changed.raw" >"$logs/changed"
  git diff --name-only --no-renames --diff-filter=D "$changed_base" -- >"$logs/deleted" 2>/dev/null
  scope_changed_files <"$logs/changed"
  scope_label="scoped to $(wc -l <"$logs/changed" | tr -d ' ') files changed since $changed_base"
else
  [ -z "$changed_base" ] || [ -n "${CHECK_FULL:-}" ] || echo "check: cannot diff against $changed_base, running everything" >&2
  reached=' all '
  : >"$logs/changed"
  scope_label=full
fi

# The shell lists. Scoped, shfmt sees only changed files, and shellcheck lints a list whole when any member changed,
# since a member can source another.
plain_shell_files >"$logs/plain.all"
sourcing_shell_files >"$logs/sourcing.all"
agent_shell_files >"$logs/agent.all"
cat "$logs/plain.all" "$logs/sourcing.all" >"$logs/fmt.all"
if reaches all; then
  cp "$logs/plain.all" "$logs/plain.list"
  cp "$logs/sourcing.all" "$logs/sourcing.list"
  cp "$logs/agent.all" "$logs/agent.list"
  cp "$logs/plain.all" "$logs/plain.fmt.list"
  cp "$logs/sourcing.all" "$logs/sourcing.fmt.list"
  cp "$logs/agent.all" "$logs/agent.fmt.list"
else
  grep -Fxf "$logs/changed" "$logs/plain.all" >"$logs/plain.fmt.list"
  grep -Fxf "$logs/changed" "$logs/sourcing.all" >"$logs/sourcing.fmt.list"
  grep -Fxf "$logs/changed" "$logs/agent.all" >"$logs/agent.fmt.list"
  # A sourced file is read by shellcheck only when it is on the same command line (the test runners source their lib.sh),
  # so a change to any of these lints all of them together, as a full run does.
  if [ -s "$logs/plain.fmt.list" ] || [ -s "$logs/deleted" ]; then cp "$logs/plain.all" "$logs/plain.list"; else : >"$logs/plain.list"; fi
  # A deleted file is in no list any more, yet a member that sourced it now fails, so any deletion lints both groups.
  if [ -s "$logs/sourcing.fmt.list" ] || [ -s "$logs/deleted" ]; then cp "$logs/sourcing.all" "$logs/sourcing.list"; else : >"$logs/sourcing.list"; fi
  if [ -s "$logs/agent.fmt.list" ] || [ -s "$logs/deleted" ]; then cp "$logs/agent.all" "$logs/agent.list"; else : >"$logs/agent.list"; fi
fi

# Optional tooling: a step whose tool is missing says so and does not run, so validation stays dependency-light.
have() { command -v "$1" >/dev/null 2>&1; }
tool_missing() {
  case $1 in
  shellcheck | shfmt | stylua) have "$1" || echo "skip: $1 not installed" ;;
  firefox-policy) have jq || echo 'skip: the firefox policy test needs jq' ;;
  voxcmd-*) { have jq && have fzf; } || echo 'skip: voxcmd phrases need jq and fzf' ;;
  calendar-sync) python3 -c 'import icalendar, recurring_ical_events' >/dev/null 2>&1 || echo 'skip: calendar-sync tests need python-icalendar and python-recurring-ical-events' ;;
  agent-hooks | stale-shells-hook | owner-test-bar) have jq || echo 'skip: agent hook and owner-test-bar tests need jq' ;;
  notification-markup) have node || echo 'skip: notification markup tests need node' ;;
  esac
}
# Whether a step is in scope: the cheap always-run steps, or one a changed path reaches.
in_scope() {
  reaches all && return 0
  step_scope "$1"
  case $step_scope in
  tree) true ;;
  shell)
    case $1 in
    shellcheck) [ -s "$logs/plain.list" ] || [ -s "$logs/sourcing.list" ] || [ -s "$logs/agent.list" ] ;;
    shfmt) [ -s "$logs/plain.fmt.list" ] || [ -s "$logs/sourcing.fmt.list" ] || [ -s "$logs/agent.fmt.list" ] ;;
    esac
    ;;
  *) reaches "$step_scope" ;;
  esac
}

# The content the steps read: the tracked and untracked (not ignored) files as they are in the working tree, written as a
# tree through a scratch index, so neither the real index nor HEAD moves. Prints the tree.
snapshot_tree() {
  [ -e "$logs/snapshot.index" ] || cp "$(git rev-parse --git-path index)" "$logs/snapshot.index" 2>/dev/null
  GIT_INDEX_FILE=$logs/snapshot.index git add -A . >/dev/null 2>&1 && GIT_INDEX_FILE=$logs/snapshot.index git write-tree
}

# Writes the files of tree $1 to $2, one "<scopes>\t<mode> <type> <object>\t<path>" line each, for step_key.
tab=$(printf '\t')
classify_tree() {
  git -c core.quotePath=false ls-tree -r --full-tree "$1" | while IFS= read -r line; do
    path_scopes "${line#*"$tab"}"
    printf ' %s \t%s\n' "$scopes" "$line"
  done >"$2"
}

# Prints the key a step's pass is recorded under: a hash of its name and of every file it reads, from the classified tree
# $2 of tree $3. $1 is the step; $4 is "run" for the shell lists this run lints or "full" for the whole lists. Fails when
# a file the step reads is not in the tree (an ignored file in a shell list), since its content would go unkeyed.
step_key() {
  step_scope "$1"
  (
    echo "check-step-key 1 $1"
    case $step_scope in
    tree)
      # symlinks skips the links into a repos/ that is not set up, and git-diff-check compares with HEAD.
      echo "$3 $coverage"
      [ "$1" != git-diff-check ] || git rev-parse 'HEAD^{tree}'
      ;;
    shell)
      for group in plain sourcing agent; do
        if [ "$4" = full ]; then list=$logs/$group.all; elif [ "$1" = shfmt ]; then list=$logs/$group.fmt.list; else list=$logs/$group.list; fi
        echo "group $group"
        awk -F '\t' 'FILENAME == ARGV[1] { if ($0 != "") want[$0] = 1; next } $3 in want { print; delete want[$3] }
          END { for (path in want) exit 3 }' "$list" "$2" || exit 1
      done
      awk -F '\t' 'index($1, " all ")' "$2"
      ;;
    *) awk -F '\t' -v scope=" $step_scope " 'index($1, scope) || index($1, " all ")' "$2" ;;
    esac
  ) >"$logs/key.input" || return 1
  git hash-object "$logs/key.input"
}

# Each step's key is computed before the run and again after it; a pass is recorded only when they agree, so a file
# edited while the step ran never gets a pass recorded for content the step did not see.
cache_tree='' coverage=no-repos
[ -z "$(find repos -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ] || coverage=with-repos
if [ -z "$plan_only" ]; then
  cache_tree=$(snapshot_tree) && classify_tree "$cache_tree" "$logs/tree.before" || cache_tree=''
fi

ran='' passed_before='' skipped_by_scope='' skipped_by_request='' voxcmd_run='' other_run=''
for name in $voxcmd_steps $other_steps; do
  case " ${CHECK_SKIP_STEPS:-} " in
  *" $name "*)
    skipped_by_request="$skipped_by_request $name"
    continue
    ;;
  esac
  in_scope "$name" || {
    skipped_by_scope="$skipped_by_scope $name"
    continue
  }
  missing=''
  # The plan is the same on a machine without the tools, so the scope test does not depend on them.
  [ -n "$plan_only" ] || missing=$(tool_missing "$name")
  if [ -n "$missing" ]; then
    echo "$missing" >>"$logs/skips"
    continue
  fi
  if [ -n "$cache_tree" ] && step_key "$name" "$logs/tree.before" "$cache_tree" run >"$logs/$name.key"; then
    if [ -z "${CHECK_FULL:-}" ] && lib/check-passed.sh step-is-passed "$name" "$(cat "$logs/$name.key")"; then
      passed_before="$passed_before $name"
      continue
    fi
  else
    rm -f "$logs/$name.key"
  fi
  ran="$ran $name"
  case " $voxcmd_steps " in
  *" $name "*) voxcmd_run="$voxcmd_run $name" ;;
  *) other_run="$other_run $name" ;;
  esac
done
[ ! -s "$logs/skips" ] || sort -u "$logs/skips"
echo "check: $scope_label; ran:$ran;${passed_before:+ skipped (passed for these inputs):$passed_before;} skipped by scope:${skipped_by_scope:- none}${skipped_by_request:+; skipped by request:$skipped_by_request}"

for name in $passed_before; do printf '== %s skipped (passed for these inputs)\n' "$name"; done

if [ -n "$plan_only" ]; then
  for group in plain sourcing agent; do sed "s|^|shellcheck $group: |" "$logs/$group.list"; done
  exit 0
fi

export CHECK_LOGS="$logs" CHECK_JOBS="$jobs"
if [ "$jobs" -le 1 ]; then
  for name in $voxcmd_run $other_run; do sh "$self" --run-step "$name" 7>&-; done
else
  lane_pid=''
  pool=$jobs
  if [ -n "$voxcmd_run" ]; then
    pool=$((jobs - 1))
    (for name in $voxcmd_run; do sh "$self" --run-step "$name" 7>&-; done) &
    lane_pid=$!
  fi
  # shellcheck disable=SC2086 # step names have no spaces
  [ -z "$other_run" ] || printf '%s\n' $other_run | xargs -P "$pool" -I{} sh "$self" --run-step {} 7>&-
  [ -z "$lane_pid" ] || wait "$lane_pid"
fi

failed=''
for name in $ran; do
  [ ! -e "$logs/$name.failed" ] || failed="$failed $name"
done
if [ -n "$failed" ]; then
  printf 'FAILED:%s\n' "$failed" >&2
  for name in $failed; do
    printf '\n== %s (last 25 lines)\n' "$name" >&2
    tail -n 25 "$logs/$name.log" >&2
  done
fi

# Records what passed. A step counts only when its inputs are what they were when it started.
if [ -n "$cache_tree" ] && after_tree=$(snapshot_tree) && classify_tree "$after_tree" "$logs/tree.after"; then
  for name in $ran; do
    [ ! -e "$logs/$name.failed" ] && [ -s "$logs/$name.key" ] || continue
    key=$(step_key "$name" "$logs/tree.after" "$after_tree" run) || continue
    [ "$key" != "$(cat "$logs/$name.key")" ] || lib/check-passed.sh step-record "$name" "$key"
  done
else
  after_tree=''
fi
[ -z "$failed" ] || exit 1

# A whole-tree record means HEAD's tree, so it needs a working tree with nothing uncommitted or untracked that was not
# edited during the run. --paths-from checks a list someone chose, which vouches for no tree.
every_step_passed() {
  for name in $voxcmd_steps $other_steps; do
    [ -z "$(tool_missing "$name")" ] || continue
    key=$(step_key "$name" "$logs/tree.after" "$after_tree" full) && lib/check-passed.sh step-is-passed "$name" "$key" || return 1
  done
}
if [ -z "$paths_from" ] && [ -n "$after_tree" ] && [ "$after_tree" = "$cache_tree" ] &&
  [ "$after_tree" = "$(git rev-parse 'HEAD^{tree}')" ]; then
  [ -z "$changed_base" ] || lib/check-passed.sh record-changed "$changed_base" || true
  # Inductive: a base whose every step passed, plus a scoped pass over everything changed since, vouches for the tree.
  if every_step_passed || { [ -n "$changed_base" ] && lib/check-passed.sh passed-somewhere "$changed_base"; }; then
    lib/check-passed.sh record || true
  fi
fi

echo 'All checks passed'
