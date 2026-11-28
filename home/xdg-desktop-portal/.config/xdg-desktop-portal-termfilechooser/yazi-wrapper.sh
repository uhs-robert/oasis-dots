#!/usr/bin/env sh
# This wrapper script is invoked by xdg-desktop-portal-termfilechooser.
#
# For more information about input/output arguments read `xdg-desktop-portal-termfilechooser(5)`

set -e

if [ "${6:-0}" -ge 4 ]; then
  set -x
fi

multiple="$1"
directory="$2"
save="$3"
path="$4"
out="$5"

cmd="yazi"
termcmd="${TERMCMD:-kitty --title 'termfilechooser'}"

if [ "$save" = "1" ]; then
  # save a file
  set -- --chooser-file="$out" "$path"
elif [ "$directory" = "1" ]; then
  # upload files from a directory
  set -- --chooser-file="$out" --cwd-file="$out"".1" "$path"
elif [ "$multiple" = "1" ]; then
  # upload multiple files
  set -- --chooser-file="$out" "$path"
else
  # upload only 1 file
  set -- --chooser-file="$out" "$path"
fi

# The arguments reach the terminal as positionals, so a path is never parsed as shell code. Only TERMCMD is parsed.
# Ghostty 1.2.0 and later also takes `-e` arguments as a plain argv; older releases joined them and re-parsed them.
sh -c "$termcmd \"\$@\"" sh "$cmd" "$@"

if [ "$directory" = "1" ]; then
  if [ ! -s "$out" ] && [ -s "$out"".1" ]; then
    cat "$out"".1" >"$out"
    rm -f "$out"".1"
  else
    rm -f "$out"".1"
  fi
fi
