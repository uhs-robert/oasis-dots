#!/bin/sh
set -eu

# Keeps lock/skins/index.json in step with the skin files, audio importers and the greeter's import limits.
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
qs_dir="$repo_dir/home/quickshell/.config/quickshell"
skins_dir="$qs_dir/lock/skins"
index="$skins_dir/index.json"

if ! command -v jq >/dev/null 2>&1; then
  echo 'skip: lock skin check needs jq'
  exit 0
fi

status=0

if ! jq -e 'type == "object"' "$index" >/dev/null 2>&1; then
  echo "lock skins: $index is missing or not a JSON object" >&2
  exit 1
fi

files=$(
  for f in "$skins_dir"/*.qml; do
    basename "$f" .qml | tr '[:upper:]' '[:lower:]'
  done | sort
)
keys=$(jq -r 'keys[]' "$index" | sort)
if [ "$files" != "$keys" ]; then
  echo 'lock skins: index.json keys differ from lock/skins/*.qml:' >&2
  echo '--- files:' >&2
  printf '%s\n' "$files" >&2
  echo '--- index.json:' >&2
  printf '%s\n' "$keys" >&2
  status=1
fi

for skin in $(jq -r 'to_entries[] | select(.value.audio) | .key' "$index"); do
  if [ ! -f "$qs_dir/scripts/$skin-audio" ]; then
    echo "lock skins: $skin has audio but scripts/$skin-audio is missing" >&2
    status=1
  fi
done

for importer in "$qs_dir"/scripts/*-audio; do
  skin=$(basename "$importer" -audio)
  if ! jq -e --arg s "$skin" '.[$s].audio == true' "$index" >/dev/null; then
    echo "lock skins: scripts/$skin-audio exists but index.json does not mark $skin as audio" >&2
    status=1
  fi
done

if ! jq -e 'all(.[]; (.lock_only | not) or (.label | type == "string"))' "$index" >/dev/null; then
  echo 'lock skins: every lock_only skin in index.json needs a label' >&2
  status=1
fi

if bad=$(grep -rnE '^[[:space:]]*import[[:space:]]+"[^"]*(components|services)' "$skins_dir" --include='*.qml'); then
  echo 'lock skins: a skin imports components/ or services/, which the greeter does not stage:' >&2
  printf '%s\n' "$bad" >&2
  status=1
fi

exit "$status"
