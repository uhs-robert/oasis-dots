#!/usr/bin/env bash
# The bar-editor check step: BarSettings storage and the editor's lifecycle in a headless qs (see run.py).
set -euo pipefail
exec python3 -B -I "$(dirname "${BASH_SOURCE[0]}")/run.py" "$@"
