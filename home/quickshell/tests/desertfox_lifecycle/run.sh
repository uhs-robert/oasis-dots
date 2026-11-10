#!/usr/bin/env bash
# The DesertFox state lifecycle check: features/desertfox in a headless qs (see run.py).
set -euo pipefail
exec python3 -B -I "$(dirname "${BASH_SOURCE[0]}")/run.py" "$@"
