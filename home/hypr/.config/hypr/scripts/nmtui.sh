#!/usr/bin/env bash

export NEWT_COLORS='root=,black window=white,black border=brown,black title=red,black textbox=white,black label=white,black entry=red,black disentry=gray,black button=black,cyan actbutton=black,cyan compactbutton=green,black listbox=white,black actlistbox=red,black sellistbox=white,green actsellistbox=black,cyan checkbox=white,black actcheckbox=black,cyan emptyscale=gray,black fullscale=black,green helpline=green,black roottext=green,black'

FOOT_ARGS=()
CMD="nmtui"

for arg in "$@"; do
  case "$arg" in
    --waybar)  FOOT_ARGS+=(--app-id waybar-nmtui) ;;
    --connect) CMD="nmtui-connect" ;;
  esac
done

exec foot "${FOOT_ARGS[@]}" -e "$CMD"
