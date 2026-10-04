#!/usr/bin/env bash

export NEWT_COLORS='root=,black window=white,black border=brown,black title=red,black textbox=white,black label=white,black entry=red,black disentry=gray,black button=black,cyan actbutton=black,cyan compactbutton=green,black listbox=white,black actlistbox=red,black sellistbox=white,green actsellistbox=black,cyan checkbox=white,black actcheckbox=black,cyan emptyscale=gray,black fullscale=black,green helpline=green,black roottext=green,black'

CMD="nmtui"

for arg in "$@"; do
  case "$arg" in
    --connect) CMD="nmtui-connect" ;;
  esac
done

term=~/.local/state/hypr/bin/term
[ -x "$term" ] || term="${TERMINAL:-kitty}"
exec "$term" -e "$CMD"
