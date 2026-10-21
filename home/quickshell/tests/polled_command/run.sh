#!/usr/bin/env bash
# The polled-command check: settle-once and drain-grace tests for core/PolledCommand.qml in a headless qs (see run.py).
set -euo pipefail
exec python3 -B -I "$(dirname "${BASH_SOURCE[0]}")/run.py" "$@"
