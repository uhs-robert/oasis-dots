# shellcheck shell=bash
# Sourced by ship-batch.sh. A long-lived shell's HYPRLAND_INSTANCE_SIGNATURE goes stale when
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

# The lookup is hypr-live (--owner: never the nested instance inside a shadow). It is found by repo path, not PATH,
# because ship-batch can run before the restow that puts it on PATH. Callers export the owner's runtime dir alongside the
# signature, since hyprctl looks its socket up under $XDG_RUNTIME_DIR/hypr/<signature>.
hypr_live_bin="$(dirname "${BASH_SOURCE[0]}")/../../../home/hypr/.local/bin/hypr-live"

# Prints the newest live instance signature whose hyprctl answers `$1` (default version), and fails when none does.
find_live_hypr_signature() {
  "$hypr_live_bin" --owner --probe "${1:-version}" 2>/dev/null
}
