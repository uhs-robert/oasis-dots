#!/bin/sh
# Write the command that reopens a kitty OS window (cwd and foreground program) to a file.
# Usage: kitty-window-cmd.sh <kitty_pid> <class> <title> <focused:0|1> <base_cmd> <out_file>
pid=$1 class=$2 title=$3 focused=$4 base=$5 out=$6

mkdir -p "$(dirname "$out")"
timeout 2 kitty @ --to "unix:$XDG_RUNTIME_DIR/kitty-$pid" ls 2>/dev/null |
  jq -r --arg class "$class" --arg title "$title" --arg focused "$focused" --arg base "$base" --arg shell "${SHELL:-/bin/sh}" '
    def is_shell: length == 1 and (.[0] | test("(^|[/-])(zsh|bash|fish|sh)$"));
    [.[] | select(.wm_class == $class) | .is_focused as $os_focused
      | .tabs[] | select(.is_active) | .windows[] | select(.is_active) | . + {os_focused: $os_focused}] as $all
    | (if $focused == "1" then $all | map(select(.os_focused)) | first else null end)
      // ($all | map(select(.title == $title)) | if length == 1 then first else null end)
      // ($all | if length == 1 then first else null end)
    | select(. != null)
    | ((.foreground_processes // []) | min_by(.pid)) as $fg
    | (if (.cmdline | is_shell | not) then " -e " + (.cmdline | @sh)
       elif $fg == null or ($fg.cmdline | is_shell) then ""
       else " -e " + ([$shell, "-ic", (($fg.cmdline | @sh) + "; exec " + $shell)] | @sh)
       end) as $run
    | "cd " + (($fg.cwd // .cwd) | @sh) + " && " + $base + $run
  ' >"$out" 2>/dev/null
