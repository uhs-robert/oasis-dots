# shellcheck shell=bash
# shellcheck disable=SC2154 # fixtures_dir comes from the sourcing script
# The fixture desktop run-phrases.sh and bench.sh route against, sourced before they enter the sandbox: windows (Firefox,
# Slack and kitty), binds, monitors, workspaces, audio devices, the text OCR reads, agents, timers, tmux and launcher
# sessions, and installed apps from the fixtures' desktop entries alone. No private integration is loaded. Needs
# $fixtures_dir.
SANDBOX_CLIENTS_JSON=$(cat "$fixtures_dir/clients.json")
SANDBOX_ACTIVEWINDOW_JSON=$(jq -c '.[] | select(.focusHistoryID == 0)' <<<"$SANDBOX_CLIENTS_JSON")
SANDBOX_MONITORS_JSON=$(cat "$fixtures_dir/monitors.json")
SANDBOX_ACTIVEWORKSPACE_JSON=$(jq -c '.[] | select(.focused) | .activeWorkspace' <<<"$SANDBOX_MONITORS_JSON")
SANDBOX_BINDS_JSON=$(cat "$fixtures_dir/binds.json")
SANDBOX_WORKSPACES_JSON=$(cat "$fixtures_dir/workspaces.json")
SANDBOX_PW_DUMP_JSON=$(cat "$fixtures_dir/pw-dump.json")
SANDBOX_TESSERACT_TSV=$(cat "$fixtures_dir/ocr.tsv")
SANDBOX_AGENTS_JSON='[]'
SANDBOX_TIMERS_JSON='[]'
SANDBOX_TMUX_SESSIONS='dotfiles'
SANDBOX_LAUNCHER_SESSIONS=$'work\n🌐 Browsing'
export SANDBOX_CLIENTS_JSON SANDBOX_ACTIVEWINDOW_JSON SANDBOX_ACTIVEWORKSPACE_JSON SANDBOX_MONITORS_JSON \
  SANDBOX_BINDS_JSON SANDBOX_WORKSPACES_JSON SANDBOX_PW_DUMP_JSON SANDBOX_TESSERACT_TSV SANDBOX_AGENTS_JSON SANDBOX_TIMERS_JSON SANDBOX_TMUX_SESSIONS SANDBOX_LAUNCHER_SESSIONS
export XDG_DATA_HOME="$fixtures_dir" XDG_DATA_DIRS="$fixtures_dir"
unset VOXCMD_EXTRA_INTEGRATIONS
