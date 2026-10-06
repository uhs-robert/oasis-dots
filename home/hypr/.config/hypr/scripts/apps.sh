#!/usr/bin/env bash
# hypr/.config/hypr/scripts/apps.sh
# Default apps: `dump` prints the choices as JSON, `apply` sets xdg-mime defaults from the state file,
# `open-folder PATH` opens PATH in the Directories default.

state="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/apps.json"
data_dirs=("${XDG_DATA_HOME:-$HOME/.local/share}")
IFS=: read -ra system_dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
data_dirs+=("${system_dirs[@]}")

groups="web mail pdf images video audio text directories"

# The first type of a group is the one used to list candidates.
group_types() {
  case "$1" in
  web) echo "x-scheme-handler/https x-scheme-handler/http text/html application/xhtml+xml" ;;
  mail) echo "x-scheme-handler/mailto" ;;
  pdf) echo "application/pdf" ;;
  images) echo "image/png image/jpeg image/gif image/webp image/svg+xml" ;;
  video) echo "video/mp4 video/x-matroska video/webm" ;;
  audio) echo "audio/mpeg audio/flac audio/x-wav audio/ogg" ;;
  text) echo "text/plain text/markdown" ;;
  directories) echo "inode/directory" ;;
  esac
}

app_candidates() {
  case "$1" in
  term) echo "kitty foot ghostty wezterm alacritty xterm konsole" ;;
  editor) echo "nvim vim hx micro nano emacs" ;;
  gui_file_manager) echo "thunar nautilus dolphin pcmanfm nemo caja" ;;
  tui_file_manager) echo "yazi ranger lf nnn mc" ;;
  esac
}

desktop_file() {
  local dir
  for dir in "${data_dirs[@]}"; do
    [ -f "$dir/applications/$1" ] && {
      echo "$dir/applications/$1"
      return
    }
  done
}

candidates() {
  local dir id
  for dir in "${data_dirs[@]}"; do
    [ -r "$dir/applications/mimeinfo.cache" ] && sed -n "s|^$1=||p" "$dir/applications/mimeinfo.cache"
  done | tr ';' '\n' | awk 'NF && !seen[$0]++' | while read -r id; do
    [ -n "$(desktop_file "$id")" ] && echo "$id"
  done
}

dump() {
  local group first id file name key cmd
  {
    for group in $groups; do
      first=$(group_types "$group")
      first=${first%% *}
      printf 'cur\t%s\t%s\n' "$group" "$(xdg-mime query default "$first" 2>/dev/null)"
      while read -r id; do
        file=$(desktop_file "$id")
        name=$(sed -n 's/^Name=//p' "$file" | head -n1)
        printf 'opt\t%s\t%s\t%s\n' "$group" "$id" "$name"
      done < <(candidates "$first")
    done
    for key in term editor gui_file_manager tui_file_manager; do
      for cmd in $(app_candidates "$key"); do
        command -v "$cmd" >/dev/null 2>&1 && printf 'cmd\t%s\t%s\n' "$key" "$cmd"
      done
    done
  } | jq -Rn '[inputs | split("\t")] as $rows
    | reduce $rows[] as $r ({mime: {}, app: {}};
      if $r[0] == "cur" then .mime[$r[1]].current = $r[2]
      elif $r[0] == "opt" then .mime[$r[1]].options += [{id: $r[2], name: $r[3]}]
      else .app[$r[1]] += [$r[2]] end)'
}

apply() {
  local group id types
  [ -f "$state" ] || exit 0
  jq -r '.mime // {} | to_entries[] | "\(.key)\t\(.value)"' "$state" 2>/dev/null | while IFS=$'\t' read -r group id; do
    [[ "$id" =~ ^[A-Za-z0-9._+-]+\.desktop$ ]] || continue
    types=$(group_types "$group")
    [ -n "$types" ] || continue
    # shellcheck disable=SC2086
    xdg-mime default "$id" $types
  done
}

# xdg-open ignores Terminal=true outside a full desktop, so a TUI default such as yazi would start with no window.
# This runs a terminal entry in the configured terminal through Hyprland, and anything else straight through Hyprland.
open_folder() {
  local path=$1 id file exec_line terminal quoted cmd lua
  id=$(xdg-mime query default inode/directory 2>/dev/null)
  file=$([ -n "$id" ] && desktop_file "$id")
  if [ -z "$file" ]; then
    exec xdg-open "$path"
  fi
  exec_line=$(sed -n '/^\[Desktop Entry\]/,/^\[/{s/^Exec=//p}' "$file" | head -n1)
  terminal=$(sed -n '/^\[Desktop Entry\]/,/^\[/{s/^Terminal=//p}' "$file" | head -n1)
  quoted=$(printf '%q' "$path")
  if [[ "$exec_line" =~ %[fFuU] ]]; then
    cmd=$(sed -E "s/%[fFuU]/$(printf '%s' "$quoted" | sed 's/[\/&]/\\&/g')/" <<<"$exec_line")
  else
    cmd="$exec_line $quoted"
  fi
  cmd=$(sed -E 's/ ?%[a-zA-Z]//g' <<<"$cmd")
  cmd=$(jq -Rn --arg c "$cmd" '$c')
  if [ "$terminal" = "true" ]; then
    lua="require('lib.actions.cmd').term($cmd)()"
  else
    lua="hl.exec_cmd($cmd)"
  fi
  hyprctl eval "$lua" >/dev/null
}

case "${1:-}" in
dump) dump ;;
apply) apply ;;
open-folder) open_folder "$2" ;;
*)
  echo "usage: apps.sh dump|apply|open-folder PATH" >&2
  exit 2
  ;;
esac
