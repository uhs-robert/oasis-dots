#!/usr/bin/env bash

export NEWT_COLORS='root=,black window=white,black border=brown,black title=red,black textbox=white,black label=white,black entry=red,black disentry=gray,black button=black,cyan actbutton=black,cyan compactbutton=green,black listbox=white,black actlistbox=red,black sellistbox=white,green actsellistbox=black,cyan checkbox=white,black actcheckbox=black,cyan emptyscale=gray,black fullscale=black,green helpline=green,black roottext=green,black'

if [[ "$1" == "--waybar" ]]; then
  exec foot --app-id waybar-nmtui -e nmtui
else
  exec foot -e nmtui "$@"
fi
