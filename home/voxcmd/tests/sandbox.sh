#!/usr/bin/env bash
# Runs a command with voxcmd cut off from the live desktop: its own runtime dir, a config dir holding this checkout's
# integrations and replacements, this checkout's voxcmd first on PATH, and stubs in place of everything that acts.
# `voxcmd` there is the new CLI: VOXCMD_BIN=bash (the default) reaches the bash voxcmd through the shim in tests/bin;
# VOXCMD_BIN=rs builds this checkout's Rust crate (cargo build --release, once per sandbox start) and puts its binary
# first on PATH instead. run-phrases.sh passes under rs; the other suites fail until their items land (voxcmd-port 2.3 and later).
#
#   home/voxcmd/tests/sandbox.sh <command...>
#   home/voxcmd/tests/sandbox.sh voxcmd explain "close firefox"
#   SANDBOX_SHOW_CALLS=1 home/voxcmd/tests/sandbox.sh voxcmd run "close firefox"
#
# Stubs log each call and succeed, printing nothing or a plausible answer (wpctl get-volume, qs-ipc get_dnd,
# hyprctl dispatch's "ok"). Read-only queries still reach the real tool unless a fixture replaces them:
#
#   hyprctl binds|clients|monitors|activewindow|activeworkspace|version|workspaces -j
#                                     SANDBOX_BINDS_JSON, SANDBOX_CLIENTS_JSON, ... (the JSON itself); activewindow
#                                     is {} (no focused window) without its fixture, never the live window;
#                                     SANDBOX_ACTIVEWINDOW_AFTER_WTYPE_JSON replaces it once wtype has been called,
#                                     SANDBOX_ACTIVEWINDOW_AFTER_LAUNCH_JSON once setsid has been (an app started),
#                                     SANDBOX_ACTIVEWINDOW_AFTER_FOCUS_JSON once a focus dispatch has been. With
#                                     SANDBOX_ACTIVEWINDOW_GATE=<path> either flip waits for <path> to exist, and
#                                     each query before that logs "activewindow gated", for a test to wait on
#                                     SANDBOX_SWITCHED_TITLE retitles it once Return has been typed
#                                     SANDBOX_ACTIVEWINDOW_BLOCK_AFTER_WTYPE=<path> makes the first query after wtype
#                                     create <path>.entered and wait for <path>.release
#   wtype                             logged; with SANDBOX_WTYPE_BLOCK=<path> the first call creates <path>.entered and
#                                     waits for <path>.release
#   tesseract                         SANDBOX_TESSERACT_TSV (the tsv itself; no words without it)
#   grim, magick                      never real: grim writes a blank image the size of the activewindow fixture
#                                     times SANDBOX_GRIM_SCALE (default 1), or SANDBOX_GRIM_SIZE ("W H"), and fails
#                                     -T when SANDBOX_GRIM_NO_TOPLEVEL is set; magick cuts empty strips and reports
#                                     a light image (SANDBOX_IMAGE_MEAN, default 1)
#   pw-dump                           SANDBOX_PW_DUMP_JSON
#   keeptabs-pick --json              SANDBOX_AGENTS_JSON
#   systemctl list-timers|list-units  SANDBOX_TIMERS_JSON
#   tmux list-sessions|has-session    SANDBOX_TMUX_SESSIONS (one name per line)
#   hyprctl eval (launcher write_names)  SANDBOX_LAUNCHER_SESSIONS (the Session Launcher's names, one per line)
#   qs-ipc call overview open|close|state|act
#                                     the workspace overview. state prints what $SANDBOX_DIR/overview-state holds
#                                     ("closed" when absent), which open sets to "open" and close to "closed"; act
#                                     answers SANDBOX_OVERVIEW_ACT ("ok" by default). Its snapshot is the test's own
#                                     $XDG_RUNTIME_DIR/voxcmd/overview.json.
#   qs-ipc call tmux_overview state   what $SANDBOX_DIR/tmux_overview-state holds ("closed" when absent)
#   qs-ipc call popup keyboard        what $SANDBOX_DIR/popup-keyboard holds ("no" when absent): "yes" when the open
#                                     popup takes the keyboard, "no" when it is hands-off or none is open
#   qs-ipc call clickhints open|dismiss|state
#                                     the bar's numbered overlay. open logs a "clickhints-open" line holding the
#                                     pending-pick.json it finds and the spec file's JSON, then answers through the
#                                     spec's result FIFO as the bar would. state prints what $SANDBOX_DIR/clickhints-state
#                                     holds ("closed" when absent), which open sets to "open" and dismiss to "closed".
#                                     "qs-ipc call popup state" does the same from $SANDBOX_DIR/popup-state, such as
#                                     "open weather". SANDBOX_POPUP_OPENS=1 makes "popup open <name>", "calendar
#                                     open_day" (clock) and "notifications open" write "open <name>" there, as the bar
#                                     would once the popup is drawn.
#                                       SANDBOX_CLICKHINTS_ANSWER  the line written to the FIFO (a number or a label;
#                                                                  empty is a cancel)
#                                       SANDBOX_CLICKHINTS_OPEN    what open prints, "ok" by default; anything else
#                                                                  is a bar that refused the overlay
#                                       SANDBOX_CLICKHINTS_HOLD=1  open prints ok and nobody answers, as a bar
#                                                                  waiting on the user does
#                                       SANDBOX_CLICKHINTS_BLOCK=<path>  open blocks before answering: it creates
#                                                                  <path>.entered, then waits for <path>.release
#                                       SANDBOX_CLICKHINTS_STATE_BLOCK=<path>  state blocks the same way
#   voxcmd-pick, voxcmd-autostop      voxcmd finds these beside itself, not on PATH, so a test copies the package (with the
#                                     shim, see lib.sh) and symlinks its two onto $SANDBOX_DIR/bin's. voxcmd-pick logs and "picks" the first
#                                     choice's id. voxcmd-autostop gives no verdict (exit 1) unless a voxtype turn is
#                                     being recorded (see below); --check passes unless SANDBOX_AUTOSTOP_OFF holds the
#                                     reason it is off
#   setsid                            logs "setsid owner=$VOXCMD_RECORDING_OWNER_FILE <args>" and starts nothing
#                                     but writes its PID to that owner file, as a watcher would, unless
#                                     SANDBOX_SETSID_RUN=1, which runs the command instead (a voice session's watcher)
#   voxtype record start|stop|cancel  logged. With SANDBOX_VOXTYPE_TURNS (a file of queued turns, one per line) it
#                                     also acts like voxtype: start takes the next turn, sets the state file under
#                                     $XDG_RUNTIME_DIR/voxtype to recording, and a turn that is speech writes itself
#                                     to the --file after SANDBOX_VOXTYPE_SPEAK_SECS (0.4) and goes idle. SILENCE (and
#                                     an empty queue) is no speech, EMPTY is speech that transcribes to nothing, HOLD
#                                     records until stopped or cancelled, FAIL is a start that fails, and
#                                     "GATED <speech>" is spoken only once $SANDBOX_DIR/voxtype-release exists, for a
#                                     test to act while it is heard. "UNTIL_STOP <speech>" records until stopped, and
#                                     the stop writes the speech (a cancel writes nothing), as a long dictation does;
#                                     "CAP <speech>" and "IDLE <speech>" are the same, with the detector giving its
#                                     length-limit (5) or pause (0) verdict. voxcmd-autostop
#                                     then reads the turn from $SANDBOX_DIR/voxtype-turn: SILENCE is its no-speech
#                                     exit (3) after half a second, any other turn waits on `$SANDBOX_AUTOSTOP_SLEEP 30`
#                                     (default sleep; a copy under another name lets a test end leftovers by name).
#                                     The detector with VOXCMD_AUTOSTOP_MAX_SECS=10 on an UNTIL_STOP turn (a chained ending's) waits
#                                     for $SANDBOX_DIR/chain-pause, then gives the pause verdict (0), or exits at once with
#                                     SANDBOX_CHAIN_DETECTOR_EXIT. It logs "threshold_db=<n>" when VOXCMD_AUTOSTOP_THRESHOLD_DB is set,
#                                     and writes SANDBOX_ROOM_THRESHOLD_DB to VOXCMD_AUTOSTOP_THRESHOLD_FILE when both are set.
#   voxtype -q ... transcribe <file>  prints voxtype's progress lines, a blank line and $SANDBOX_TRANSCRIBE_TEXT, as a
#                                     wake confirmation's transcription does (no blank line without it: no speech)
#                                     It logs its VOXCMD_AUTOSTOP_NO_SPEECH_SECS as "autostop no_speech_secs=<n>",
#                                     then "autostop min_speech_secs=<n> silence_secs=<n>" from the matching variables,
#                                     and "max_secs=<n>" when VOXCMD_AUTOSTOP_MAX_SECS is set.
#                                     With VOXCMD_DEBUG set, speech and SILENCE first wait for the watcher to log that it
#                                     sees the recording, and SILENCE then exits at once.
#
# Hyprland's dispatch, eval and keyword are logged and never sent. The eval that asks for monitor slots is answered from
# SANDBOX_MONITOR_SLOTS (the slot lookup's file contents, e.g. "DP-8 HDMI-A-1 - eDP-1"); without it the file stays absent.
#
#   VOXCMD_EXTRA_INTEGRATIONS  colon-separated integration files to load too, e.g. a private one
#   SANDBOX_EXTRA_STUBS        space-separated commands to stub as well, such as the ones an extra integration calls
#   SANDBOX_SHOW_CALLS=1       print the stub call log to stderr when the command ends
#   SANDBOX_STUB_DELAY=<secs>  every stub call first sleeps that long: a slow machine, the same on every run, for
#                              checking that a suite waits on events rather than on time. Keep it under 2: voxcmd
#                              reads the bar's state through `timeout 2`, and a slower bar reads as none
#   SANDBOX_DIR                set for the command: the sandbox root, with the call log at $SANDBOX_DIR/calls.log
#
# HOME, XDG_STATE_HOME and XDG_CACHE_HOME are empty dirs in the sandbox, so the caller's tmuxifier layouts, timers
# and state never change a route.
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
package_dir=$(dirname "$tests_dir")
case "${VOXCMD_BIN:-bash}" in
bash) voxcmd_path_dirs="$tests_dir/bin:$package_dir/.local/bin" ;;
rs)
  # A nested sandbox (run.sh running a sibling suite) has the build already.
  [ -n "${SANDBOX_DIR:-}" ] || cargo build --release --quiet --manifest-path "$package_dir/Cargo.toml" >&2 || exit 1
  voxcmd_path_dirs="$package_dir/target/release"
  ;;
