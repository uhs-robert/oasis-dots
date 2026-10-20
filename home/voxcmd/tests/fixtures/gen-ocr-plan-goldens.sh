#!/usr/bin/env bash
# Writes the golden file the Rust tests compare click-ocr's strip arithmetic and tool calls against: what the bash
# click-ocr did over a grid of window sizes, capture scales and image brightness. Run it by hand when the grid changes,
# never from a check, and commit the output; `cargo test` reads it and needs only the file. A golden changes only with
# the owner's sign-off (voxcmd-port.md, Working rules).
#
#   home/voxcmd/tests/fixtures/gen-ocr-plan-goldens.sh
#
# Writes next to this script:
#   ocr-plan-goldens.tsv  name, window w, window h, mean, stream, calls. stream is the `#window` and `#strip` lines (the
#                         image size is on the `#window` line), calls the magick and tesseract command lines the run made,
#                         sorted (the strips run in parallel) with the work directory as <work>. Fields are tab
#                         separated with \ \n \t \r escaped. Rows named info/* hold one `--explain` run's `#info` line
#                         instead of the calls, its ocr_ms as N.
#
# Not the sandbox's stubs: those do not log the arguments of magick and tesseract, and this must see them all.
set -euo pipefail

fixtures_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
package_dir=$(CDPATH='' cd -- "$fixtures_dir/../.." && pwd)
script=$package_dir/.local/share/voxcmd/click-ocr
out=$fixtures_dir/ocr-plan-goldens.tsv

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/runtime"
chmod 700 "$work/runtime"

cat >"$work/bin/hyprctl" <<'STUB'
#!/bin/sh
printf '{"at": [10, 20], "size": [%s, %s], "class": "term", "stableId": "1"}\n' "$GOLDEN_W" "$GOLDEN_H"
STUB
cat >"$work/bin/grim" <<'STUB'
#!/bin/sh
for out; do :; done
set -- $(awk -v w="$GOLDEN_W" -v h="$GOLDEN_H" -v s="$GOLDEN_SCALE" 'BEGIN { printf "%d %d", w * s + 0.5, h * s + 0.5 }')
{ printf 'P6\n%s %s\n255\n' "$1" "$2"; head -c $(($1 * $2 * 3)) /dev/zero; } >"$out"
STUB
cat >"$work/bin/magick" <<'STUB'
#!/bin/sh
echo "magick $*" >>"$GOLDEN_CALLS"
previous=
for arg; do
  [ "$previous" != -write ] || case "$arg" in info:-) echo "$GOLDEN_MEAN" ;; *) : >"$arg" ;; esac
  previous=$arg
done
STUB
cat >"$work/bin/tesseract" <<'STUB'
#!/bin/sh
echo "tesseract $*" >>"$GOLDEN_CALLS"
[ "$1" != - ] || cat >/dev/null
STUB
chmod +x "$work/bin/"*

escape() {
  local text=$1
  text=${text//\\/\\\\}
  text=${text//$'\n'/\\n}
  text=${text//$'\t'/\\t}
  text=${text//$'\r'/\\r}
  printf '%s' "$text"
}

# run <w> <h> <scale> <mean> [click-ocr args]: stdout in $work/stdout, normalised calls in $work/calls.
run() {
  : >"$work/calls"
  GOLDEN_W=$1 GOLDEN_H=$2 GOLDEN_SCALE=$3 GOLDEN_MEAN=$4 GOLDEN_CALLS=$work/calls.raw XDG_RUNTIME_DIR=$work/runtime \
    PATH="$work/bin:$PATH" bash "$script" "${@:5}" >"$work/stdout"
  sed "s#$work/runtime/voxcmd-click\.[A-Za-z0-9]*#<work>#g" "$work/calls.raw" | LC_ALL=C sort >"$work/calls"
  rm -f "$work/calls.raw"
}

: >"$out.new"
for size in "160 96" "800 600" "1000 1000" "1000 1001" "1000 1500" "1280 2100" "400 3000" "1920 1080"; do
  read -r w h <<<"$size"
  for scale in 1 1.25 1.5 1.6 2; do
    for mean in 1 0.2; do
      run "$w" "$h" "$scale" "$mean"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${w}x${h}@${scale}/${mean}" "$w" "$h" "$mean" \
        "$(escape "$(grep '^#\(window\|strip\)' "$work/stdout")")" "$(escape "$(<"$work/calls")")" >>"$out.new"
    done
  done
done
for case in "info/light 160 96 1.6 1" "info/dark 1000 1500 2 0.2"; do
  read -r name w h scale mean <<<"$case"
  run "$w" "$h" "$scale" "$mean" --explain
  info=$(sed -n 's/\(ocr_ms=\)[0-9]*$/\1N/;1p' "$work/stdout")
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$w" "$h" "$mean" "$(escape "$(grep '^#\(window\|strip\)' "$work/stdout")")" "$(escape "$info")" >>"$out.new"
done
mv "$out.new" "$out"
echo "wrote $(wc -l <"$out") rows to $out" >&2
