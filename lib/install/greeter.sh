#!/usr/bin/env bash
# Stages and installs the Quickshell greeter (/etc/greetd/quickshell) with the lock skins, theme, fonts and the user's lock style,
# and lets the greetd login unlock the GNOME keyring.

# shellcheck source=lib/common/greeter-files.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common/greeter-files.sh"

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
  mkdir -p "$dest"
  cp -r "$repo/system/etc/greetd/quickshell/." "$dest/" || return 1
  copy_greeter_qs_files "$qs" "$dest" || return 1
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
  if [[ -n ${3:-} && -f "$3/theme/theme.json" ]]; then
    cp "$3/theme/theme.json" "$dest/theme/" || return 1
  elif jq -e 'type == "object"' "$state_dir/theme.json" &>/dev/null; then
    cp "$state_dir/theme.json" "$dest/theme/"
  elif [[ -f "$live/theme/theme.json" ]]; then
    cp "$live/theme/theme.json" "$dest/theme/"
  fi

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
# The volume levels in a live greeter.json come only from the bar, so reseeding it keeps them.
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
    "if levels=\$(jq -c '{music_volume, output_volume} | with_entries(select(.value | type == \"string\"))' '$GREETER_DATA/greeter.json' 2>/dev/null); then jq --argjson levels \"\$levels\" '. + \$levels' '$stage/greeter.json' >'$GREETER_DATA/.greeter.json.new' && chmod 640 '$GREETER_DATA/.greeter.json.new' && mv -f '$GREETER_DATA/.greeter.json.new' '$GREETER_DATA/greeter.json'; else install -m 640 '$stage/greeter.json' '$GREETER_DATA/greeter.json'; fi" \
    "$seed_theme" \
    "[ ! -f '$HOME/.face' ] || install -D -m 640 '$HOME/.face' '$GREETER_DATA/faces/$USER'"
}

