#!/usr/bin/env bash

# Rofi window-switcher for Hyprland.
#
# Two modes driven by whether rofi passes a selection back:
#   No args  — print rows to stdout; rofi displays them as the menu.
#   $1 set   — rofi is calling back with the chosen row; focus that window.

set -u

# Fetch all open windows sorted by workspace > class > title.
get_clients() {
  hyprctl clients -j |
    jq -c 'sort_by(.workspace.id, .class, .title)'
}

# Print rofi-formatted rows for every open window.
# Each row: "<index>  <Class>  <title>\0icon\x1f<icon>\x1finfo\x1f<addr>…"
# \0 separates display text from rofi metadata; \x1f separates key/value pairs.
render_rows() {
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

# Focus a window by address, detached with a small delay so rofi closes first.
focus_addr() {
  local addr="$1"

  [ -z "$addr" ] && return 1

  nohup bash -c '
    sleep 0.08
    hyprctl --batch "dispatch focuswindow address:'"$addr"'; dispatch alterzorder top,address:'"$addr"'" >/dev/null 2>&1
  ' >/dev/null 2>&1 &
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

  focus_addr "$addr"
}

main() {
  clients="$(get_clients)"

  if [ -n "${1:-}" ]; then
    handle_selection "$1"
    exit 0
  fi

  render_rows
}

main "$@"
