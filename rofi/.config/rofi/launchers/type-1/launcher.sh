#!/usr/bin/env bash
# rofi/.config/rofi/launchers/type-1/launcher.sh

## Author : Robert Hill (uhs-robert)
## Github : @uhs-robert
#
## Rofi   : Launcher (Modi Drun, Run, File Browser, Window)
#
## Usage:
#   launcher.sh [-s STYLE] [-d DIR] [-m MODE] [-n NAME] [-- ARGS...]
#   launcher.sh -l|--list
#
## Available Styles
#
## style-1     style-2     style-3     style-4     style-5
## style-6     style-7     style-8     style-9     style-10
## style-11    style-12    style-13    style-14    style-15

set -euo pipefail

dir="$HOME/.config/rofi/launchers/type-1"
style="${1:-style-7}" # Default style
# style="${1:-style-7}" # Sidebar
# style="${1:-style-7}" # 2nd favorite

# If they pass just a number, treat it as style-N
if [[ "$style" =~ ^[0-9]+$ ]]; then
  style="style-$style"
fi

## Run
rofi \
  -show drun \
  -theme ${dir}/${style}.rasi
