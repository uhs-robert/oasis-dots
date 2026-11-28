#!/usr/bin/env bash
# Tests that an optional install step failing warns and lets the install go on, and that a failing command in the
# middle of a step is not hidden by the guard. The static half checks that main() calls every optional step through
# run_optional_step. setup_tailnet_ssh and setup_agent_host stay bare on purpose: they abort when they fail.
# INSTALL_SH points the test at another copy of install.sh.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
install_sh="${INSTALL_SH:-$repo_dir/install.sh}"
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT
failures=0
fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

optional_steps=(install_greetd enable_keyd enable_power_profiles install_steam install_nvidia setup_voxtype
  setup_calendar_timer setup_syncthing setup_snapper)
for step in "${optional_steps[@]}"; do
  calls=$(grep -nE "(^|[[:space:];])${step}([[:space:];]|$)" "$install_sh" | grep -vE "^[0-9]+:[[:space:]]*#")
  [[ -n $calls ]] || fail "$step is never called in install.sh"
  while IFS= read -r line; do
    [[ -z $line || $line =~ run_optional_step[[:space:]]+${step}[[:space:]]+\" ]] || fail "unguarded optional step: $line"
  done <<<"$calls"
done
for step in setup_tailnet_ssh setup_agent_host; do
  if grep -qE "run_optional_step[[:space:]]+$step" "$install_sh"; then fail "$step must stay bare and abort"; fi
done

# Behavior: take the helper out of install.sh (which cannot be sourced: it runs main) and run it under set -e.
helper=$(sed -n '/^run_optional_step() {/,/^}/p' "$install_sh")
[[ -n $helper ]] || fail "run_optional_step is not defined in install.sh"

stubs="$scratch/bin"
mkdir -p "$stubs"
# keyd is present and not enabled yet, so enable_keyd reaches its sudo call, which fails.
printf '#!/usr/bin/env bash\nexit 1\n' >"$stubs/sudo"
printf '#!/usr/bin/env bash\nexit 1\n' >"$stubs/systemctl"
printf '#!/usr/bin/env bash\nexit 0\n' >"$stubs/keyd"
chmod +x "$stubs/sudo" "$stubs/systemctl" "$stubs/keyd"

# A step that relies on errexit, like the real ones: a bare failing command, then a success message.
bare_failing_step() {
  false
  echo "STEP-FALSE-SUCCESS"
}

run_scenario() { # prints the output, then "REACHED" when the install goes on after the helper
  bash -c "set -euo pipefail
    source '$repo_dir/lib/common/output.sh'
    source '$repo_dir/lib/install/system.sh'
    PATH='$stubs':\$PATH
    $helper
    $(declare -f bare_failing_step)
    $1
    echo REACHED" 2>&1
}

out=$(run_scenario 'run_optional_step bare_failing_step "bare step warning"')
[[ $out == *"bare step warning"* ]] || fail "no warning for a step whose bare command fails: $out"
[[ $out != *STEP-FALSE-SUCCESS* ]] || fail "step ran past its failed command"
[[ $out == *REACHED* ]] || fail "install stopped after a failed optional step"

out=$(run_scenario 'run_optional_step enable_keyd "keyd warning"')
[[ $out == *"keyd warning"* ]] || fail "no warning when enable_keyd's sudo fails: $out"
[[ $out == *REACHED* ]] || fail "install stopped after enable_keyd failed"

out=$(run_scenario 'run_optional_step true "never"')
[[ $out != *never* && $out == *REACHED* ]] || fail "a passing step must not warn: $out"

if [[ $failures -ne 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "ok: optional steps are guarded and failures warn"
