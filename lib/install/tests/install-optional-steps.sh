#!/usr/bin/env bash
# Static check: each optional step in install.sh main() is guarded with "|| warn", so one failing step cannot abort the
# install under set -e. setup_tailnet_ssh and setup_agent_host stay bare on purpose: they abort when they fail.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
install_sh="$repo_dir/install.sh"
optional_steps=(install_greetd enable_keyd enable_power_profiles install_steam install_nvidia setup_voxtype
  setup_calendar_timer setup_syncthing setup_snapper)

failures=0
for step in "${optional_steps[@]}"; do
  calls=$(grep -nE "(^|[[:space:];])${step}([[:space:];]|$)" "$install_sh" | grep -vE "^[0-9]+:[[:space:]]*#")
  if [[ -z $calls ]]; then
    echo "FAIL: $step is never called in install.sh"
    failures=$((failures + 1))
    continue
  fi
  while IFS= read -r line; do
    if [[ $line != *"|| warn "* ]]; then
      echo "FAIL: unguarded optional step: $line"
      failures=$((failures + 1))
    fi
  done <<<"$calls"
done

if [[ $failures -ne 0 ]]; then
  echo "$failures optional step call(s) without || warn"
  exit 1
fi
echo "ok: all optional steps guarded"
