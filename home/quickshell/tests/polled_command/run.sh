#!/usr/bin/env bash
# The polled-command check: how Quickshell ends stdout for core/PolledCommand.qml in a headless qs (see run.py).
set -euo pipefail
exec python3 -B -I "$(dirname "${BASH_SOURCE[0]}")/run.py" "$@"
