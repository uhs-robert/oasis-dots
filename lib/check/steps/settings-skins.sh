#!/usr/bin/env bash
set -eu

# Keeps features/settings/skins/ in step with styles/index.js and the skin contract: a skin file per known style, every
# slot in Default, and no focus or key handling in a skin (SettingsPopup owns them). What a skin may import is checked by qml_paths.py.
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
qs_dir="${SETTINGS_SKINS_QS_DIR:-$repo_dir/home/quickshell/.config/quickshell}"
skins_dir="$qs_dir/features/settings/skins"
index="$qs_dir/styles/index.js"
slots='nav_item backdrop panel_art'

status=0

if [ ! -f "$skins_dir/Default.qml" ]; then
  echo "settings skins: $skins_dir/Default.qml is missing" >&2
  exit 1
fi

styles=$(sed -n 's/^ *"\([a-z0-9_]*\)": style(.*/\1/p' "$index")
if [ -z "$styles" ]; then
  echo "settings skins: no styles found in $index" >&2
  exit 1
fi

# The text of one slot: from its declaration to the next slot declaration or the end of the file.
slot_body() {
  awk -v slot="$2" '
    /readonly property Component [a-z_]+:/ { in_slot = ($0 ~ ("Component " slot ":")) }
    in_slot { print }
  ' "$1"
}

for slot in $slots; do
  if ! grep -q "readonly property Component $slot:" "$skins_dir/Default.qml"; then
    echo "settings skins: Default.qml does not define the $slot slot" >&2
    status=1
  fi
done

for file in "$skins_dir"/*.qml; do
  name=$(basename "$file" .qml)
  lower=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
  rel="features/settings/skins/$name.qml"
  if [ "$name" != Default ] && ! printf '%s\n' "$styles" | grep -qx "$lower"; then
    echo "settings skins: $rel matches no style in styles/index.js" >&2
    status=1
  fi
  if grep -nE 'Keys\.|focus: *true|forceActiveFocus' "$file" >&2; then
    echo "settings skins: $rel takes focus or keys; SettingsPopup owns both" >&2
    status=1
  fi
  # reveal_selected finds the nav row through its `selected` property.
  if grep -q 'readonly property Component nav_item:' "$file" &&
    ! slot_body "$file" nav_item | grep -qE '^ *(readonly )?(property +[a-z]+ +)?selected *:'; then
    echo "settings skins: the nav_item of $rel does not declare selected, so scroll-to-selection breaks" >&2
    status=1
  fi
done

exit "$status"
