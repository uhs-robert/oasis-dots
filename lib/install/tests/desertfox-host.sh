#!/usr/bin/env bash
# Tests lib/install/desertfox-host and install_desertfox_host offline: a stub gh, a stub curl and a fake release install.sh.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
script="$repo_dir/lib/install/desertfox-host"
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"

# curl serves the release JSON for the API URL and a fake install.sh that records its arguments; $STUB_CURL_FAIL breaks it.
cat >"$scratch/bin/curl" <<'STUB'
#!/usr/bin/env bash
[[ -z ${STUB_CURL_FAIL:-} ]] || exit 6
out=""
while [[ $# -gt 0 ]]; do
  case $1 in -o) out=$2; shift ;; http*) url=$1 ;; esac
  shift
done
case $url in
  */releases/latest) echo '{"tag_name": "v9.8.7"}' ;;
  */install.sh)
    printf '#!/usr/bin/env bash\necho "$*" >"$STUB_RECORD"\n' >"$out"
    echo "$url" >"$STUB_RECORD.url" ;;
esac
STUB
cat >"$scratch/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ -z ${STUB_GH_FAIL:-} ]] || exit 1
echo v1.2.3
STUB
chmod +x "$scratch/bin/curl" "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH" STUB_RECORD="$scratch/record"

failures=0
check() { # case_name, wanted, got
  [[ $2 == "$3" ]] || {
    printf 'FAIL %s: wanted "%s", got "%s"\n' "$1" "$2" "$3" >&2
    failures=$((failures + 1))
  }
}

rm -f "$STUB_RECORD"
bash "$script" >/dev/null 2>&1
check "gh tag, v stripped" "1.2.3" "$(cat "$STUB_RECORD" 2>/dev/null)"
check "gh tag, asset url" "https://github.com/uhs-robert/desertfox/releases/download/v1.2.3/install.sh" "$(cat "$STUB_RECORD.url" 2>/dev/null)"

rm -f "$STUB_RECORD"
STUB_GH_FAIL=1 bash "$script" >/dev/null 2>&1
check "gh fails, API fallback" "9.8.7" "$(cat "$STUB_RECORD" 2>/dev/null)"

rm -f "$STUB_RECORD"
STUB_GH_FAIL=1 STUB_CURL_FAIL=1 bash "$script" >/dev/null 2>&1
check "no network exits non-zero" "1" "$?"
[[ ! -e $STUB_RECORD ]] || check "no network runs nothing" "absent" "present"

# install.sh turns a failing install_desertfox_host into a warning, so the function must return non-zero.
out=$(
  DOTFILES_DIR=$repo_dir STUB_GH_FAIL=1 STUB_CURL_FAIL=1 bash -c '
    source "$DOTFILES_DIR/lib/install/load.sh"
    install_desertfox_host || warn "DesertFox hosts were not installed"
  ' 2>&1
)
[[ $out == *"DesertFox hosts were not installed"* ]] || check "install function warns" "warned" "$out"

((failures == 0)) && echo "ok"
exit "$failures"