*)
  echo "sandbox: VOXCMD_BIN=$VOXCMD_BIN is not bash or rs" >&2
  exit 2
  ;;
esac
[ "$#" -gt 0 ] || {
  sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0" >&2
  exit 2
}

sandbox_dir=$(mktemp -d "${TMPDIR:-/tmp}/voxcmd-sandbox.XXXXXX")
trap 'rm -rf "$sandbox_dir"' EXIT
stub_dir="$sandbox_dir/bin"
config_home="$sandbox_dir/config"
mkdir -p "$stub_dir" "$config_home/voxcmd/integrations.d" "$config_home/voxcmd/replacements.d" \
  "$config_home/hypr/scripts" "$sandbox_dir/runtime" "$sandbox_dir/home"
chmod 700 "$sandbox_dir/runtime"
: >"$sandbox_dir/calls.log"

# Regular files only: a private dotfiles repo links its own integrations and replacements in here per file, and those
# would change the routes. VOXCMD_EXTRA_INTEGRATIONS loads one on purpose.
find "$package_dir"/.config/voxcmd/integrations.d -maxdepth 1 -type f -name '*.sh' -exec cp -t "$config_home/voxcmd/integrations.d/" {} +
find "$package_dir"/.config/voxcmd/replacements.d -maxdepth 1 -type f ! -name '.*' -exec cp -t "$config_home/voxcmd/replacements.d/" {} +
if [ -n "${VOXCMD_EXTRA_INTEGRATIONS:-}" ]; then
  IFS=: read -ra extra_integrations <<<"$VOXCMD_EXTRA_INTEGRATIONS"
  cp -L "${extra_integrations[@]}" "$config_home/voxcmd/integrations.d/"
