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
  theme/MarkerTokens.js
  styles/index.js
  styles/IconSets.js
  # One entry per file, not styles/*/tokens.js: qmllint's greeter copy (lib/check/steps/qml.py) takes QML and JS entries literally.
  styles/crt/tokens.js
  styles/crt/icons.js
  styles/ff7/tokens.js
  styles/ff7/icons.js
  styles/gameboy/tokens.js
  styles/gameboy/icons.js
  styles/goldeneye/tokens.js
  styles/goldeneye/icons.js
  styles/halflife/tokens.js
  styles/halflife/icons.js
  styles/metroid/tokens.js
  styles/metroid/icons.js
  styles/modern/tokens.js
  styles/modern/icons.js
  styles/neovim/tokens.js
  styles/nes/tokens.js
  styles/nes/icons.js
  styles/oasis/tokens.js
  styles/oasis/icons.js
  styles/ps1/tokens.js
  styles/ps1/icons.js
  styles/ps2/tokens.js
  styles/ps2/icons.js
  styles/reticle/tokens.js
  styles/reticle/icons.js
  styles/snes/tokens.js
  styles/snes/icons.js
  styles/terminal/tokens.js
  styles/terminal/icons.js
  styles/tie/tokens.js
  styles/tie/icons.js
  styles/goldeneye/Watch.js
  styles/goldeneye/watch_tokens.js
  'assets/fonts/*.ttf'
  'assets/fonts/OFL-*.txt'
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
