#!/usr/bin/env bash

# Rofi window-switcher for Hyprland.
#
# Two modes driven by whether rofi passes a selection back:
#   No args  — print rows to stdout; rofi displays them as the menu.
#   $1 set   — rofi is calling back with the chosen row; act on that window.
#
# Action modes (set via ROFI_HYPRWINDOW_MODE or -m/--move flag):
#   focus (default) — focus the selected window.
#   move            — move the active window to the selected window's workspace.
#
# Usage from a keybinding:
#   rofi-hyprwindow.sh           # focus mode (rofi calls this as a script)
#   rofi-hyprwindow.sh -m        # move mode  (script self-relaunches rofi)
#   rofi-hyprwindow.sh --move    # same

set -u

MODE="${ROFI_HYPRWINDOW_MODE:-focus}"

log() { logger -t "rofi-hyprwindow" "$*"; }

# Fetch all open windows sorted by workspace > class > title.
get_clients() {
  hyprctl clients -j |
    jq -c 'sort_by(.workspace.id, .class, .title)'
}

# Print rofi-formatted rows for every open window.
# Each row: "<index>  <Class>  <title>\0icon\x1f<icon>\x1finfo\x1f<addr>…"
# \0 separates display text from rofi metadata; \x1f separates key/value pairs.
render_rows() {
  [[ "$MODE" == move* ]] && printf '\x00prompt\x1fMove window to\n'
  jq -r '
    # Build a single "key\x1fvalue" rofi metadata pair.
    def rofi_option($key; $value):
      "\($key)\u001f\($value)";

    # Prefer .class; fall back to .initialClass; then a generic icon name.
    def class_raw:
      (.value.class // .value.initialClass // "application-x-executable");

    # Strip reverse-DNS prefix (e.g. "org.gnome.Nautilus" > "Nautilus").
    def class_short:
      class_raw
      | if test("\\.") then split(".")[-1] else . end;

    def propercase:
      if length == 0 then
        .
      else
        (.[0:1] | ascii_upcase) + (.[1:] | ascii_downcase)
      end;

    # Propercase class name for the display column.
    def class_label:
      class_short | propercase;

    # Lowercase class name used for XDG icon lookup.
    def icon_name:
      class_short | ascii_downcase;

    # Strip noisy app-name suffixes from window titles and odd prefixes.
    def display_title:
      (.value.title // "") as $title
      | (class_short | ascii_downcase) as $class
      | (
          if $class == "firefox" then
            ($title | sub("^XXX\\s*"; ""))
          else
            $title
          end
        )
      | sub("\\s+[—-]\\s+(Mozilla Firefox|Betterbird|Slack|qutebrowser)$"; "");

    to_entries[]
    | "\(.key + 1 | tostring | . + (" " * (4 - length))) \(class_label + (" " * (14 - (class_label | length)))) \(display_title)\u0000"
      + rofi_option("icon"; icon_name)
      + "\u001f"
      + rofi_option("info"; .value.address)
      + "\u001f"
      + rofi_option("meta"; "\(class_raw) \(.value.initialClass) \(.value.workspace.name) \(.value.title)")
      + "\u001f"
      + rofi_option("active"; ((.value.focusHistoryID == 0) | tostring))
  ' <<<"$clients"
}

# Resolve a 1-based row index to the window address stored in $clients.
get_addr_by_index() {
  local index="$1"

  [[ "$index" =~ ^[0-9]+$ ]] || return 1

  jq -r --argjson idx "$((index - 1))" \
    '.[$idx].address // empty' <<<"$clients"
}

# Pull the leading number off the row text rofi echoes back.
extract_index() {
  sed -E 's/^([0-9]+).*/\1/' <<<"$1"
}

# Move the window captured before rofi opened to the workspace of target address.
move_to_workspace() {
  local target_addr="$1"
  local source_addr="${ROFI_HYPRWINDOW_SOURCE:-}"

  [ -z "$target_addr" ] && return 1
  [ -z "$source_addr" ] && {
    log "move_to_workspace: ROFI_HYPRWINDOW_SOURCE not set"
    return 1
  }

  local workspace_id
  workspace_id="$(jq -r --arg addr "$target_addr" \
    '.[] | select(.address == $addr) | .workspace.id // empty' <<<"$clients")"

  log "move_to_workspace: source=$source_addr target=$target_addr workspace=$workspace_id"

  [ -z "$workspace_id" ] && {
    log "move_to_workspace: no workspace found for target"
    return 1
  }

  local follow="false"
  [[ "$MODE" == "move" ]] && follow="true"
  hyprctl dispatch "hl.dsp.focus({window='address:$source_addr'})" >/dev/null
  hyprctl dispatch "hl.dsp.window.move({workspace=$workspace_id, follow=$follow})" >/dev/null
}

# Focus a window by address, detached with a small delay so rofi closes first.
focus_addr() {
  local addr="$1"

  [ -z "$addr" ] && return 1

  nohup bash -c "
    sleep 0.08
    hyprctl dispatch \"hl.dsp.focus({window='address:$addr'})\" >/dev/null 2>&1
    hyprctl dispatch \"hl.dsp.window.alter_zorder({mode='top', window='address:$addr'})\" >/dev/null 2>&1
  " >/dev/null 2>&1 &
}

# Called on rofi callback: resolve address via $ROFI_INFO (preferred) or
# from the leading index in the row text, then focus that window.
handle_selection() {
  local selected="$1"
  local addr="${ROFI_INFO:-}"

  if [ -z "$addr" ]; then
    local index
    index="$(extract_index "$selected")"
    addr="$(get_addr_by_index "$index")"
  fi

  log "handle_selection: MODE=$MODE ROFI_RETV=${ROFI_RETV:-unset} addr=$addr"

  if [[ "$MODE" == move* ]]; then
    move_to_workspace "$addr"
  else
    focus_addr "$addr"
  fi
}

main() {
  # When called directly with -m/--move, capture the active window now (before
  # rofi steals focus), then relaunch rofi with both env vars set.
  if [[ -z "${ROFI_RETV:-}" ]] && [[ "${1:-}" == "-m" || "${1:-}" == "--move" || "${1:-}" == "--move-silent" ]]; then
    local mode="move-silent"
    [[ "${1:-}" == "--move" || "${1:-}" == "-m" ]] && mode="move"
    local source_addr
    source_addr="$(hyprctl activewindow -j | jq -r '.address // empty')"
    log "launching rofi in $mode mode, source=$source_addr"
    exec env ROFI_HYPRWINDOW_MODE="$mode" ROFI_HYPRWINDOW_SOURCE="$source_addr" \
      rofi -i -show hyprwindow
  fi

  clients="$(get_clients)"

  if [ -n "${1:-}" ]; then
    handle_selection "$1"
    exit 0
  fi

  render_rows
}

main "$@"
