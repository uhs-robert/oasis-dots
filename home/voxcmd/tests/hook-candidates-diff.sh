#!/usr/bin/env bash
# Runs the candidates hooks of apps.sh and firefox.sh from an earlier revision and from this checkout over the sandbox
# desktop (the phrase fixtures, then a richer desktop) and fails on any difference in what they print. A faster rewrite
# of a hook has to offer the same candidates, in the same order, with the same labels.
#
#   home/voxcmd/tests/hook-candidates-diff.sh [git-ref]     compare the integrations at git-ref (default origin/main)
#   home/voxcmd/tests/hook-candidates-diff.sh --self-check [git-ref]
#                                                           also prove the comparison catches a changed candidate order
#
# Not part of a check run: the reference revision only means something while a hook rewrite is under review.
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
fixtures_dir="$tests_dir/fixtures"
package_dir=$(dirname "$tests_dir")

if [ -z "${SANDBOX_DIR:-}" ]; then
  # shellcheck source-path=SCRIPTDIR source=phrase-fixtures.sh
  . "$tests_dir/phrase-fixtures.sh"
  exec "$tests_dir/sandbox.sh" "$0" "$@"
fi

self_check=0
ref=origin/main
for argument in "$@"; do
  case $argument in
  --self-check) self_check=1 ;;
  *) ref=$argument ;;
  esac
done

"$tests_dir/firefox-profile" "$HOME/.config/mozilla/firefox"