fi

# One stub for every command, dispatched on the name it is called by. Passing through restores the real PATH and
# runtime dir, which Hyprland's and PipeWire's sockets live under, and the real HOME.
cat >"$stub_dir/.stub" <<'EOF'
#!/bin/sh
name=${0##*/}
[ -z "${SANDBOX_STUB_DELAY-}" ] || sleep "$SANDBOX_STUB_DELAY"
log() { printf '%s\n' "$name $*" >>"$SANDBOX_DIR/calls.log"; }
# With VOXCMD_DEBUG on, waits until a watcher has logged that it sees the recording the last voxtype record start began,
# so a turn never ends before its watcher's first poll: that watcher would take it for a recording that never started
# and wait out its start grace. It stops waiting once another record start has replaced the recording, whose turn is
# then never heard: a turn left waiting would otherwise speak into a later test's recording. The bound is the suites'
# outer one (VOXCMD_TEST_WAIT_SECS, as in lib.sh), only reached when no watcher comes. Without the debug log there is no
# telling, so it waits $1 seconds.
wait_for_watcher_to_see_recording() {
  if [ -z "${VOXCMD_DEBUG-}" ]; then
    sleep "$1"
    return
  fi
  waited=0 max_polls=$((${VOXCMD_TEST_WAIT_SECS:-120} * 50))
  while [ -d "$SANDBOX_DIR" ] && recording_is_current && [ "$(recordings_watchers_saw)" -le "${recording_mark#* }" ] &&
    [ "$waited" -lt "$max_polls" ]; do
    sleep 0.02
    waited=$((waited + 1))
  done
}
# The recording-mark file holds "<start id> <recordings watchers had seen before it>" for the last record start, and
# $recording_mark the one this stub runs for.
last_recording_mark() { cat "$SANDBOX_DIR/recording-mark" 2>/dev/null || echo "none 0"; }
recording_is_current() { [ "$(last_recording_mark)" = "$recording_mark" ]; }
recordings_watchers_saw() {
  count=$(grep -c 'watch: voxtype recording$' "$XDG_RUNTIME_DIR/voxcmd/debug.log" 2>/dev/null)
  echo "${count:-0}"
}
# fixture_missing <variable>: a stub answered from a fixture the test never set. Failing here keeps the call off the real tool and the live desktop.
fixture_missing() {
  echo "sandbox: '$name $*' needs \$$1, which this test does not set; add the fixture rather than reaching the live desktop" >&2
  exit 1
}
case "$name" in
hyprctl)
  case "${1-}" in
  activewindow)
    # SANDBOX_HYPRCTL_UNREACHABLE: hyprctl holds a dead instance's signature, as a listener that outlived its Hyprland.
    if [ -n "${SANDBOX_HYPRCTL_UNREACHABLE:-}" ]; then
      echo "Couldn't connect to /run/user/1000/hypr/dead/.socket.sock. (4)" >&2
      exit 4
    fi
    if [ -n "${SANDBOX_ACTIVEWINDOW_BLOCK_AFTER_WTYPE:-}" ] && [ ! -e "$SANDBOX_ACTIVEWINDOW_BLOCK_AFTER_WTYPE.entered" ] &&
      grep -q '^wtype ' "$SANDBOX_DIR/calls.log" 2>/dev/null; then
      : >"$SANDBOX_ACTIVEWINDOW_BLOCK_AFTER_WTYPE.entered"
      until [ -e "$SANDBOX_ACTIVEWINDOW_BLOCK_AFTER_WTYPE.release" ]; do sleep 0.02; done
    fi
    # SANDBOX_ACTIVEWINDOW_AFTER_WTYPE_JSON: the window that has focus once anything has been typed.
    # SANDBOX_SWITCHED_TITLE: the tab title Firefox's window shows once Return has been typed, as after a tab switch.
    flipped=
    if [ -n "${SANDBOX_ACTIVEWINDOW_AFTER_LAUNCH_JSON:-}" ] && grep -q '^setsid ' "$SANDBOX_DIR/calls.log" 2>/dev/null; then
      flipped=SANDBOX_ACTIVEWINDOW_AFTER_LAUNCH_JSON
    elif [ -n "${SANDBOX_ACTIVEWINDOW_AFTER_FOCUS_JSON:-}" ] && grep -q '^hyprctl dispatch hl.dsp.focus' "$SANDBOX_DIR/calls.log" 2>/dev/null; then
      flipped=SANDBOX_ACTIVEWINDOW_AFTER_FOCUS_JSON
    fi
    if [ -n "$flipped" ] && [ -n "${SANDBOX_ACTIVEWINDOW_GATE:-}" ] && [ ! -e "$SANDBOX_ACTIVEWINDOW_GATE" ]; then
      echo "activewindow gated" >>"$SANDBOX_DIR/calls.log"
      flipped=
    fi
    if [ -n "$flipped" ]; then
      printenv "$flipped"
    elif [ -n "${SANDBOX_ACTIVEWINDOW_AFTER_WTYPE_JSON:-}" ] && grep -q '^wtype ' "$SANDBOX_DIR/calls.log" 2>/dev/null; then
      printenv SANDBOX_ACTIVEWINDOW_AFTER_WTYPE_JSON
    elif [ -n "${SANDBOX_SWITCHED_TITLE:-}" ] && grep -q '^wtype -k Return' "$SANDBOX_DIR/calls.log" 2>/dev/null; then
      jq -c --arg title "$SANDBOX_SWITCHED_TITLE — Mozilla Firefox" '.title = $title' <<<"${SANDBOX_ACTIVEWINDOW_JSON:-{\}}"
    else
      printenv SANDBOX_ACTIVEWINDOW_JSON || echo '{}'
    fi
    ;;
  binds | clients | monitors | activeworkspace | version)
    fixture_var="SANDBOX_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')_JSON"
    printenv "$fixture_var" || fixture_missing "$fixture_var"
    ;;
  workspaces)
    # Without its fixture no special workspace exists, rather than the live session's.
    printenv SANDBOX_WORKSPACES_JSON || echo '[]'
    ;;
  eval)
    log "$@"
    # SANDBOX_MONITOR_SLOTS: what Hyprland's slot lookup writes to the file the eval names, e.g. "DP-8 HDMI-A-1 - eDP-1".
    slots_file=$(printf '%s' "${2-}" | sed -n "s/.*io\.open('\([^']*\)', 'w').*/\1/p")
    [ -z "${SANDBOX_MONITOR_SLOTS+x}" ] || [ -z "$slots_file" ] || printf '%s' "$SANDBOX_MONITOR_SLOTS" >"$slots_file"
    # The Session Launcher's names, which Hyprland's Lua writes to the file the eval names.
    case "${2-}" in
    *write_names*)
      names_file=${2#*write_names\(\'}
      jq -R -s -c 'split("\n") | map(select(. != ""))' <<<"${SANDBOX_LAUNCHER_SESSIONS-}" >"${names_file%%\'*}"
      ;;
    esac
    echo ok
    ;;
  dispatch | keyword) log "$@" && echo ok ;;
  *) log "$@" ;;
  esac
  ;;