detect_primary_connector() {
  local connected=()
  for f in /sys/class/drm/*/status; do
    [[ "$(cat "$f" 2>/dev/null)" == "connected" ]] || continue
    local name
    name=$(basename "$(dirname "$f")")
    name="${name#card?-}"
    connected+=("$name")
  done
  case ${#connected[@]} in
  0) echo "eDP-1" ;;
  1) echo "${connected[0]}" ;;
  *)
    if [[ $OPT_YES -eq 1 ]]; then
      info "Primary display for greeter: ${connected[0]} (--yes)" >&2
      echo "${connected[0]}"
    else
      printf '%s\n' "${connected[@]}" | fzf --prompt="Primary display for greeter> " --no-info
    fi
    ;;
  esac
}

# Optionally installs greetd + tuigreet, deploys their configs, the Quickshell greeter (tuigreet stays as its fallback), and enables greetd.
install_greetd() {
  confirm "Install greetd + tuigreet (display manager)?" || return 0

  info "Installing greetd and tuigreet..."
  sudo pacman -S --needed --noconfirm greetd
  sudo pacman -S --needed --noconfirm greetd-tuigreet

  cd "$DOTFILES_DIR" || return 1
  local connector
  connector=$(detect_primary_connector)
  info "Setting greeter primary display: $connector"
  local tmp
  tmp=$(mktemp --suffix=.toml)
  sed "s/connector = \"eDP-1\"/connector = \"$connector\"/" \
    system/etc/tuigreet/config.toml >"$tmp"
  sudo install -Dm644 system/etc/greetd/config.toml /etc/greetd/config.toml
  sudo install -Dm644 "$tmp" /etc/tuigreet/config.toml
  sudo install -Dm755 system/usr/local/bin/tuigreet-oasis /usr/local/bin/tuigreet-oasis
  sudo install -Dm644 system/etc/greetd/kitty.conf /etc/greetd/kitty.conf
  rm -f "$tmp"
  success "greetd/tuigreet config installed"
  enable_greetd_keyring_unlock

  if confirm "Use the Quickshell greeter (your lock screen style; tuigreet stays as fallback)?"; then
    local stage
    stage=$(mktemp -d)
    skin=$(stage_greeter "$stage" "$DOTFILES_DIR") || die "Staging the greeter failed"
    info "Greeter skin: $skin"
    while read -r cmd; do eval "$cmd"; done < <(greeter_install_cmds "$stage" "$DOTFILES_DIR")
    rm -rf "$stage"
    success "Quickshell greeter installed (F10 or SUPER+T switches to tuigreet)"
  else
    sudo install -Dm644 system/etc/greetd/hyprland.lua /etc/greetd/hyprland.lua
    printf '%s\n' "$USER" | sudo tee /etc/greetd/admin_user >/dev/null
    sudo rm -f /usr/local/bin/qs-greeter
    success "tuigreet greeter installed"
  fi

  sudo systemctl enable greetd
  success "greetd enabled (active on next boot)"
}

# Lets the greetd login unlock the GNOME keyring with the password typed at the greeter, so the first secret lookup after
# login (Slack, calendar-sync) raises no second unlock prompt. PAM can only do that while the keyring's password matches
# the login password; when they differ the keyring stays locked and prompts as before, and the login itself still works.

GREETD_KEYRING_AUTH_LINE='auth       optional     pam_gnome_keyring.so'
GREETD_KEYRING_SESSION_LINE='session    optional     pam_gnome_keyring.so auto_start'

# The paths and the sudo command are overridable so the test can run against scratch files without root.
# GREETD_KEYRING_SUDO may be set to the empty string.
enable_greetd_keyring_unlock() {
  local pam_file="${GREETD_PAM_FILE:-/etc/pam.d/greetd}"
  local module="${PAM_GNOME_KEYRING_MODULE:-/usr/lib/security/pam_gnome_keyring.so}"
  local -a sudo_cmd
  read -ra sudo_cmd <<<"${GREETD_KEYRING_SUDO-sudo}"

  if [[ ! -f "$module" ]]; then
    info "gnome-keyring's PAM module is not installed, skipping the login keyring unlock"
    return 0
  fi
  if [[ ! -f "$pam_file" ]]; then
    warn "$pam_file is missing, so greetd cannot unlock the keyring; install greetd first"
    return 0
  fi

  local add_auth=1 add_session=1
  grep -Eq '^[[:space:]]*-?auth[[:space:]].*pam_gnome_keyring\.so' "$pam_file" && add_auth=0
  grep -Eq '^[[:space:]]*-?session[[:space:]].*pam_gnome_keyring\.so' "$pam_file" && add_session=0
  if ((! add_auth && ! add_session)); then
    info "greetd already unlocks the keyring at login"
    return 0
  fi

  # pacman owns this file, so only our two lines go in, each after the last line of its PAM type; an upgrade then
  # leaves a .pacnew to merge rather than silently losing them.
  local tmp
  tmp=$(mktemp) || return 1
  awk -v add_auth="$add_auth" -v add_session="$add_session" \
    -v auth_line="$GREETD_KEYRING_AUTH_LINE" -v session_line="$GREETD_KEYRING_SESSION_LINE" '
    { lines[NR] = $0; if ($1 == "auth") last_auth = NR; if ($1 == "session") last_session = NR }
    END {
      for (i = 1; i <= NR; i++) {
        print lines[i]
        if (add_auth && i == last_auth) print auth_line
        if (add_session && i == last_session) print session_line
      }
      if (add_auth && !last_auth) print auth_line
      if (add_session && !last_session) print session_line
    }' "$pam_file" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if ! "${sudo_cmd[@]}" install -m 644 "$tmp" "$pam_file"; then
    rm -f "$tmp"
    warn "Could not write $pam_file"
    return 1
  fi
  rm -f "$tmp"
  success "greetd now unlocks the keyring at login (needs the keyring password to match your login password)"
}
