#!/usr/bin/env bash
# PreToolUse(Bash): warns when a command runs a voxcmd suite or the crate's cargo test/clippy by hand. Such a run records
# no pass, so the final `lib/check.sh --changed` runs the same step again behind the check lock; `lib/check.sh --only`
# runs it once and records it. Warn-only: the call goes through untouched, with a line of context for the agent.
# Iterating on one section (VOXCMD_ONLY_SECTIONS=) is the legitimate direct use, and CHECK_ALLOW_DIRECT=1 opts out.
set -u
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[[ $cmd == *VOXCMD_ONLY_SECTIONS=* || $cmd == *CHECK_ALLOW_DIRECT=1* ]] && exit 0

# The command-word anchors of check-in-background.sh, so a path that is only an argument (shellcheck, git diff, cat)
# does not count. The newline is a real one: ERE reads a written \n as the letter n.
start="(^|[;&|(]|"$'\n'")[[:space:]]*"
wrappers='(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|env|timeout[[:space:]]+[^[:space:]]+|(ba)?sh)[[:space:]]+)*'
dir='([^[:space:];&|]*/)?'
suite="${dir}(sandbox\.sh[[:space:]]+${dir})?(run[^/[:space:];&|]*)\.sh([[:space:]]|$)"
cargo='cargo[[:space:]]+([^;&|]*[[:space:]])?(test|clippy|nextest)([[:space:]]|$)'
# Inside voxcmd's tree a bare tests/run.sh or cargo test is voxcmd's: by the hook's cwd, or a cd or path in the command.
in_voxcmd=0
[[ $cwd == */home/voxcmd || $cwd == */home/voxcmd/* || $cmd =~ home/voxcmd || $cmd =~ cd[[:space:]]+[^\;\&\|]*voxcmd ]] && in_voxcmd=1

if [[ $cmd =~ ${start}${wrappers}${dir}home/voxcmd/tests/${suite} ]] ||
  { ((in_voxcmd)) && [[ $cmd =~ ${start}${wrappers}${suite} ]]; }; then
  # The suite is the match's last run*.sh, past any sandbox.sh.
  [[ ${BASH_REMATCH[0]} =~ (run[^/[:space:]]*)\.sh[[:space:]]*$ ]]
  script=${BASH_REMATCH[1]}
elif ((in_voxcmd)) && [[ $cmd =~ ${start}${wrappers}${cargo} ]]; then
  script=cargo
else
  exit 0
fi
case $script in
run-phrases) step=voxcmd-phrases ;;
run) step=voxcmd-click ;;
run-calendar) step=voxcmd-calendar ;;
run-wake) step=voxcmd-wake ;;
run-firefox-extension) step=voxcmd-firefox ;;
cargo) step=voxcmd-rust ;;
run-sessions | run-sequences | run-overview | run-monitors) step="none of its own; voxcmd-click runs it inside run.sh" ;;
*) step="none; this suite is not a check step" ;;
esac

message="Warning: this runs a voxcmd suite directly, so its pass is not recorded and the final \`lib/check.sh --changed <base>\` will run it again behind the check lock. Run \`lib/check.sh --only <step>\` instead (steps: voxcmd-phrases, voxcmd-click, voxcmd-calendar, voxcmd-wake, voxcmd-firefox, voxcmd-rust = fmt+clippy+test). Iterating on one section with VOXCMD_ONLY_SECTIONS is fine; finish with --only. Mapped step for this command: $step."
jq -nc --arg m "$message" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
