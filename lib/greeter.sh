#!/usr/bin/env bash
# Stages and installs the Quickshell greeter (/etc/greetd/quickshell) with the lock skins, theme, fonts and the user's lock style.

GREETER_DEST=/etc/greetd/quickshell

# Builds the greeter tree in $1 from the repo at $2 plus this user's theme and lock style; prints the resolved skin.
stage_greeter() {
  local dest=$1 repo=$2
  local qs="$repo/home/quickshell/.config/quickshell"
  local live="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
  local state="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/style.json"

  rm -rf "$dest"
  mkdir -p "$dest/lock/skins" "$dest/theme" "$dest/fonts"
  cp -r "$repo/system/etc/greetd/quickshell/." "$dest/"
  cp "$qs"/lock/skins/*.qml "$dest/lock/skins/"
  cp "$qs/lock/Tints.js" "$dest/lock/"
  cp "$qs/theme/Theme.qml" "$qs/theme/Style.qml" "$dest/theme/"
  [[ -f "$live/theme/theme.json" ]] && cp "$live/theme/theme.json" "$dest/theme/"
  cp "$qs"/fonts/*.ttf "$qs"/fonts/OFL-*.txt "$dest/fonts/"

  local style=oasis lock=follow tint=primary
  if [[ -f "$state" ]]; then
    style=$(jq -r '.style // "oasis"' "$state")
    lock=$(jq -r '.lock_style // "follow"' "$state")
    tint=$(jq -r '.lock_tint // "primary"' "$state")
  fi
  [[ "$lock" == "follow" ]] && lock=$style
  local file="${lock^}.qml"
  [[ "$lock" != "simple" && -f "$dest/lock/skins/$file" ]] || lock=simple

  jq -n --arg user "${GREETER_USER:-$USER}" --arg lock "$lock" --arg tint "$tint" \
    '{user: $user, lock_style: $lock, lock_tint: $tint, session: "Hyprland"}' >"$dest/greeter.json"
  printf '%s\n' "$lock"
}

# The commands that install a staged tree at $1 and the wrapper and greetd Hyprland config from the repo at $2.
greeter_install_cmds() {
  local stage=$1 repo=$2
  printf '%s\n' \
    "[ ! -f /etc/greetd/hyprland.lua ] || [ -f /etc/greetd/hyprland.lua.bak ] || sudo cp /etc/greetd/hyprland.lua /etc/greetd/hyprland.lua.bak" \
    "sudo rsync -rlpt --delete --chown=root:root --chmod=D755,F644 '$stage/' '$GREETER_DEST/'" \
    "sudo install -Dm755 '$repo/system/usr/local/bin/qs-greeter' /usr/local/bin/qs-greeter" \
    "sudo install -Dm644 '$repo/system/etc/greetd/hyprland.lua' /etc/greetd/hyprland.lua"
}
