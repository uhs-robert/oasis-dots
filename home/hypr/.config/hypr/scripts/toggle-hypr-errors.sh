#!/usr/bin/env bash
# hypr/.config/hypr/scripts/toggle-hypr-errors.sh
# Toggles Hyprland's config error banner. Hiding lasts until the next successful config reload.

# Hyprland forgets its config errors on every `hyprctl eval`, and a banner put back with `seterror` is not in
# `configerrors` either, so the hidden text lives here until hyprland.lua deletes it on the next config load.
saved_errors="${XDG_RUNTIME_DIR:-/tmp}/hypr-hidden-errors"

# Errors Hyprland holds now (a fresh load, or a failed reload while hidden) replace the saved ones.
current_errors=$(hyprctl configerrors | sed '/^[[:space:]]*$/d')
[[ -n $current_errors ]] && printf '%s\n' "$current_errors" >"$saved_errors"

if hyprctl getoption debug:suppress_errors | grep -q 'bool: false'; then
  hyprctl eval 'hl.config({ debug = { suppress_errors = true } })' >/dev/null
  hyprctl seterror disable >/dev/null
  notify-send --transient -a "Hypr errors" -i dialog-error "Hypr errors hidden" "Config errors stay hidden until the next successful reload."
else
  hyprctl eval 'hl.config({ debug = { suppress_errors = false } })' >/dev/null
  if [[ -s $saved_errors ]]; then
    hyprctl seterror 'rgba(ff5555ff)' "$(cat "$saved_errors")" >/dev/null
  fi
  notify-send --transient -a "Hypr errors" -i dialog-error "Hypr errors shown" "Config errors show in the banner."
fi
