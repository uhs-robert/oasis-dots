#!/usr/bin/env bash
# One bounded pass on a shadow bar: per style, shoot the popup, OSD, which-key and region selector, then build a contact sheet.
set -euo pipefail

shadow="$(dirname "$0")/shadow.sh"
name=smoke
fail_pattern='ERROR|TypeError|ReferenceError|Binding loop|is not a type|Could not set initial property|File not found|is not installed|Cannot assign'
out=""
dry_run=0
self_test=0
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
  --self-test)
    self_test=1
    shift
    ;;
  --name)
    name=${2:?--name needs a shadow name}
    shift 2
    ;;
  -*) die "usage: smoke.sh [--out DIR] [--name SHADOW] [--dry-run] [--self-test] [style...]" ;;
  *)
    styles+=("$1")
    shift
    ;;
  esac
done
((${#styles[@]} > 0)) || styles=(ps1 goldeneye metroid neovim)
# Exit 0 when the capture is blank (under 1% of pixels differ from what lies behind it), 1 when not, 2 when it cannot compare.
# The optional third argument "x y w h" crops the second image, which is then a whole-output shot.
is_blank() {
  python3 - "$@" <<'PY'
import sys
try:
    from PIL import Image, ImageChops
    a, b = (Image.open(f).convert("RGB") for f in sys.argv[1:3])
    if len(sys.argv) > 3:
        x, y, w, h = map(int, sys.argv[3].split())
        b = b.crop((x, y, x + w, y + h))
    if a.size != b.size:
        sys.exit(2)
    diff = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 16 else 0)
    changed = diff.histogram()[255]
except Exception:
    sys.exit(2)
sys.exit(0 if changed < 0.01 * a.size[0] * a.size[1] else 1)
PY
}

if ((self_test)); then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  python3 - "$tmp" <<'PY'
import sys
from PIL import Image, ImageDraw
d = sys.argv[1]
base = Image.new("RGB", (200, 100), (30, 30, 40))
base.save(d + "/a.png")
base.save(d + "/same.png")
other = base.copy()
ImageDraw.Draw(other).rectangle((20, 20, 120, 80), fill=(220, 220, 220))
other.save(d + "/other.png")
PY
  status=0
  if is_blank "$tmp/a.png" "$tmp/same.png"; then echo "ok: identical images read as blank"; else
    echo "FAIL: identical images not blank"
    status=1
  fi
  rc=0
  is_blank "$tmp/a.png" "$tmp/other.png" || rc=$?
  if ((rc == 1)); then echo "ok: different images read as ok"; else
    echo "FAIL: different images not read as ok"
    status=1
  fi
  rc=0
  is_blank "$tmp/a.png" "$tmp/missing.png" || rc=$?
  if ((rc == 2)); then echo "ok: unreadable image reads as a check error"; else
    echo "FAIL: unreadable image not a check error"
    status=1
  fi
  exit "$status"
fi
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
    echo "smoke: $s: style set, popup battery, osd (voxtype recording), which-key (fixture payload)$(is_region_style "$s" && echo ', region (pixel, select)')"
  done
  "$shadow" status "$name" | head -1
  exit 0
fi

started_shadow=0
if [[ $("$shadow" status "$name") == "$name: down" ]]; then
  "$shadow" up "$name" >&2
  started_shadow=1
fi

q() { "$shadow" ipc "$name" "$@"; }
sh_hyprctl() { "$shadow" hyprctl "$name" "$@"; }
qlog() { sed 's/\x1b\[[0-9;]*m//g' "${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/shadow/$name/logs/qs.log"; }

orig_style=$(q style get)
# shellcheck disable=SC2329
restore() {
  q popup close >/dev/null 2>&1 || true
  q screenshot close >/dev/null 2>&1 || true
  if ((started_shadow)); then
    "$shadow" down "$name" >&2 || true
    return
  fi
  # A style set can be dropped while the previous one is still applying, so retry until it reads back.
  local _
  for _ in {1..10}; do
    q style set "$orig_style" >/dev/null 2>&1 || true
    sleep 0.4
    [[ $(q style get 2>/dev/null) == "$orig_style" ]] && return
  done
  echo "smoke: could not restore style '$orig_style'; run: shadow.sh ipc $name style set $orig_style" >&2
}
trap restore EXIT

mkdir -p "$out"
log_start=$(qlog | wc -l)

# "x y w h" of a layer grown by pad, clamped at the output's top-left corner like shadow.sh shot.
layer_rect() {
  sh_hyprctl layers -j | jq -r --arg ns "$1" --argjson pad "${2:-0}" '
    [.[].levels[][] | select(.namespace == $ns)] | first // empty
    | (if .x - $pad < 0 then 0 else .x - $pad end) as $x0
    | (if .y - $pad < 0 then 0 else .y - $pad end) as $y0
    | "\($x0) \($y0) \(.w + .x - $x0 + $pad) \(.h + .y - $y0 + $pad)"'
}

layer_geom() { layer_rect "$1"; }

wait_layer() {
  for _ in $(seq 30); do
    [[ -n $(layer_geom "$1") ]] && return 0
    sleep 0.1
  done
  return 1
}

wait_gone() {
  for _ in $(seq 100); do
    [[ -z $(layer_geom "$1") ]] && return 0
    sleep 0.1
  done
  return 1
}

last_rect=""

# Shoots the whole output once the surface is gone and compares the surface's rect with it; records a blank capture as a miss.
check_blank() {
  local style=$1 surface=$2 ns=$3
  local rect=$last_rect
  last_rect=""
  [[ -n $rect ]] || return 0
  wait_gone "$ns" || {
    missing+=("MISS $style $surface-close")
    return 0
  }
  sleep 0.3
  mkdir -p "$out/behind"
  "$shadow" shot "$name" --out "$out/behind/${style}_$surface.png" >/dev/null
  local rc=0
  is_blank "$out/${style}_$surface.png" "$out/behind/${style}_$surface.png" "$rect" || rc=$?
  case $rc in
  0) missing+=("MISS $style $surface-blank") ;;
  1) ;;
  *) missing+=("MISS $style $surface-check") ;;
  esac
}

