# shellcheck shell=bash disable=SC2034,SC2016
# The bar's notification center: clear it, open it, and show the newest notification again. Do not disturb lives in
# system.sh. Format: ~/.config/voxcmd/README.md

name="Notifications"
confirm=0
# Each action's effect is its own feedback: the center empties, the popup opens, the toast comes back.
silent=1

qs_ipc="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/qs-ipc"

verbs=(
  "clear      (clear|dismiss|delete|remove)( all)?( of)?( the| my)? notifications|clear (the )?notification (center|history)"
  "read_last  (read|show|repeat)( me)? (the )?(last|latest|previous|most recent|newest) notification( again)?|what (was|did) (that|the last) notification( say)?"
  "open       {show}( me)?( the| my)? notifications( center| popup| history)?|{show} (the )?notification (center|popup|history)"
)

examples=(
  "clear notifications"
  "read the last notification"
  "what was that notification"
  "open notifications"
)

declare -A actions=(
  [clear]='clear_notifications'
  [read_last]='show_last_notification'
  [open]='"$qs_ipc" call notifications open'
)

clear_notifications() {
  "$qs_ipc" call notifications clear_all
}

# Re-sent as a transient notification so it shows as a toast without a second copy in the history. Do not disturb
# would swallow it, and asking for it is reason enough to show it, so it goes out critical then.
show_last_notification() {
  local latest
  latest=$("$qs_ipc" call notifications get_last) || return 1
  # silent=1 would leave an empty history looking like a command that did nothing.
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
