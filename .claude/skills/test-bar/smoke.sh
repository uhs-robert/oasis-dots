#!/usr/bin/env bash
# One bounded live pass on the running bar: per style, shoot the popup, OSD, which-key and region selector, then build a contact sheet.
set -euo pipefail

here=$(dirname "$0")
ipc=${SMOKE_QS_IPC:-$(git -C "$here" rev-parse --show-toplevel)/home/hypr/.config/hypr/scripts/qs-ipc}
fail_pattern='ERROR|TypeError|ReferenceError|Binding loop|is not a type|Could not set initial property|File not found|is not installed|Cannot assign'
out=""
dry_run=0
styles=()
missing=()

die() {
  echo "smoke: $*" >&2
  exit 1
}

while (($# > 0)); do
  case $1 in
  --out)
    out=${2:?--out needs a directory}
    shift 2
    ;;
  --dry-run)
    dry_run=1
    shift
    ;;
  -*) die "usage: smoke.sh [--out DIR] [--dry-run] [style...]" ;;
  *)
    styles+=("$1")
    shift
    ;;
  esac
done
((${#styles[@]} > 0)) || styles=(ps1 goldeneye metroid neovim)
out=${out:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/smoke/$(date +%Y%m%d-%H%M%S)}

region_styles=()
for s in "${styles[@]}"; do [[ $s == goldeneye ]] && region_styles+=("$s"); done
for s in "${styles[@]}"; do
  [[ $s != goldeneye ]] && {
    region_styles+=("$s")
    break
  }
done
is_region_style() { [[ " ${region_styles[*]} " == *" $1 "* ]]; }

if ((dry_run)); then
  echo "smoke: out $out"
  for s in "${styles[@]}"; do
    echo "smoke: $s: style set, popup battery, osd, which-key$(is_region_style "$s" && echo ', region (pixel, select)')"
  done
  state=$(timeout 3 "$ipc" call lock state 2>/dev/null || true)
  echo "smoke: lock state '${state:-unknown}' (would $([[ $state == unlocked ]] && echo run || echo refuse))"
  exit 0
fi

state=$(timeout 3 "$ipc" call lock state 2>/dev/null || true)
[[ $state == unlocked ]] || die "lock state is '${state:-unknown}'; not running unless it reports 'unlocked'"

line=$(pgrep -af '^qs -n' | tail -1 || true)
[[ -n $line ]] || die "no running 'qs -n' bar"
qs_path=$(sed -n 's/.* -p \([^ ]*\).*/\1/p' <<<"$line" | head -1)
qs_args=()
[[ -n $qs_path ]] && qs_args=(-p "$qs_path")

q() { qs ipc "${qs_args[@]}" call "$@"; }
qlog() { qs log "${qs_args[@]}" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }

orig_style=$(q style get)
# shellcheck disable=SC2329
restore() {
  hyprctl eval 'hl.dispatch(hl.dsp.submap("reset"))' >/dev/null 2>&1 || true
  q popup close >/dev/null 2>&1 || true
  q screenshot close >/dev/null 2>&1 || true
  # A style set can be dropped while the previous one is still applying, so retry until it reads back.
  local _
  for _ in {1..10}; do
    q style set "$orig_style" >/dev/null 2>&1 || true
    sleep 0.4
    [[ $(q style get 2>/dev/null) == "$orig_style" ]] && return
  done
  echo "smoke: could not restore style '$orig_style'; run: qs ipc call style set $orig_style" >&2
}
trap restore EXIT

mkdir -p "$out"
log_start=$(qlog | wc -l)

layer_geom() {
  hyprctl layers -j | jq -r --arg ns "$1" '[.[].levels[][] | select(.namespace == $ns)] | first // empty | "\(.x) \(.y) \(.w) \(.h)"'
}

wait_layer() {
  for _ in $(seq 30); do
    [[ -n $(layer_geom "$1") ]] && return 0
    sleep 0.1
  done
  return 1
}

wait_gone() {
  for _ in $(seq 30); do
    [[ -z $(layer_geom "$1") ]] && return 0
    sleep 0.1
  done
  return 1
}

shoot() {
  local style=$1 surface=$2 ns=$3
  hyprctl layers -j >"$out/${style}_$surface.layers.json"
  "$here/capture.sh" "$ns" --pad 4 --out "$out/${style}_$surface.png" >/dev/null || missing+=("MISS $style $surface")
  [[ -n $(layer_geom "$ns") ]] || missing+=("MISS $style $surface-gone")
}

region_shot() {
  local style=$1 surface=$2 cx cy
  wait_layer quickshell-region || {
    missing+=("MISS $style $surface")
    return 0
  }
  sleep 1
  read -r cx cy < <(hyprctl cursorpos | tr -d ',')
  grim -g "$((cx < 300 ? 0 : cx - 300)),$((cy < 270 ? 0 : cy - 270)) 600x540" "$out/${style}_$surface.png"
  wtype -k Escape
  wait_gone quickshell-region || missing+=("MISS $style $surface-close")
}

for style in "${styles[@]}"; do
  echo "smoke: $style"
  q style set "$style" >/dev/null
  sleep 1.3
  if [[ $(q style get) != "$style" ]]; then
    missing+=("MISS $style style (unknown name, or it did not apply)")
    continue
  fi

  q popup open battery >/dev/null
  wait_layer quickshell-popup && {
    sleep 0.6
    shoot "$style" popup quickshell-popup
  } || missing+=("MISS $style popup")
  q popup close >/dev/null
  sleep 0.3

  wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+
  wait_layer quickshell-osd && {
    sleep 0.3
    shoot "$style" osd quickshell-osd
  } || missing+=("MISS $style osd")
  wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-

  hyprctl eval 'hl.dispatch(hl.dsp.submap("Leader"))' >/dev/null
  wait_layer quickshell-whichkey && {
    sleep 0.3
    shoot "$style" whichkey quickshell-whichkey
  } || missing+=("MISS $style whichkey")
  hyprctl eval 'hl.dispatch(hl.dsp.submap("reset"))' >/dev/null
  sleep 0.3

  if is_region_style "$style"; then
    q screenshot pick pixel "" >/dev/null
    region_shot "$style" region_pixel
    sleep 0.5
    q screenshot select false "" >/dev/null
    region_shot "$style" region
    sleep 0.5
  fi
done

sheet="$out/sheet.png"
python3 - "$out" "$sheet" <<'PY'
import sys, glob, os
from PIL import Image, ImageDraw
out, sheet = sys.argv[1:3]
files = sorted(f for f in glob.glob(out + "/*.png") if not f.endswith("sheet.png"))
cell_w, cell_h, label_h, cols = 480, 340, 24, 4
rows = max(1, -(-len(files) // cols))
img = Image.new("RGB", (cols * cell_w, rows * (cell_h + label_h)), (24, 24, 28))
draw = ImageDraw.Draw(img)
for i, f in enumerate(files):
    tile = Image.open(f).convert("RGB")
    tile.thumbnail((cell_w - 8, cell_h - 8))
    x, y = (i % cols) * cell_w, (i // cols) * (cell_h + label_h)
    img.paste(tile, (x + 4, y + label_h + 4))
    draw.text((x + 6, y + 6), os.path.basename(f)[:-4], fill=(230, 230, 230))
img.save(sheet)
PY
echo "sheet: $sheet"

new=$(qlog | tail -n +"$((log_start + 1))")
echo "-- new WARN/ERROR lines"
grep -E '^ *(WARN|ERROR)' <<<"$new" || echo none
status=0
if grep -qE "$fail_pattern" <<<"$new"; then
  echo "smoke: log has load failures or errors; for 'X is not a type' on a folder loaded by URL, add import \"<folder>\" to the loader file (see #531)" >&2
  status=1
fi
if ((${#missing[@]} > 0)); then
  printf '%s\n' "${missing[@]}"
  status=1
fi
exit "$status"
