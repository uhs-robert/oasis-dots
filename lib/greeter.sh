#!/usr/bin/env bash
# Stages and installs the Quickshell greeter (/etc/greetd/quickshell) with the lock skins, theme, fonts and the user's lock style.

GREETER_DEST=/etc/greetd/quickshell
# Data only (greeter.json, theme.json), owned by the installing user and readable by group greeter; the bar keeps it current.
GREETER_DATA=/var/lib/qs-greeter

# Builds the greeter tree in $1 from the repo at $2 plus this user's theme and lock style; prints the resolved skin.
# $3 is a Quickshell config dir to stage skins and theme from instead of the repo's, e.g. a worktree's.
stage_greeter() {
  local dest=$1 repo=$2
  local qs="${3:-$repo/home/quickshell/.config/quickshell}"
  local live="${3:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell}"
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"

  rm -rf "$dest"
  mkdir -p "$dest/lock/skins" "$dest/theme" "$dest/fonts"
  cp -r "$repo/system/etc/greetd/quickshell/." "$dest/" || return 1
  cp -r "$qs/lock/skins/." "$dest/lock/skins/" || return 1
  cp "$qs/lock/Tints.js" "$dest/lock/" || return 1
  [[ -f "$qs/VERSION" ]] && cp "$qs/VERSION" "$dest/"
  local skin audio_dir audio_skins
  # Skins whose imported audio lives in $XDG_DATA_HOME/quickshell/<skin>-audio.
  audio_skins=$(jq -r 'to_entries[] | select(.value.audio) | .key' "$qs/lock/skins/index.json") || return 1
  mapfile -t audio_skins <<<"$audio_skins"
  for skin in "${audio_skins[@]}"; do
    audio_dir="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/$skin-audio"
    if [[ -d "$audio_dir" && -n "$(ls -A "$audio_dir")" ]]; then
      rm -rf "${dest:?}/lock/skins/$skin/audio"
      mkdir -p "$dest/lock/skins/$skin/audio"
      cp -rL "$audio_dir/." "$dest/lock/skins/$skin/audio/"
    fi
  done
  local frames_dir="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/goldeneye-frames"
  if (($(cat "$frames_dir/count.txt" 2>/dev/null || echo 0) > 0)); then
    rm -rf "${dest:?}/lock/skins/goldeneye/frames"
    mkdir -p "$dest/lock/skins/goldeneye/frames"
    cp -rL "$frames_dir/." "$dest/lock/skins/goldeneye/frames/"
  fi
  cp "$qs/theme/Theme.qml" "$qs/theme/Style.qml" "$qs/theme/StyleSchema.js" "$qs/theme/Paths.qml" "$qs/theme/Watch.js" "$dest/theme/" || return 1
  cp -r "$qs/theme/styles" "$dest/theme/" || return 1
  if [[ -n ${3:-} && -f "$3/theme/theme.json" ]]; then
    cp "$3/theme/theme.json" "$dest/theme/" || return 1
  elif jq -e 'type == "object"' "$state_dir/theme.json" &>/dev/null; then
    cp "$state_dir/theme.json" "$dest/theme/"
  elif [[ -f "$live/theme/theme.json" ]]; then
    cp "$live/theme/theme.json" "$dest/theme/"
  fi
  cp "$qs"/fonts/*.ttf "$qs"/fonts/OFL-*.txt "$dest/fonts/" || return 1

  local style=oasis lock=follow tint=primary music=on session=Hyprland watch=Theme
  local login_screen=follow login_tint=follow login_music=follow
  [[ -f "$state_dir/style.json" ]] && style=$(jq -r '.style // "oasis"' "$state_dir/style.json")
  [[ -f "$state_dir/theme_options.json" ]] && watch=$(jq -r '.goldeneye.watch_colors // "Theme"' "$state_dir/theme_options.json")
  if [[ -f "$state_dir/lock.json" ]]; then
    lock=$(jq -r '.lock_style // "follow"' "$state_dir/lock.json")
    tint=$(jq -r '.lock_tint // "primary"' "$state_dir/lock.json")
    music=$(jq -r 'if .lock_music == false then "off" else "on" end' "$state_dir/lock.json")
  fi
  if [[ -f "$state_dir/greeter.json" ]]; then
    login_screen=$(jq -r '.screen // "follow"' "$state_dir/greeter.json")
    login_tint=$(jq -r '.tint // "follow"' "$state_dir/greeter.json")
    login_music=$(jq -r '.music // "follow"' "$state_dir/greeter.json")
    session=$(jq -r '.session // "Hyprland"' "$state_dir/greeter.json")
  fi
  [[ "$login_screen" != "follow" ]] && lock=$login_screen
  [[ "$login_tint" != "follow" ]] && tint=$login_tint
  [[ "$login_music" != "follow" ]] && music=$login_music
  [[ "$lock" == "follow" ]] && lock=$style
  local file="${lock^}.qml"
  [[ "$lock" != "simple" && -f "$dest/lock/skins/$file" ]] || lock=simple

  jq -n --arg user "${GREETER_USER:-$USER}" --arg lock "$lock" --arg tint "$tint" --arg music "$music" --arg session "$session" --arg watch "$watch" \
    '{user: $user, lock_style: $lock, lock_tint: $tint, lock_music: $music, watch_colors: $watch, session: $session}' >"$dest/greeter.json"
  printf '%s\n' "$lock"
}

# The commands that install a staged tree at $1 and the wrapper and greetd Hyprland config from the repo at $2, then seed the data dir.
greeter_install_cmds() {
  local stage=$1 repo=$2
  local seed_theme=":"
  [[ -f "$stage/theme/theme.json" ]] && seed_theme="install -m 640 '$stage/theme/theme.json' '$GREETER_DATA/theme.json'"
  printf '%s\n' \
    "[ ! -f /etc/greetd/hyprland.lua ] || [ -f /etc/greetd/hyprland.lua.bak ] || sudo cp /etc/greetd/hyprland.lua /etc/greetd/hyprland.lua.bak" \
    "sudo rsync -rlpt --delete --chown=root:root --chmod=D755,F644 '$stage/' '$GREETER_DEST/'" \
    "sudo install -Dm755 '$repo/system/usr/local/bin/qs-greeter' /usr/local/bin/qs-greeter" \
    "sudo install -Dm644 '$repo/system/etc/greetd/hyprland.lua' /etc/greetd/hyprland.lua" \
    "printf '%s\\n' '${GREETER_USER:-$USER}' | sudo tee /etc/greetd/admin_user >/dev/null" \
    "sudo install -d -m 2750 -o '$USER' -g greeter '$GREETER_DATA'" \
    "install -m 640 '$stage/greeter.json' '$GREETER_DATA/greeter.json'" \
    "$seed_theme" \
    "[ ! -f '$HOME/.face' ] || install -D -m 640 '$HOME/.face' '$GREETER_DATA/faces/$USER'"
}
