# shellcheck shell=bash
# shellcheck disable=SC2154 # fixtures_dir comes from the sourcing script
# The fixture windows, binds and desktop entries the run-*.sh suites share, sourced before and after they enter the sandbox so a wrapped and a bare run
# see the same desktop. Needs $fixtures_dir. run-phrases.sh and bench.sh source the fuller phrase-fixtures.sh instead.
SANDBOX_CLIENTS_JSON=$(cat "$fixtures_dir/clients.json")
SANDBOX_ACTIVEWINDOW_JSON=$(jq -c '.[] | select(.focusHistoryID == 0)' <<<"$SANDBOX_CLIENTS_JSON")
SANDBOX_BINDS_JSON=$(cat "$fixtures_dir/binds.json")
export SANDBOX_CLIENTS_JSON SANDBOX_ACTIVEWINDOW_JSON SANDBOX_BINDS_JSON
export XDG_DATA_HOME="$fixtures_dir" XDG_DATA_DIRS="$fixtures_dir"
unset VOXCMD_EXTRA_INTEGRATIONS
