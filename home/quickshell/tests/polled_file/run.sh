#!/usr/bin/env bash
# The polled-file check: core/PolledFile.qml in a headless qs (see run.py).
set -euo pipefail
exec python3 -B -I "$(dirname "${BASH_SOURCE[0]}")/run.py" "$@"