grim)
  log "$@"
  for out; do :; done
  # SANDBOX_GRIM_NO_TOPLEVEL fails the per-window capture (-T), as on a compositor without it.
  for arg; do [ "$arg" != -T ] || [ -z "${SANDBOX_GRIM_NO_TOPLEVEL-}" ] || exit 1; done
  scale=${SANDBOX_GRIM_SCALE:-1}
  size=${SANDBOX_GRIM_SIZE-}
  [ -n "$size" ] || size=$(printenv SANDBOX_ACTIVEWINDOW_JSON | jq -r --argjson scale "$scale" 'if .size then "\(.size[0] * $scale | round) \(.size[1] * $scale | round)" else empty end') || exit 1
  [ -n "$size" ] || exit 1
  set -- $size
  { printf 'P6\n%s %s\n255\n' "$1" "$2"; head -c $(($1 * $2 * 3)) /dev/zero; } >"$out"
  ;;
tesseract)
  # An image piped in is drained, so the inverting magick upstream never sees a broken pipe.
  [ "${1-}" != - ] || cat >/dev/null
  printenv SANDBOX_TESSERACT_TSV || :
  ;;
magick)
  # The strips are named by -write; the one -write to info:- is the mean luminance.
  previous=
  for arg; do
    if [ "$previous" = -write ]; then
      case "$arg" in
      info:-) echo "${SANDBOX_IMAGE_MEAN:-1}" ;;
      *) : >"$arg" ;;
      esac
    fi
    previous=$arg
  done
  ;;
