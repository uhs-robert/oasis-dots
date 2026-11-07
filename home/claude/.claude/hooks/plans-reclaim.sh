#!/usr/bin/env bash
# SessionStart (startup, resume): a resumed session keeps its session id but gets a new pid, so the plans tools take
# its docs for dead. `plans reclaim` reads the hook input on stdin and points this session's docs at its new pid.
# The hook stays silent and always exits 0: its stdout reaches the model, and a failure shows at every start.
plans="$HOME/.local/bin/plans"
[[ -x $plans ]] || exit 0
"$plans" reclaim >/dev/null 2>&1
exit 0
