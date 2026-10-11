# shellcheck shell=bash disable=SC2034,SC2016
# Screen brightness, power profile, do not disturb and auto-lock, through the same scripts and bar IPC the keybinds
# use, so the OSD and the bar stay in sync. Format: ~/.config/voxcmd/README.md

name="System"
confirm=0

hypr_scripts="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"

# Tried in order against the normalized transcript ("set brightness to 40%" arrives as "set brightness to 40").
verbs=(
  "brightness_max   (set )?(the )?(screen )?brightness( to)? (max|maximum|full)|(max|maximum|full) brightness"
  "brightness_min   (set )?(the )?(screen )?brightness( to)? (min|minimum|lowest)|(min|minimum|lowest) brightness"
  "brightness_up    brighter|(increase|raise) (the )?(screen )?brightness|(turn )?(the )?(screen )?brightness up( by {number}( percent)?)?"
  "brightness_down  dimmer|darker|(decrease|lower) (the )?(screen )?brightness|(turn )?(the )?(screen )?brightness down( by {number}( percent)?)?"
  "brightness_set   (set )?(the )?(screen )?brightness( to| at)? {number}( percent)?"
  "power_saver      ((switch|change) to |use |enable |turn on )?(the )?(power|battery) sav(er|ing)( mode)?( on)?|low power mode"
  "balanced         ((switch|change) to |use )?(the )?balanced( power)?( mode| profile)?"
  "performance      ((switch|change) to |use |enable |turn on )?(the )?(high )?performance( mode| profile)?( on)?"
  "profile          ((set|switch|change) )?(the )?power (profile|mode) to {target}"
  "dnd_off          ((turn|switch) off |disable |end )(the )?(do not disturb|dnd)( mode)?|(do not disturb|dnd)( mode)? off|(unsilence|unmute|enable) (the )?notifications|(turn |switch )?(the )?notifications (back )?on"
  "dnd_on           ((turn|switch) on |enable |start )?(the )?(do not disturb|dnd)( mode)?( on)?|(silence|mute|disable) (the )?notifications|(turn |switch )?(the )?notifications off"
  "autolock_on      caffeine( mode)? off|(turn |switch )off (the )?caffeine( mode)?|(enable|turn on|start) (the )?(auto ?lock|idle lock)|auto ?lock on|let (the )?(screen|computer) (sleep|lock)"
  "autolock_off     keep (the )?(screen|display|computer|system) (awake|on)|stay awake|((turn|switch) on )?caffeine( mode)?( on)?|(disable|turn off) (the )?(auto ?lock|idle lock)|auto ?lock off|dont (auto ?)?lock( the screen)?"
)

examples=(
  "set brightness to <number>"
  "brightness up"
  "power saver mode"
  "performance mode"
  "do not disturb on"
  "do not disturb off"
  "keep the screen awake"
)

declare -A actions=(
  [brightness_max]='set_brightness 100%'
  [brightness_min]='set_brightness 1%'
  [brightness_up]='set_brightness "${target:-10}%+"'
  [brightness_down]='set_brightness "${target:-10}%-"'
  [brightness_set]='set_brightness "$(clamp_percent "$target")%"'
  [power_saver]='set_power_profile power-saver'
  [balanced]='set_power_profile balanced'
  [performance]='set_power_profile performance'
  [profile]='set_power_profile "$id"'
  [dnd_on]='set_dnd true'
  [dnd_off]='set_dnd false'
  [autolock_on]='set_autolock on'
  [autolock_off]='set_autolock off'
)

# Profiles for "set power profile to <name>", the ones this machine offers; performance needs hardware support.
candidates() {
  case "$1" in
  profile)
    local profiles
    profiles=$(powerprofilesctl list 2>/dev/null | sed -n 's/^[* ] *\([a-z-]*\):$/\1/p')
    [ -n "$profiles" ] || profiles=$'power-saver\nbalanced\nperformance'
    jq -R -s -c 'split("\n") | map(select(. != "") | {id: ., label: gsub("-"; " ")})' <<<"$profiles"
    ;;
  esac
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
