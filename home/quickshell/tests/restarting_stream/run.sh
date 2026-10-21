#!/usr/bin/env bash
# The restarting-stream check: the lifecycle of core/RestartingStream.qml in a headless qs (see run.py).
set -euo pipefail
exec python3 -B -I "$(dirname "${BASH_SOURCE[0]}")/run.py" "$@"
