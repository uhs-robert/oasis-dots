#!/usr/bin/env bash
# hypr/.config/hypr/scripts/toggle-hypr-errors.sh
# Toggles Hyprland's config error banner. Hiding lasts until the next successful config reload.

# Hyprland forgets its config errors on every `hyprctl eval`, so the text is saved here to put back on show.
saved_errors="${XDG_RUNTIME_DIR:-/tmp}/hypr-hidden-errors"

if hyprctl getoption debug:suppress_errors | grep -q 'bool: false'; then
  hyprctl configerrors | sed '/^[[:space:]]*$/d' >"$saved_errors"
  hyprctl eval 'hl.config({ debug = { suppress_errors = true } })' >/dev/null
  hyprctl seterror disable >/dev/null
  notify-send --transient -a "Hypr errors" -i dialog-error "Hypr errors hidden" "Config errors stay hidden until the next successful reload."
else
  hyprctl eval 'hl.config({ debug = { suppress_errors = false } })' >/dev/null
  if [[ -s $saved_errors ]]; then
    hyprctl seterror 'rgba(ff5555ff)' "$(cat "$saved_errors")" >/dev/null
  fi
  rm -f "$saved_errors"
  notify-send --transient -a "Hypr errors" -i dialog-error "Hypr errors shown" "Config errors show in the banner."
fi
