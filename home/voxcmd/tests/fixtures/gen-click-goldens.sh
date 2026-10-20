#!/usr/bin/env bash
# Writes the golden file the Rust tests compare the click matcher against: what click-match.awk made of a page and a
# spoken target. Run it by hand when the corpus changes, never from a check, and commit the output; `cargo test` reads it
# and needs no gawk. A golden changes only with the owner's sign-off (voxcmd-port.md, Working rules).
#
#   home/voxcmd/tests/fixtures/gen-click-goldens.sh
#
# Writes next to this script:
#   click-goldens.tsv  name, spans (1 or empty), target, page, stdout, trace, exit status. Fields are tab separated with
#                      \ \n \t \r escaped. The page is the text itself, or `@name` for click/pages/name.tsv. stdout is the
#                      awk's candidates, trace the `~...` lines of a run with -v explain=1, exit 2 when the awk died.
#
# The rows come from two places: every page and target the matcher sections of run.sh feed the awk (run.sh keeps them
# in CLICK_CASES_DUMP, so the goldens follow the suite), and click/cases.tsv (name, page, raw target, spans) over
# click/pages/*.tsv, which adds what the suite does not try: look-alikes, joined letters, fillers, non-ASCII, long labels,
# fractional scales, a negative origin, strips, and the cases where the awk dies.
#
# gawk runs under C.UTF-8: it counts characters (label truncation) and lowers U+0130 and U+212A to ASCII there, which is
# the locale voxcmd runs in. The Rust matcher assumes it.
set -uo pipefail

fixtures_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
package_dir=$(CDPATH='' cd -- "$fixtures_dir/../.." && pwd)
matcher=$package_dir/.local/share/voxcmd/click-match.awk
out=$fixtures_dir/click-goldens.tsv
sections='matching|words one edit away|joined letters and noise|doubtful words|sub-spans|candidate box|duplicates|runs|coordinate mapping|strips'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

escape() {
  local text=$1
  text=${text//\\/\\\\}
  text=${text//$'\n'/\\n}
  text=${text//$'\t'/\\t}
  text=${text//$'\r'/\\r}
  printf '%s' "$text"
}

# awk_run <page file> <target> <spans> [explain]: stdout, then the trace in $work/trace, status in $work/status.
awk_run() {
  local page=$1 target=$2 spans=$3 explain=${4:-} status
  local -a explain_args=()
  [ -z "$explain" ] || explain_args=(-v explain=1)
  CLICK_TARGET=$target CLICK_SPANS=$spans LC_ALL=C.UTF-8 gawk "${explain_args[@]}" -f "$matcher" "$page" 2>"$work/stderr"
  status=$?
  grep '^~' "$work/stderr" >"$work/trace" || true
  echo "$status" >"$work/status"
}

write_row() {
  local name=$1 spans=$2 target=$3 page_field=$4 page_file=$5 stdout trace status explained
  stdout=$(awk_run "$page_file" "$target" "$spans"; printf x)
  status=$(<"$work/status")
  stdout=${stdout%x}
  explained=$(awk_run "$page_file" "$target" "$spans" explain; printf x)
  explained=${explained%x}
  trace=$(<"$work/trace")
  if [ "$stdout" != "$explained" ]; then
    echo "gen-click-goldens: explain changed the output of $name" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(escape "$name")" "$spans" "$(escape "$target")" "$page_field" "$(escape "${stdout%$'\n'}")" \
    "$(escape "$trace")" "$status" >>"$out.new"
}

# ---- the pages and targets of run.sh ----------------------------------------------------------------------------------

mkdir "$work/dump"
: >"$out.new"
if ! (cd "$package_dir" && env -u VOXCMD_BIN CLICK_CASES_DUMP="$work/dump" VOXCMD_ONLY_SECTIONS="$sections" \
  tests/sandbox.sh tests/run.sh >"$work/run.log" 2>&1); then
  echo "gen-click-goldens: run.sh failed:" >&2
  tail -5 "$work/run.log" >&2
  exit 1
fi
for target_file in "$work"/dump/*.target; do
  id=${target_file##*/}
  id=${id%.target}
  spans=$(<"$work/dump/$id.spans")
  [ -z "$spans" ] || spans=1
  page=$(<"$work/dump/$id.page")
  write_row "suite/$id" "$spans" "$(<"$target_file")" "$(escape "${page}")" "$work/dump/$id.page"
done

# ---- the wider corpus ---------------------------------------------------------------------------------------------------

while IFS=$'\t' read -r name page target spans; do
  write_row "$name" "$spans" "$target" "$page" "$fixtures_dir/click/pages/${page#@}.tsv"
done <"$fixtures_dir/click/cases.tsv"

mv "$out.new" "$out"
echo "wrote $(wc -l <"$out") rows to $out" >&2
