#!/bin/sh
set -eu

# Keeps the generated keybind table in docs/keybinds.md in step with the keymaps.
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)

python3 -B "$repo_dir/lib/docs/gen-keybinds" --check
