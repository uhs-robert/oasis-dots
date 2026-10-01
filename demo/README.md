# Showcase video kit

A scripted take for the README video: `showcase.sh` drives the real desktop, and a standalone overlay (`overlay/`, run with `qs -p`) shows each keybind as key caps before it fires. It is separate from the live bar and never loaded by it. Run everything from a terminal on another output than `DEMO_OUTPUT` (default `HDMI-A-1`); the script refuses to type into that terminal.

Needs `hyprctl`, `jq`, `wtype`, `qs`, `tmux`, plus `wf-recorder` and `ffmpeg` to record. Plug in first: style transitions are skipped on battery, so the script aborts there.

## Usage

```sh
demo/showcase.sh stage              # focus the output, style oasis, spoof weather, add a tmux claude window, reset the region zoom
demo/showcase.sh list               # scene names
demo/showcase.sh scene overview     # rehearse one scene (same as `just demo-scene overview`)
demo/showcase.sh all                # every scene, no recording
demo/showcase.sh record             # stage, record, run all scenes, encode to ~/Videos/Recordings (`just demo-record`)
demo/showcase.sh restore            # undo stage and close anything left open
demo/showcase.sh reset              # close the windows the work scene opened, then restore
demo/showcase.sh --dry-run all      # print every step without running it
```

Scenes after `work` expect its windows. Run `work` once, rehearse the rest, then `reset` to start the take from a clean desktop.

## Tuning

Everything is an environment variable with a default at the top of the script: `DEMO_OUTPUT`, `DEMO_PASSWORD` (letters only, no `q`), `DEMO_FPS`, `DEMO_OUT_DIR`, `DEMO_LOCATION`, `DEMO_SEARCH_TEXT`, `DEMO_WEATHER_FILE`, and one `T_*` variable per delay, for example `T_STYLE_HOLD=2 demo/showcase.sh scene styles`.

`reset` closes windows by address and never touches the protected terminal (`DEMO_PROTECT_PID`, default `$KITTY_PID`). Firefox is also terminated; `DEMO_RESET_KILL=1` terminates every closed app, and `DEMO_RESET_TMUX_SERVER=1` kills the tmux server unless the terminal is inside tmux.
