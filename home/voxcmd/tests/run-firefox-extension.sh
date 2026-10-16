#!/usr/bin/env bash
# Tests for voxcmd's Firefox extension and its native-messaging host: the host's framing and routing against a fake
# extension on pipes, and the extension's background script against a mocked `browser`. Run from anywhere.
# The firefox-tab side (live tabs, activation, fallback) is in run.sh's "firefox live" section.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=../../../lib/check/lock.sh
. "$here/../../../lib/check/lock.sh"
check_lock_gate "voxcmd ${0##*/}" "$0" "$@"
status=0
PYTHONDONTWRITEBYTECODE=1 python3 -I "$here/firefox-host-test" || status=1
if command -v node >/dev/null 2>&1; then
  node "$here/firefox-background.test.js" || status=1
else
  echo "skip: node not installed, so the background script is not checked"
fi
exit "$status"
