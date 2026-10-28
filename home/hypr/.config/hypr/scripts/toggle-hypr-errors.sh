#!/usr/bin/env bash
# hypr/.config/hypr/scripts/toggle-hypr-errors.sh
# Toggles Hyprland's config error banner. The choice lasts until the next config reload.

if hyprctl getoption debug:suppress_errors | grep -q 'bool: false'; then
  hyprctl eval 'hl.config({ debug = { suppress_errors = true } })' >/dev/null
  # suppress_errors covers config errors only; this clears a banner set with `hyprctl seterror`.
  hyprctl seterror disable >/dev/null
  notify-send --transient -a "Hypr errors" -i dialog-error "Hypr errors hidden" "Config errors will not show until the next reload."
else
  hyprctl eval 'hl.config({ debug = { suppress_errors = false } })' >/dev/null
  notify-send --transient -a "Hypr errors" -i dialog-error "Hypr errors shown" "Config errors show in the banner."
fi