pw-dump) printenv SANDBOX_PW_DUMP_JSON || fixture_missing SANDBOX_PW_DUMP_JSON ;;
keeptabs-pick)
  case "$*" in
  *--json*) printenv SANDBOX_AGENTS_JSON || fixture_missing SANDBOX_AGENTS_JSON ;;
  *) log "$@" ;;
  esac
  ;;
systemctl)
  case "$*" in
  *list-timers* | *list-units*) printenv SANDBOX_TIMERS_JSON || fixture_missing SANDBOX_TIMERS_JSON ;;
  *) log "$@" ;;
  esac
  ;;
tmux)
  case "${1-}" in
  list-sessions) printenv SANDBOX_TMUX_SESSIONS || fixture_missing SANDBOX_TMUX_SESSIONS ;;
  has-session)
    [ -n "${SANDBOX_TMUX_SESSIONS+set}" ] || fixture_missing SANDBOX_TMUX_SESSIONS
    eval "session=\${$#}"
    printf '%s\n' "$SANDBOX_TMUX_SESSIONS" | grep -qxF -- "${session#=}"
    ;;
  *) log "$@" ;;
  esac
  ;;
qs-ipc)
  log "$@"
  if [ -n "${SANDBOX_POPUP_OPENS-}" ]; then
    case "$*" in
    *"call popup open "*) echo "open $4" >"$SANDBOX_DIR/popup-state" ;;
    *"call calendar open_day"*) echo "open clock" >"$SANDBOX_DIR/popup-state" ;;
    *"call notifications open"*) echo "open notifications" >"$SANDBOX_DIR/popup-state" ;;
    esac
  fi
  case "$*" in
  *get_dnd*) echo false ;;
  *"call clickhints open"*)
    if [ "${SANDBOX_CLICKHINTS_OPEN:-ok}" != ok ]; then
      echo "$SANDBOX_CLICKHINTS_OPEN"
      exit 0
    fi
    if [ -n "${SANDBOX_CLICKHINTS_BLOCK-}" ]; then
      : >"$SANDBOX_CLICKHINTS_BLOCK.entered"
      until [ -e "$SANDBOX_CLICKHINTS_BLOCK.release" ]; do sleep 0.02; done
    fi
    printf 'clickhints-open %s\n' "$(jq -c '{pending_kind: ., spec: input}' "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json" "$4")" >>"$SANDBOX_DIR/calls.log"
    echo open >"$SANDBOX_DIR/clickhints-state"
    if [ -z "${SANDBOX_CLICKHINTS_HOLD-}" ]; then
      fifo=$(jq -r .result_path "$4")
      (printf '%s\n' "${SANDBOX_CLICKHINTS_ANSWER-}" >"$fifo") >/dev/null 2>&1 &
    fi
    echo ok
    ;;
  *"call clickhints dismiss"*) echo closed >"$SANDBOX_DIR/clickhints-state" ;;
  *"call clickhints state"*)
    if [ -n "${SANDBOX_CLICKHINTS_STATE_BLOCK-}" ]; then
      : >"$SANDBOX_CLICKHINTS_STATE_BLOCK.entered"
      until [ -e "$SANDBOX_CLICKHINTS_STATE_BLOCK.release" ]; do sleep 0.02; done
    fi
    cat "$SANDBOX_DIR/clickhints-state" 2>/dev/null || echo closed ;;
  *"call popup state"*) cat "$SANDBOX_DIR/popup-state" 2>/dev/null || echo closed ;;
  *"call popup keyboard"*) cat "$SANDBOX_DIR/popup-keyboard" 2>/dev/null || echo no ;;
  *"call overview open"*)
    echo open >"$SANDBOX_DIR/overview-state"
    echo ok
    ;;
  *"call overview close"*)
    echo closed >"$SANDBOX_DIR/overview-state"
    echo ok
    ;;
  *"call overview state"*) cat "$SANDBOX_DIR/overview-state" 2>/dev/null || echo closed ;;
  *"call overview act"*) echo "${SANDBOX_OVERVIEW_ACT:-ok}" ;;
  *"call tmux_overview state"*) cat "$SANDBOX_DIR/tmux_overview-state" 2>/dev/null || echo closed ;;
  *"confirm ask"* | *"sound play"*) echo ok ;;
  esac
  ;;
