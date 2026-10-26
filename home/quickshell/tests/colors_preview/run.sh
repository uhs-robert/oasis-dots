#!/usr/bin/env bash
# The colors-preview check step: with the Palette list open in a tall Colors pane, the list and the preview card must
# not overlap (#1293). Runs shell.qml against a copy of the Quickshell tree in a headless qs.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -rL "$here/../../.config/quickshell" "$tmp/cfg"
cp "$here/shell.qml" "$tmp/cfg/shell.qml"
mkdir -m 700 "$tmp/run" "$tmp/home"
out="$(env -i PATH="$PATH" HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/run" QT_QPA_PLATFORM=offscreen RESULT="$tmp/result" timeout 60 qs -p "$tmp/cfg" 2>&1)" || true
if [[ ! -s "$tmp/result" ]]; then
    echo "colors-preview: no result"
    echo "$out" | tail -30
    exit 1
fi
cat "$tmp/result"
if grep -q "^FAIL" "$tmp/result"; then exit 1; fi
