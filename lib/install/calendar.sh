#!/usr/bin/env bash
# Enables the calendar sync timer and offers the one-time calendar-sync setup.

# The calendar package is optional and ships the units, so this does nothing, silently, unless it was stowed.
setup_calendar_timer() {
  [[ -e "$HOME/.config/systemd/user/calendar-sync.timer" ]] || return 0
  if systemctl --user show-environment &>/dev/null; then
    systemctl --user daemon-reload
    systemctl --user is-enabled calendar-sync.timer &>/dev/null || systemctl --user enable --now calendar-sync.timer
  else
    warn "User systemd not available, enable the calendar timer after login: systemctl --user enable --now calendar-sync.timer"
  fi
  offer_calendar_setup
}

# The timer is silent until configured, so it is enabled either way; this only decides whether to ask now.
offer_calendar_setup() {
  local calendar_sync="$HOME/.local/bin/calendar-sync"
  [[ -x "$calendar_sync" ]] || return 0
  local check_status=0
  "$calendar_sync" setup --check &>/dev/null || check_status=$?
  if [[ $check_status -eq 0 ]]; then
    info "Calendar already connected"
  elif [[ $check_status -eq 3 ]]; then
    info "rbw is locked; run calendar-sync setup after unlocking"
  elif [[ $check_status -eq 4 ]]; then
    info "The keyring is locked; run calendar-sync setup after unlocking"
  elif [[ "${OPT_YES:-0}" -eq 0 && -t 0 && -t 1 ]] && confirm "Connect your Google Calendar now?"; then
    "$calendar_sync" setup || warn "Calendar setup did not finish; run calendar-sync setup to try again"
  else
    info "Run calendar-sync setup to connect your calendar later"
  fi
}