wpctl)
  log "$@"
  [ "${1-}" != get-volume ] || echo 'Volume: 0.50'
  ;;
pamixer)
  log "$@"
  case "$*" in
  *--get-volume*) echo 50 ;;
  *--get-mute*) echo false ;;
  esac
  ;;
brightnessctl)
  log "$@"
  [ "${1-}" != -m ] || echo 'sandbox,backlight,50,50%,100'
  ;;
wtype)
  log "$@"
  # SANDBOX_WTYPE_BLOCK=<path>: the first call creates <path>.entered and waits for <path>.release.
  if [ -n "${SANDBOX_WTYPE_BLOCK:-}" ] && [ ! -e "$SANDBOX_WTYPE_BLOCK.entered" ]; then
    : >"$SANDBOX_WTYPE_BLOCK.entered"
    until [ -e "$SANDBOX_WTYPE_BLOCK.release" ]; do sleep 0.02; done
  fi
  ;;
voxcmd-pick)
  log "$@"
  for last; do :; done
  printf '%s\n' "$last" | jq -r '.[0].id'
  ;;
voxcmd-autostop)
  if [ "${1-}" = --check ]; then
    [ -z "${SANDBOX_AUTOSTOP_OFF-}" ] || { echo "$SANDBOX_AUTOSTOP_OFF"; exit 1; }
    exit 0
  fi
  [ -e "$SANDBOX_DIR/voxtype-turn" ] || exit 1
  log "no_speech_secs=${VOXCMD_AUTOSTOP_NO_SPEECH_SECS:-default}"
  log "min_speech_secs=${VOXCMD_AUTOSTOP_MIN_SPEECH_SECS:-default} silence_secs=${VOXCMD_AUTOSTOP_SILENCE_SECS:-default}"
  [ -z "${VOXCMD_AUTOSTOP_MAX_SECS-}" ] || log "max_secs=$VOXCMD_AUTOSTOP_MAX_SECS"
  [ -z "${VOXCMD_AUTOSTOP_THRESHOLD_DB-}" ] || log "threshold_db=$VOXCMD_AUTOSTOP_THRESHOLD_DB"
  # The room threshold a watcher's detector measures, as the real one writes it.
  [ -z "${VOXCMD_AUTOSTOP_THRESHOLD_FILE-}" ] || [ -z "${SANDBOX_ROOM_THRESHOLD_DB-}" ] ||
    echo "$SANDBOX_ROOM_THRESHOLD_DB" >"$VOXCMD_AUTOSTOP_THRESHOLD_FILE"
  turn=$(cat "$SANDBOX_DIR/voxtype-turn")
  # The pause detector of a chained ending (max_secs=10, which type mode's own detector never has) hears its pause once
  # $SANDBOX_DIR/chain-pause exists, and gives up when the recording is over.
  if [ "${VOXCMD_AUTOSTOP_MAX_SECS-}" = 10 ] && [ "${turn#UNTIL_STOP }" != "$turn" ]; then
    [ -z "${SANDBOX_CHAIN_DETECTOR_EXIT-}" ] || exit "$SANDBOX_CHAIN_DETECTOR_EXIT"
    until [ -e "$SANDBOX_DIR/chain-pause" ]; do
      [ "$(cat "$XDG_RUNTIME_DIR/voxtype/state" 2>/dev/null)" = recording ] || exit 4
      sleep 0.05
    done
    exit 0
  fi
  case "$turn" in
  SILENCE | "CAP "* | "IDLE "*)
    recording_mark=$(last_recording_mark)
    wait_for_watcher_to_see_recording 0.5
    case "$turn" in
    SILENCE) exit 3 ;;
    CAP*) exit 5 ;;
    *) exit 0 ;;
    esac
    ;;
  esac
  exec "${SANDBOX_AUTOSTOP_SLEEP:-sleep}" 30
  ;;
