# shellcheck shell=bash
# Hook library of system.toml: sourced before every hook and action of the integration.

hypr_scripts="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"

# id<TAB>label per profile: the profile name, then the same with spaces for dashes.
profile_candidates() {
  local profiles
  profiles=$(powerprofilesctl list 2>/dev/null | sed -n 's/^[* ] *\([a-z-]*\):$/\1/p')
  [ -n "$profiles" ] || profiles=$'power-saver\nbalanced\nperformance'
  awk 'NF { label = $0; gsub("-", " ", label); print $0 "\t" label }' <<<"$profiles"
}

# Never 0%: the floor the brightness keys and the bar's slider keep, so a misheard number cannot black out the screen.
clamp_percent() {
  local percent=$((10#$1))
  ((percent < 1)) && percent=1
  ((percent > 100)) && percent=100
  echo "$percent"
}

# Like the brightness keys: brightnessctl, then the bar re-reads the backlight and shows its OSD.
set_brightness() {
  brightnessctl -n1 set "$1" >/dev/null || return 1
  "$hypr_scripts/qs-ipc" call brightness refresh >/dev/null 2>&1 || true
  echo "brightness $(brightnessctl -m | cut -d, -f4)"
}

# The bar's UPower service follows the daemon, so its battery popup updates on its own. power.sh still applies the
# profile chosen in Settings for AC or battery on the next power-source change.
set_power_profile() {
  powerprofilesctl set "$1" || return 1
  echo "power profile $(powerprofilesctl get)"
}

# The Quickshell bar is the notification daemon; its IPC only toggles, so read the state first.
set_dnd() {
  local current
  current=$("$hypr_scripts/qs-ipc" call notifications get_dnd) || return 1
  [ "$current" = "$1" ] || "$hypr_scripts/qs-ipc" call notifications toggle_dnd || return 1
  if [ "$1" = true ]; then echo "do not disturb on"; else echo "do not disturb off"; fi
}

# Auto-lock is hypridle running; toggle-autolock.sh starts or stops it the way the System submap key does.
set_autolock() {
  local running=off
  pgrep -x hypridle >/dev/null && running=on
  if [ "$running" = "$1" ]; then
    echo "auto-lock already $1"
    return
  fi
  "$hypr_scripts/toggle-autolock.sh" || return 1
  echo "auto-lock $1"
}
