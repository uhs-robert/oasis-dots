#!/usr/bin/env bash
# Screenshot one Quickshell layer by namespace, optionally revealing it past no_screen_share.
set -euo pipefail

ipc="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/home/hypr/.config/hypr/scripts/qs-ipc"

die() {
  echo "capture: $*" >&2
  exit 1
}

ns=${1:-}
[[ -n $ns ]] || die "usage: capture.sh <namespace> [--pad N] [--reveal] [--screen NAME] [--out PATH] [--rect-file PATH]"
shift
pad=0
reveal=0
out=""
rect_file=""
screen=""
while (($# > 0)); do
  case $1 in
    --pad)
      pad=${2:?--pad needs a number}
      shift 2
      ;;
    --reveal)
      reveal=1
      shift
      ;;
    --screen)
      screen=${2:?--screen needs a monitor name}
      shift 2
      ;;
    --out)
      out=${2:?--out needs a path}
      shift 2
      ;;
    --rect-file)
      rect_file=${2:?--rect-file needs a path}
      shift 2
      ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ $pad =~ ^[0-9]+$ ]] || die "--pad must be a non-negative integer"

state=$(timeout 3 "$ipc" call lock state 2>/dev/null || true)
[[ $state == unlocked ]] || die "lock state is '${state:-unknown}'; not capturing unless it reports 'unlocked'"

read -r cx cy < <(hyprctl cursorpos | tr -d ',')
geom=$(
  hyprctl layers -j | jq -r --arg ns "$ns" '
    [to_entries[] | .key as $mon | .value.levels[][] | select(.namespace == $ns) | . + {mon: $mon}] as $hits
    | $hits[] | "\(.x) \(.y) \(.w) \(.h) \(.mon)"'
)
[[ -n $geom ]] || die "no layer with namespace '$ns' (see: hyprctl layers -j)"

pick=$(head -1 <<<"$geom")
if [[ -n $screen ]]; then
  pick=$(awk -v m="$screen" '$5 == m { print; exit }' <<<"$geom")
  [[ -n $pick ]] || die "no '$ns' layer on screen '$screen'"
elif (($(wc -l <<<"$geom") > 1)); then
  mon=$(hyprctl monitors -j | jq -r --argjson cx "$cx" --argjson cy "$cy" '.[] | . as $m | (if .transform % 2 == 1 then [.height, .width] else [.width, .height] end | map(. / $m.scale)) as [$w, $h] | select(.x <= $cx and $cx < .x + $w and .y <= $cy and $cy < .y + $h) | .name')
  pick=$(awk -v m="$mon" '$5 == m { print; exit }' <<<"$geom")
  [[ -n $pick ]] || pick=$(head -1 <<<"$geom")
fi
read -r x y w h _ <<<"$pick"

x0=$((x - pad < 0 ? 0 : x - pad))
y0=$((y - pad < 0 ? 0 : y - pad))
w0=$((w + (x - x0) + pad))
h0=$((h + (y - y0) + pad))

if ((reveal)); then
  trap 'hyprctl eval "capture_reveal_rule:set_enabled(false)" >/dev/null' EXIT
  hyprctl eval "capture_reveal_rule = hl.layer_rule({ name = \"capture_reveal\", match = { namespace = \"$ns\" }, no_screen_share = false })" >/dev/null
  sleep 0.5
fi

out=${out:-${XDG_RUNTIME_DIR:-/tmp}/capture-$ns-$(date +%H%M%S).png}
[[ -z $rect_file ]] || echo "$x0,$y0 ${w0}x$h0" >"$rect_file"
grim -g "$x0,$y0 ${w0}x$h0" "$out"
echo "$out"