setsid)
  log "owner=${VOXCMD_RECORDING_OWNER_FILE-} $*"
  [ -z "${SANDBOX_SETSID_RUN-}" ] || exec "$@"
  # A watcher's first step, so a picker waiting for its reply recording's owner finds one.
  [ -z "${VOXCMD_RECORDING_OWNER_FILE-}" ] || echo $$ >"$VOXCMD_RECORDING_OWNER_FILE"
  ;;
voxtype)
  log "$@"
  if [ "${1-}" = -q ]; then
    for transcribed; do :; done
    printf 'Loading audio file: "%s"\n' "$transcribed"
    [ -z "${SANDBOX_TRANSCRIBE_TEXT-}" ] || printf '\n%s\n' "$SANDBOX_TRANSCRIBE_TEXT"
    exit 0
  fi
  [ -n "${SANDBOX_VOXTYPE_TURNS-}" ] || exit 0
  state_file=$XDG_RUNTIME_DIR/voxtype/state
  # A turn that is spoken when it is stopped: the --file and the speech.
  until_stop=$SANDBOX_DIR/voxtype-until-stop
  case "${1-} ${2-}" in
  "record start")
    file=${3#--file=}
    turn=$(head -n 1 "$SANDBOX_VOXTYPE_TURNS")
    sed -i 1d "$SANDBOX_VOXTYPE_TURNS"
    [ -n "$turn" ] || turn=SILENCE
    [ "$turn" != FAIL ] || exit 1
    echo "$turn" >"$SANDBOX_DIR/voxtype-turn"
    recording_mark="$(date +%s%N) $(recordings_watchers_saw)"
    echo "$recording_mark" >"$SANDBOX_DIR/recording-mark"
    echo recording >"$state_file"
    rm -f "$until_stop"
    case "$turn" in
    "UNTIL_STOP "* | "CAP "* | "IDLE "*)
      printf '%s\n%s' "$file" "${turn#* }" >"$until_stop"
      turn=HOLD
      ;;
    esac
    if [ "$turn" != SILENCE ] && [ "$turn" != HOLD ]; then
      (
        wait_for_watcher_to_see_recording 0
        recording_is_current || exit 0
        if [ "${turn#GATED }" != "$turn" ]; then
          turn=${turn#GATED }
          # A recording cancelled (or a sandbox removed) before the release would never be written anyway; stop waiting.
          until [ -e "$SANDBOX_DIR/voxtype-release" ]; do
            [ -d "$SANDBOX_DIR" ] && [ "$(cat "$state_file" 2>/dev/null)" = recording ] || exit 0
            sleep 0.02
          done
        fi
        sleep "${SANDBOX_VOXTYPE_SPEAK_SECS:-0.4}"
        if [ "$(cat "$state_file")" = recording ] && recording_is_current; then
          [ "$turn" = EMPTY ] || printf '%s' "$turn" >"$file"
          echo idle >"$state_file"
        fi
      ) >/dev/null 2>&1 &
    fi
    ;;
  "record stop")
    if [ -e "$until_stop" ] && [ "$(cat "$state_file")" = recording ]; then
      tail -n +2 "$until_stop" >"$(head -n 1 "$until_stop")"
    fi
    rm -f "$until_stop"
    echo idle >"$state_file"
    ;;
  "record cancel")
    rm -f "$until_stop"
    echo idle >"$state_file"
    ;;
  esac
  ;;
