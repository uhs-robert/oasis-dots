# shellcheck shell=bash
# Hook library of notifications.toml: sourced before every hook of the integration.

qs_ipc="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/qs-ipc"

clear_notifications() {
  "$qs_ipc" call notifications clear_all
}

# Re-sent as a transient notification so it shows as a toast without a second copy in the history. Do not disturb
# would swallow it, and asking for it is reason enough to show it, so it goes out critical then.
show_last_notification() {
  local latest
  latest=$("$qs_ipc" call notifications get_last) || return 1
  # The integration is silent, which would leave an empty history looking like a command that did nothing.
  if [ -z "$latest" ]; then
    notify-send --transient --app-name=voxcmd "No notifications"
    return
  fi
  local app summary body icon urgency=normal
  local -a icon_args=()
  {
    IFS= read -r -d '' app
    IFS= read -r -d '' summary
    IFS= read -r -d '' body
    IFS= read -r -d '' icon
  } < <(jq -j '(.app, .summary, .body, .icon) | (. // "") + "\u0000"' <<<"$latest")
  [ -z "$icon" ] || icon_args=(--icon="$icon")
  [ "$("$qs_ipc" call notifications get_dnd)" = true ] && urgency=critical
  # notify-send reads C escapes in the body (g_strcompress), so its backslashes are doubled to come out as stored.
  notify-send --transient --urgency="$urgency" --app-name="${app:-Notification}" "${icon_args[@]}" -- "$summary" "${body//\\/\\\\}"
}
