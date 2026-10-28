#!/usr/bin/env bash
# Tests the CodeRabbit entry of install_dev_tools with stubbed fzf, curl, sh and coderabbit, so nothing touches the network or the real PATH tools.
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

# A fresh PATH of stubs per case. curl logs its argv and emits a script that logs the CR_CLI_SKIP_LOGIN it ran with, which proves the variable reaches the installer and not just curl.
new_case() {
  case_name="$1"
  stubs="$scratch/stubs"
  rm -rf "$stubs" "$scratch/curl.log" "$scratch/sh.log"
  mkdir -p "$stubs"
  printf '#!/bin/sh\necho coderabbit\n' >"$stubs/fzf"
  cat >"$stubs/curl" <<STUB
#!/bin/sh
echo "curl \$*" >>"$scratch/curl.log"
echo 'echo "installer-ran skip_login=\${CR_CLI_SKIP_LOGIN:-}" >>"$scratch/sh.log"'
STUB
  chmod +x "$stubs"/*
  ORIG_PATH=${ORIG_PATH:-$PATH}
  PATH="$stubs:$ORIG_PATH"
}
has_coderabbit() { printf '#!/bin/sh\n' >"$stubs/coderabbit" && chmod +x "$stubs/coderabbit"; }
curl_calls() { [[ -f "$scratch/curl.log" ]] && wc -l <"$scratch/curl.log" || echo 0; }

# Hide any real coderabbit: command -v must only see the stubs for these cases.
hermetic_path() { PATH="$stubs:/usr/bin:/bin"; }

OPT_YES=0
new_case 'already installed is skipped'
has_coderabbit
hermetic_path
out=$(install_dev_tools 2>&1)
check test "$(curl_calls)" = 0
check grep -q 'already present' <<<"$out"

new_case 'missing is installed with login skipped'
hermetic_path
out=$(install_dev_tools 2>&1)
check test "$(curl_calls)" = 1
check grep -qF 'curl -fsSL https://cli.coderabbit.ai/install.sh' "$scratch/curl.log"
check grep -qxF 'installer-ran skip_login=1' "$scratch/sh.log"
check grep -qF 'coderabbit auth login' <<<"$out"

new_case '--yes selects nothing'
hermetic_path
OPT_YES=1
out=$(install_dev_tools 2>&1)
OPT_YES=0
check test "$(curl_calls)" = 0

new_case 'picker lists coderabbit'
check grep -qx coderabbit < <(read_ini_section devtools.ini TOOLS)

exit $((failures > 0))