xdg-mime)
  log "$@"
  # SANDBOX_DEFAULT_BROWSER: the desktop file id "query default" answers for any type (none without it).
  [ "${1-}" != query ] || printenv SANDBOX_DEFAULT_BROWSER || true
  ;;
powerprofilesctl)
  log "$@"
  case "${1-}" in
  list) printf '  performance:\n* balanced:\n  power-saver:\n' ;;
  get) echo balanced ;;
  esac
  ;;
*) log "$@" ;;
esac
EOF
chmod +x "$stub_dir/.stub"

# Called by name from PATH. hyprctl, pw-dump, keeptabs-pick, systemctl and tmux also answer read-only queries; grim,
# tesseract and magick answer from the fixtures above and never touch the screen.
stubbed_commands=(
  hyprctl pw-dump keeptabs-pick systemctl tmux
  systemd-run notify-send pamixer wpctl bluetoothctl playerctl brightnessctl powerprofilesctl
  grim tesseract magick wlrctl wl-kbptr wtype wl-copy voxtype wf-recorder xdg-open setsid rofi qs-ipc firefox xdg-mime
  voxcmd-pick voxcmd-autostop
)
read -ra extra_stubs <<<"${SANDBOX_EXTRA_STUBS:-}"
for command_name in "${stubbed_commands[@]}" "${extra_stubs[@]}"; do ln -s .stub "$stub_dir/$command_name"; done
# Called by path, under $XDG_CONFIG_HOME/hypr/scripts.
for script_name in qs-ipc qs-picker screenshot.sh toggle-autolock.sh rofi-tmux.sh; do
  ln -s "$stub_dir/.stub" "$config_home/hypr/scripts/$script_name"
done

export SANDBOX_DIR="$sandbox_dir"
export SANDBOX_REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export HOME="$sandbox_dir/home"
export XDG_STATE_HOME="$sandbox_dir/home/.local/state"
export XDG_CACHE_HOME="$sandbox_dir/home/.cache"
export PATH="$stub_dir:$voxcmd_path_dirs:$PATH"
export XDG_RUNTIME_DIR="$sandbox_dir/runtime"
export XDG_CONFIG_HOME="$config_home"
export VOXCMD_CONFIG_DIR="$config_home/voxcmd"
# A picker or confirm card has no bar to answer it here, so it gives up quickly.
export VOXCMD_PICK_TIMEOUT="${VOXCMD_PICK_TIMEOUT:-2}"
export VOXCMD_CONFIRM_TIMEOUT="${VOXCMD_CONFIRM_TIMEOUT:-2}"
unset VOXCMD_LLM_CMD

status=0
"$@" || status=$?
if [ "${SANDBOX_SHOW_CALLS:-}" = 1 ]; then
  printf '\n== stub calls\n' >&2
  cat "$sandbox_dir/calls.log" >&2
fi
exit "$status"
