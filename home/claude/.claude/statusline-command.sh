#!/usr/bin/env bash
input=$(cat)

eval "$(printf '%s' "$input" | jq -r '
  @sh "cwd=\(.cwd // "")",
  @sh "name=\(.session_name // "")",
  @sh "model=\(.model.display_name // "")",
  @sh "effort=\(.effort.level // "")",
  @sh "thinking=\(.thinking.enabled // false)"')"

cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ttl=60

label=""
repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$repo_root" ]; then
  branch=$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null)
  key=$(printf '%s@%s' "$repo_root" "$branch" | tr -c 'A-Za-z0-9._-' '_')
  cache="$cfg/.pr-cache/$key"
  mkdir -p "$cfg/.pr-cache"

  if [ -z "$(find "$cache" -newermt "-$ttl seconds" 2>/dev/null)" ]; then
    lock="$cache.lock"
    if mkdir "$lock" 2>/dev/null; then
      ( bash "$cfg/pr-context.sh" "$repo_root" "$branch" "$cache"; rmdir "$lock" ) >/dev/null 2>&1 &
      disown 2>/dev/null
    fi
  fi

  [ -f "$cache" ] && [ ! -L "$cache" ] && label=$(head -c 64 "$cache" | tr -d '\000-\037')

  # Branch number carries the issue while gh is still resolving, or when it cannot.
  if [ -z "$label" ]; then
    num=$(printf '%s' "$branch" | grep -oE '[0-9]{1,6}' | head -1)
    [ -n "$num" ] && label="#$num"
  fi
fi

badge=$(printf '%s' "$input" | bash "$HOME/.claude/plugins/marketplaces/caveman/src/hooks/caveman-statusline.sh")

sep=" \033[38;5;240m·\033[0m "
printf '\033[38;5;250m%s\033[0m' "$(basename "$cwd")"
[ -n "$name" ] && printf "$sep"'\033[38;5;110m%s\033[0m' "$(printf '%s' "$name" | head -c 40)"
[ -n "$label" ] && printf "$sep"'\033[38;5;114m%s\033[0m' "$(printf '%s' "$label" | head -c 48)"
if [ -n "$model" ]; then
  printf "$sep"'\033[38;5;245m%s' "$model"
  [ -n "$effort" ] && printf ' %s' "$effort"
  [ "$thinking" = "false" ] && printf ' no-think'
  printf '\033[0m'
fi
[ -n "$badge" ] && printf ' %s' "$badge"
exit 0