shoot() {
  local style=$1 surface=$2 ns=$3
  last_rect=$(layer_rect "$ns" 4)
  sh_hyprctl layers -j >"$out/${style}_$surface.layers.json"
  "$shadow" shot "$name" "$ns" --pad 4 --out "$out/${style}_$surface.png" >/dev/null || missing+=("MISS $style $surface")
  [[ -n $(layer_geom "$ns") ]] || missing+=("MISS $style $surface-gone")
}

region_shot() {
  local style=$1 surface=$2 cx cy
  wait_layer quickshell-region || {
    missing+=("MISS $style $surface")
    return 0
  }
  sleep 1
  read -r cx cy < <(sh_hyprctl cursorpos | tr -d ',')
  last_rect="$((cx < 300 ? 0 : cx - 300)) $((cy < 270 ? 0 : cy - 270)) 600 540"
  "$shadow" shot "$name" --out "$out/${style}_$surface.png" >/dev/null
  python3 - "$out/${style}_$surface.png" "$last_rect" <<'PY'
import sys
from PIL import Image
x, y, w, h = map(int, sys.argv[2].split())
Image.open(sys.argv[1]).crop((x, y, x + w, y + h)).save(sys.argv[1])
PY
  "$shadow" keys "$name" -k Escape
  check_blank "$style" "$surface" quickshell-region
}

# The shadow loads no HyprVim, so the HUD is fed a payload of the shape HyprVim writes (keys, groups, a destructive row, footer).
whichkey_payload="$out/whichkey.json"
cat >"$whichkey_payload" <<'JSON'
{
  "title": "Leader",
  "position": "bottom-right",
  "columns": 2,
  "items": [
    { "key": "a", "desc": "Apps", "group": true },
    { "key": "b", "desc": "Browser" },
    { "key": "t", "desc": "Terminal" },
    { "key": "w", "desc": "Windows", "group": true },
    { "key": "f", "desc": "Fullscreen" },
    { "key": "q", "desc": "Close window", "destructive": true }
  ],
  "footer": [{ "key": "ESC", "desc": "close" }, { "key": "BS", "desc": "back" }]
}
JSON

for style in "${styles[@]}"; do
  echo "smoke: $style"
  q style set "$style" >/dev/null
  sleep 1.3
  if [[ $(q style get) != "$style" ]]; then
    missing+=("MISS $style style (unknown name, or it did not apply)")
    continue
  fi

  q popup open battery >/dev/null
  wait_layer quickshell-popup && "$shadow" wait "$name" popup battery >/dev/null && {
    shoot "$style" popup quickshell-popup
  } || missing+=("MISS $style popup")
  q popup close >/dev/null
  check_blank "$style" popup quickshell-popup
  sleep 0.3

  "$shadow" voxtype "$name" recording
  wait_layer quickshell-osd && "$shadow" wait "$name" osd voxtype >/dev/null && {
    shoot "$style" osd quickshell-osd
  } || missing+=("MISS $style osd")
  "$shadow" voxtype "$name" idle
  check_blank "$style" osd quickshell-osd

  q hyprvim_whichkey open "$whichkey_payload" >/dev/null
  wait_layer quickshell-whichkey && {
    sleep 0.3
    shoot "$style" whichkey quickshell-whichkey
  } || missing+=("MISS $style whichkey")
  q hyprvim_whichkey close >/dev/null
  check_blank "$style" whichkey quickshell-whichkey
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
# Qt's text-input warning fires on every layer surface that closes in a headless nested compositor.
grep -E '^ *(WARN|ERROR)' <<<"$new" | grep -v 'qt.qpa.wayland.textinput' || echo none
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
