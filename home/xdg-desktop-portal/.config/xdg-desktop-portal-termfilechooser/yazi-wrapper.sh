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

# Ghostty parses its arguments through a shell again, so for it each argument gets one more layer of quoting.
single_quote() {
  # The trailing x keeps $(...) from dropping a newline that ends the argument.
  quoted=$(
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
    printf x
  )
  printf "'%s'" "${quoted%x}"
}

case "$termcmd" in
*"ghostty"*)
  for arg in "$@"; do
    set -- "$@" "$(single_quote "$arg")"
    shift
  done
  ;;
esac

# The arguments reach the terminal as positionals, so a path is never parsed as shell code. Only TERMCMD is parsed.
sh -c "$termcmd \"\$@\"" sh "$cmd" "$@"

if [ "$directory" = "1" ]; then
  if [ ! -s "$out" ] && [ -s "$out"".1" ]; then
    cat "$out"".1" >"$out"
    rm -f "$out"".1"
  else
    rm -f "$out"".1"
  fi
fi
