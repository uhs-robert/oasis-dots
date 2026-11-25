#!/bin/bash
# Tests lib/check/steps/settings-skins.sh on scratch skin folders through SETTINGS_SKINS_QS_DIR, so no real file changes.
set -u
unset SETTINGS_SKINS_QS_DIR

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
step=$repo_dir/lib/check/steps/settings-skins.sh
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

failures=0
# A scratch tree with the nes and goldeneye styles and a Default skin holding every slot.
new_tree() {
  rm -rf "$scratch/qs"
  mkdir -p "$scratch/qs/styles" "$scratch/qs/features/settings/skins"
  printf '        "nes": style(Nes),\n        "goldeneye": style(Goldeneye, x),\n' >"$scratch/qs/styles/index.js"
  printf 'QtObject {\n    readonly property Component nav_item: Component { Item {\n        property bool selected: false\n    } }\n    readonly property Component backdrop: Component { Item {} }\n    readonly property Component panel_art: Component { Item {} }\n}\n' >"$scratch/qs/features/settings/skins/Default.qml"
}
# run_case <name> <expected exit 0|1> <skin file> <skin text>
run_case() {
  new_tree
  printf '%b' "$4" >"$scratch/qs/features/settings/skins/$3"
  SETTINGS_SKINS_QS_DIR=$scratch/qs bash "$step" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" = "$2" ]; then printf 'ok   %s\n' "$1"; else
    printf 'FAIL %s (exit %s, wanted %s)\n' "$1" "$rc" "$2" >&2
    failures=$((failures + 1))
  fi
}

nav='QtObject {\n    readonly property Component nav_item: Component { Item {\n        property bool selected: false\n    } }\n}\n'
run_case 'a clean skin passes' 0 Goldeneye.qml "$nav"
run_case 'a lowercase file name fails' 1 nes.qml "$nav"
run_case 'a mixed-case file name fails' 1 GoldenEye.qml "$nav"
run_case 'an unknown style fails' 1 Bogus.qml "$nav"
run_case 'a nav_item without readonly and without selected fails' 1 Nes.qml 'QtObject {\n    property Component nav_item: Component { Item {} }\n}\n'
run_case 'a nav_item without readonly but with selected passes' 0 Nes.qml 'QtObject {\n    property Component nav_item: Component { Item {\n        property bool selected: false\n    } }\n}\n'
run_case 'Keys. in a comment passes' 0 Nes.qml "// no Keys.onPressed here\n$nav"
run_case 'a name ending in Keys passes' 0 Nes.qml "$nav"'Item { property var x: MyKeys.y }\n'
run_case 'forceActiveFocus fails' 1 Nes.qml "$nav"'Item { Component.onCompleted: forceActiveFocus() }\n'
run_case 'Keys.onPressed fails' 1 Nes.qml "$nav"'Item { Keys.onPressed: {} }\n'

[ "$failures" = 0 ]
