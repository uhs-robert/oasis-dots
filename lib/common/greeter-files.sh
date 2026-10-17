#!/usr/bin/env bash
# The Quickshell files the login greeter stages, relative to the Quickshell config dir: the one list to edit when a greeter-staged file moves.
# A trailing / is a directory copied whole, a trailing ? an optional entry, and * a glob matched at stage time.
# Read by stage_greeter (lib/install/greeter.sh), lib/check/steps/qml.py, lib/check/steps/qml_paths.py, the greeter-sync check in the justfile and ship-batch.
GREETER_QS_FILES=(
  lock/skins/
  lock/Tints.js
  VERSION?
  theme/Theme.qml
  theme/Style.qml
  theme/StyleSchema.js
  core/Paths.qml
  theme/Watch.js
  theme/MarkerTokens.js
  theme/styles/
  theme/icon_sets/
  'fonts/*.ttf'
  'fonts/OFL-*.txt'
)

# Copies the GREETER_QS_FILES entries from the Quickshell config dir $1 into $2, each at the same relative path; fails on a missing required entry.
copy_greeter_qs_files() {
  local qs=$1 dest=$2 entry
  for entry in "${GREETER_QS_FILES[@]}"; do
    if [[ $entry == *'?' ]]; then
      [[ -e "$qs/${entry%'?'}" ]] || continue
      entry=${entry%'?'}
    fi
    # The glob entries stay unquoted so cp sees what they match; a glob matching nothing reaches cp literally and fails.
    # shellcheck disable=SC2086
    (cd "$qs" && cp -r --parents ${entry%/} "$dest/") || return 1
  done
}
