#!/bin/sh
set -eu

# Keeps the generated tables in step with their sources: the keybind table in docs/keybinds.md and the IPC table in the Quickshell README.
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)

python3 -B "$repo_dir/lib/docs/gen-keybinds" --check
python3 -B "$repo_dir/lib/docs/gen-ipc" --check
