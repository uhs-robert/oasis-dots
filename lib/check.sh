#!/bin/sh

# Runs the validation steps and reports all failures, rather than stopping at the first one.
#
#   lib/check.sh                  every step
#   lib/check.sh --changed <base> only the steps the files changed since <base> can affect
#
# The other options (--paths-from, --only, --plan), the environment, the step list, the pass records and the heavy-step
# slots are in lib/check/README.md; the steps and the paths that reach them are in lib/check/scopes.py.
#
# This file is scope "all" and part of every step's key, so any edit here, a comment too, reruns every step. Put
# documentation in lib/check/README.md.
#
# The runner is lib/check/runner.py; this shim works both as `sh lib/check.sh` and `lib/check.sh`.
exec python3 -B "$(dirname -- "$0")/check/runner.py" "$@"
