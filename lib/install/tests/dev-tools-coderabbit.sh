#!/usr/bin/env bash
# Tests the CodeRabbit entry of install_dev_tools with stubbed fzf, curl and coderabbit on a PATH holding only those stubs plus sh and awk, so nothing touches the network and a coderabbit installed on this machine stays invisible.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

PKG_DIR="$repo_dir/packages" # read by read_ini_section
export PKG_DIR
source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/common/packages.sh"
source "$repo_dir/lib/install/dev-tools.sh"

failures=0
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}

# A fresh stub dir per case. curl logs its argv and emits a script that logs the CR_CLI_SKIP_LOGIN it ran with, which proves the variable reaches the installer and not just curl; with curl_fails set it exits 22 like `curl -f` on an HTTP error.
new_case() {
  case_name="$1"
  stubs="$scratch/stubs"
  rm -rf "$stubs" "$scratch"/*.log "$scratch/curl_fails"
  mkdir -p "$stubs"
  ln -s "$(command -v sh)" "$stubs/sh"
  ln -s "$(command -v awk)" "$stubs/awk"
  printf '#!/bin/sh\necho fzf-ran >>"%s"\necho coderabbit\n' "$scratch/fzf.log" >"$stubs/fzf"
  cat >"$stubs/curl" <<STUB
#!/bin/sh
echo "curl \$*" >>"$scratch/curl.log"
[ ! -e "$scratch/curl_fails" ] || exit 22
echo 'echo "installer-ran skip_login=\${CR_CLI_SKIP_LOGIN:-}" >>"$scratch/sh.log"'
STUB
  chmod +x "$stubs/fzf" "$stubs/curl"
}
has_coderabbit() { printf '#!/bin/sh\n' >"$stubs/coderabbit" && chmod +x "$stubs/coderabbit"; }
curl_calls() { [[ -f "$scratch/curl.log" ]] && wc -l <"$scratch/curl.log" || echo 0; }

# Only the stub dir is on PATH while the picker runs, so command -v cannot find a real coderabbit.
run_picker() { PATH="$stubs" install_dev_tools 2>&1; }

OPT_YES=0
new_case 'already installed is skipped'
has_coderabbit
out=$(run_picker)
check test "$(curl_calls)" = 0
check grep -q 'already present' <<<"$out"

new_case 'missing is installed with login skipped'
out=$(run_picker)
check test "$(curl_calls)" = 1
check grep -qF 'curl -fsSL https://cli.coderabbit.ai/install.sh' "$scratch/curl.log"
check grep -qxF 'installer-ran skip_login=1' "$scratch/sh.log"
check grep -qF 'coderabbit auth login' <<<"$out"

new_case 'failed download is not reported as installed'
touch "$scratch/curl_fails"
out=$(run_picker)
check test "$(curl_calls)" = 1
check test ! -f "$scratch/sh.log"
check test -z "$(grep -F -e 'coderabbit installed' -e 'coderabbit auth login' <<<"$out")"
# Status as seen by a caller whose shell never set pipefail.
(
  set +o pipefail
  PATH="$stubs" install_devtool_coderabbit >/dev/null 2>&1
)
check test $? -ne 0

new_case '--yes selects nothing'
OPT_YES=1
out=$(run_picker)
OPT_YES=0
check test "$(curl_calls)" = 0
check test ! -f "$scratch/fzf.log"

new_case 'picker lists coderabbit'
check grep -qx coderabbit < <(read_ini_section devtools.ini TOOLS)

exit $((failures > 0))
