# shellcheck shell=bash
# Sourced by restart-qs-after-git.sh and ship-batch.sh. A long-lived shell's HYPRLAND_INSTANCE_SIGNATURE goes stale when
# the owner logs in again, so these find the owner's live Hyprland instead of trusting the environment.

# The owner's runtime directory. A shell started inside a shadow (see the shadow skill) has XDG_RUNTIME_DIR pointing at
# /tmp/shadow-<uid>-<name>, whose nested Hyprland would answer every probe; the owner's session is never there.
# OWNER_RUNTIME_DIR exists for the tests.
in_shadow_runtime() { [[ ${XDG_RUNTIME_DIR:-} == /tmp/shadow-* ]]; }

owner_runtime_dir() {
  if in_shadow_runtime; then
    echo "${OWNER_RUNTIME_DIR:-/run/user/$UID}"
  else
    echo "${XDG_RUNTIME_DIR:-/run/user/$UID}"
  fi
}

# hyprctl looks its socket up under $XDG_RUNTIME_DIR/hypr/<signature>, so probes and every later hyprctl call must run
# with the owner's runtime dir, which callers export alongside the signature.
# Prints the newest instance signature whose hyprctl answers `$1` (default version), and fails when none does. Newest by
# its .socket.sock, not the directory: a directory's mtime moves whenever a child like .hyprpaper.sock is recreated.
find_live_hypr_signature() {
  local probe=${1:-version} socket instance owner_dir
  owner_dir=$(owner_runtime_dir)
  while read -r socket; do
    instance=$(basename "$(dirname "$socket")")
    if XDG_RUNTIME_DIR=$owner_dir HYPRLAND_INSTANCE_SIGNATURE=$instance timeout 3 hyprctl "$probe" >/dev/null 2>&1; then
      echo "$instance"
      return 0
    fi
  done < <(ls -1t "$owner_dir"/hypr/*/.socket.sock 2>/dev/null)
  return 1
}
