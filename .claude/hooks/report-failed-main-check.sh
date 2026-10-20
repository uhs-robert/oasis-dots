#!/usr/bin/env bash
# SessionStart: when the last background check of main failed (ship-batch-main-check.result in the git common dir, written
# by .claude/skills/ship-batch/main-check.sh), prints one line naming the commit and the log so the session starts knowing
# main is red. Silent when the check passed, never ran, or this is not a repository.
set -u
common=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
result=$common/ship-batch-main-check.result
[[ -r $result ]] || exit 0
read -r status sha _ log <"$result" || exit 0
[[ $status == fail ]] || exit 0
main_check=$(cd "$(dirname "$0")/../skills/ship-batch" && pwd)/main-check.sh
echo "The check of main FAILED at ${sha:0:12}; log $log. Fix it before anything else ($main_check status for details)."