reference_dir="$SANDBOX_DIR/reference-integrations"
mkdir -p "$reference_dir"
repo_root=$(git -C "$package_dir" rev-parse --show-toplevel)
integrations_path=${package_dir#"$repo_root"/}/.config/voxcmd/integrations
for library in apps.sh firefox.sh; do
  git -C "$repo_root" show "$ref:$integrations_path/$library" >"$reference_dir/$library"
done
# apps.sh and firefox.sh read the file's presence to know Firefox is installed.
touch "$reference_dir/firefox.toml"
current_dir="$package_dir/.config/voxcmd/integrations"
share_dir="$package_dir/.local/share/voxcmd"

# One hook as voxcmd starts it: bash over the integration's library, then the hook, with the match in VOXCMD_* variables.
run_hook() {
  local dir=$1 library=$2 hook=$3 target=$4 ignore=$5
  VOXCMD_INTEGRATION_DIR=$dir VOXCMD_SHARE_DIR=$share_dir VOXCMD_SELF=$(command -v voxcmd) \
    VOXCMD_ARG_TARGET=$target VOXCMD_RAW_TRANSCRIPT="go to $target" VOXCMD_MATCH_IGNORE_WORDS=$ignore \
    bash --noprofile --norc -c ". \"\$VOXCMD_INTEGRATION_DIR/$library\"; $hook" 2>&1 || printf 'exit %s\n' "$?"
}

apps_ignore="window app application program"
firefox_ignore="tab tabs website site page"
apps_actions=(open open_new focus close move move_with_window swap resize grow shrink)
targets=(
  "" firefox slack kitty calendar "my calendar" "the calendar" "gnome calendar" terminal "file manager" files browser
  "the browser" browsers "visual studio code" code dolphin "not kde" "only kde" "no display" "workspace 2" left right
  "this window" it me "example docs" "getting started" general zsh home classless "firefox window" "tmux session"
  "claude agent" "new tab" "firefox in firefox" "example in firefox" "firefox to workspace 3" "kitty to workspace 2"
  "this window to workspace 5" "it to the third workspace" "me to workspace 5" "to workspace 5" "to workspace 99"
  "firefox to special workspace notes" "slack to workspace twenty five" "firefox to 1200 by 800" "width by 100"
  "the width" "with firefox" "this window with slack" "voice command" application window "volume up" mute screenshot
  "resize left" "firefox and slack" "firefox, slack" "KITTY"
)
# Every described keybind, spoken the way a user would: they drive the keybind check each hook starts with.
while IFS= read -r description; do targets+=("$description"); done < <(
  jq -r '.[] | select(.has_description) | .description | ascii_downcase' "$fixtures_dir/binds.json" | sort -u
)

cases=0 differing=0
compare() {
  local label=$1 library=$2 hook=$3 target=$4 ignore=$5 old new
  old=$(run_hook "$reference_dir" "$library" "$hook" "$target" "$ignore")
  new=$(run_hook "$current_dir" "$library" "$hook" "$target" "$ignore")
  cases=$((cases + 1))
  if [ "$old" != "$new" ]; then
    differing=$((differing + 1))
    printf 'DIFF %s\n--- %s\n%s\n--- this checkout\n%s\n' "$label" "$ref" "$old" "$new"
  fi
}

compare_desktop() {
  local desktop=$1 target action
  for target in "${targets[@]}"; do
    for action in "${apps_actions[@]}"; do
      compare "$desktop, apps $action: $target" apps.sh "apps_candidates $action" "$target" "$apps_ignore"
    done
    compare "$desktop, firefox tabs: $target" firefox.sh tab_candidates "$target" "$firefox_ignore"
    compare "$desktop, firefox sites: $target" firefox.sh site_candidates "$target" "$firefox_ignore"
  done
  compare "$desktop, apps help" apps.sh help_apps "" "$apps_ignore"
  compare "$desktop, firefox help" firefox.sh tab_help "" "$firefox_ignore"
}

# The fixture desktop has four apps and three windows. The second adds what the desktop-file reader and the window
# naming have to agree on: a Hidden copy masking a system one, apps shown or hidden by desktop, a subdirectory id, a
# terminal app with a Path, apps sharing a name or a short id, and windows that are unmapped, classless, outside the
# focus history or long-titled.
extra_data="$SANDBOX_DIR/extra-data"
mkdir -p "$extra_data/applications/kde"
desktop_file() {
  local file=$1 name=$2
  shift 2
  {
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s %%F\n' "$name" "${file%.desktop}"
    [ "$#" -eq 0 ] || printf '%s\n' "$@"
    printf '[Desktop Action new]\nName=Wrong Name\nExec=wrong\n'
  } >"$extra_data/applications/$file"
}
desktop_file kitty.desktop Kitty Hidden=true
desktop_file code.desktop "Visual Studio Code" Terminal=true Path=/tmp StartupWMClass=Code
desktop_file org.gnome.Files.desktop Files
desktop_file org.gnome.Nautilus.desktop Files
desktop_file terminal.desktop Terminal
desktop_file file-manager.desktop "File Manager"
desktop_file only-kde.desktop "Only KDE" OnlyShowIn=KDE
desktop_file not-kde.desktop "Not KDE" NotShowIn=KDE
desktop_file gone.desktop "Not Hyprland" NotShowIn=Hyprland
desktop_file nodisplay.desktop "No Display" NoDisplay=true
desktop_file kde/dolphin.desktop Dolphin
desktop_file plural.desktop "Browsers"
desktop_file browser.desktop "Browser"
printf '[Desktop Entry]\nType=Link\nName=A Link\nExec=x\n' >"$extra_data/applications/link.desktop"
extra_clients=$(jq -c '
  . + [(.[] | select(.class == "kitty")) as $window
    | ($window | .class = "Code" | .title = "main.rs - voxcmd - Visual Studio Code" | .address = "0x2001" | .focusHistoryID = 3),
      ($window | .class = "org.gnome.Files" | .title = "Home" | .address = "0x2002" | .focusHistoryID = -1),
      ($window | .class = "" | .title = "classless" | .address = "0x2003"),
      ($window | .class = "unmapped" | .title = "nothing" | .address = "0x2004" | .mapped = false),
      ($window | .class = "Terminal" | .title = ("a very long title " * 6) | .address = "0x2005" | .focusHistoryID = 4),
      ($window | .class = "slack" | .title = "slack" | .address = "0x2006" | .focusHistoryID = 5)]' <<<"$SANDBOX_CLIENTS_JSON")

compare_desktop "fixture desktop"
XDG_DATA_HOME="$extra_data" XDG_DATA_DIRS="$extra_data:$fixtures_dir" SANDBOX_CLIENTS_JSON=$extra_clients \
  compare_desktop "extended desktop"

# A comparison that never sees a candidate would pass any rewrite.
for sample in "apps.sh|apps_candidates open|firefox|$apps_ignore" "apps.sh|apps_candidates focus|slack|$apps_ignore" \
  "firefox.sh|tab_candidates|example docs|$firefox_ignore"; do
  IFS='|' read -r library hook target ignore <<<"$sample"
  if [ -z "$(run_hook "$current_dir" "$library" "$hook" "$target" "$ignore")" ]; then
    echo "no candidates for '$hook $target': the fixtures no longer exercise it" >&2
    differing=$((differing + 1))
  fi
done

# ... and the second desktop has to reach the reader and the window naming: a Hidden copy masks Kitty, Code is a window.
extended=$(XDG_DATA_HOME="$extra_data" XDG_DATA_DIRS="$extra_data:$fixtures_dir" SANDBOX_CLIENTS_JSON=$extra_clients \
  bash -c '
    run() { VOXCMD_INTEGRATION_DIR=$1 VOXCMD_SHARE_DIR=$2 VOXCMD_SELF=$(command -v voxcmd) VOXCMD_ARG_TARGET=x \
      VOXCMD_MATCH_IGNORE_WORDS= bash --noprofile --norc -c ". \"\$VOXCMD_INTEGRATION_DIR/apps.sh\"; apps_candidates $3"; }
    run "$@" open; run "$@" focus' _ "$current_dir" "$share_dir" 2>&1)
for expected in $'\tVisual Studio Code\t' $'\tVisual Studio Code: main.rs' $'\tFiles\tNautilus'; do
  if ! grep -qF -- "$expected" <<<"$extended"; then
    echo "the extended desktop no longer offers '${expected//$'\t'/<tab>}'" >&2
    differing=$((differing + 1))
  fi
done
if grep -q 'kitty.desktop' <<<"$extended"; then
  echo 'the extended desktop offers kitty.desktop, which its Hidden copy masks' >&2
  differing=$((differing + 1))
fi

printf 'compared %s hook runs against %s: %s differ\n' "$cases" "$ref" "$differing"
[ "$differing" -eq 0 ] || exit 1

if [ "$self_check" = 1 ]; then
  # The current libraries with the candidates reversed: same candidates, other order. The comparison has to notice.
  mutated_dir="$SANDBOX_DIR/mutated-integrations"
  mkdir -p "$mutated_dir"
  cp "$current_dir/apps.sh" "$current_dir/firefox.sh" "$mutated_dir/"
  touch "$mutated_dir/firefox.toml"
  cat >>"$mutated_dir/apps.sh" <<'EOF'

apps_candidates() {
  candidates_json "$1" "$VOXCMD_ARG_TARGET" | candidate_rows | tac
}
EOF
  old=$(run_hook "$reference_dir" apps.sh "apps_candidates open" firefox "$apps_ignore")
  new=$(run_hook "$mutated_dir" apps.sh "apps_candidates open" firefox "$apps_ignore")
  if [ "$old" = "$new" ]; then
    echo 'self-check failed: a reversed candidate order compared equal' >&2
    exit 1
  fi
  echo 'self-check ok: a reversed candidate order is reported as a difference'
fi
