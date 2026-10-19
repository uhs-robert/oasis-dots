#!/usr/bin/env bash
# The output-sink ducker: voxtype-duck against a fake wpctl and a fake voxtype, in a temp runtime dir. The audio server
# and the real voxtype are never reached.
#
#   home/voxtype/tests/run-duck.sh
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=../../../lib/check/lock.sh
. "$tests_dir/../../../lib/check/lock.sh"
check_lock_gate "voxtype ${0##*/}" "$0" "$@"
python3 -I -B "$tests_dir/duck_test.py"
