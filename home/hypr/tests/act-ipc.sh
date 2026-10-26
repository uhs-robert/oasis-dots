#!/usr/bin/env bash
# Runs act_ipc.lua, the check that the keyless IPC actions send the right `qs-ipc call` line, then checks that every
# IPC target and function they name is declared by an IpcHandler in the Quickshell tree. It runs from a temp dir and
# fails if the repo's `git status` differs afterwards.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel) || exit 1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1

# Compared with the state before, not with empty: a checkout being edited is not clean, and a check run's is.
before=$(git -C "$repo" status --porcelain)
status=0
lua "$here/act_ipc.lua" || status=1

lua "$here/act_ipc.lua" --targets >"$work/targets.tsv" || status=1
[[ -s $work/targets.tsv ]] || {
  echo "FAIL no IPC actions were listed" >&2
  status=1
}
python3 -B -I - "$repo" "$work/targets.tsv" <<'PY' || status=1
import sys

repo, targets = sys.argv[1:3]
sys.path.insert(0, repo + "/lib/check/steps")
sys.dont_write_bytecode = True
import qml_ipc

handlers, _ = qml_ipc.declared(repo, qml_ipc.QML_DIRS)
bad = 0
for line in open(targets):
    id_, target, function = line.rstrip("\n").split("\t")
    handler = handlers.get(target)
    if handler is None or function not in handler.functions:
        print(f"FAIL {id_}: {target} {function} is not declared by an IpcHandler")
        bad += 1
sys.exit(1 if bad else 0)
PY

if [[ $(git -C "$repo" status --porcelain) != "$before" ]]; then
  echo "FAIL the test changed the repo" >&2
  status=1
fi
exit "$status"
