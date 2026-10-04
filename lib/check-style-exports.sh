#!/bin/sh
set -eu

# Keeps Style.qml's generated token exports in step with theme/StyleSchema.js.
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")

if ! command -v python3 >/dev/null 2>&1; then
  echo 'skip: style export check needs python3'
  exit 0
fi

python3 "$repo_dir/home/quickshell/.config/quickshell/scripts/gen-style-exports" --check
