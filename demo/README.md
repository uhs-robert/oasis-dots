# Showcase video kit

A scripted take for the README video: `showcase.sh` drives the real desktop, and a standalone overlay (`overlay/`, run with `qs -p`) shows each keybind as key caps before it fires. It is separate from the live bar and never loaded by it. Run everything from a terminal on another output than `DEMO_OUTPUT` (default: the landscape 1920x1080 output, so nothing is scaled; set it to a connector name to choose); the script refuses to type into that terminal or to start while it sits on the output.

Needs `hyprctl`, `jq`, `wtype`, `qs`, `tmux`, `grim`, `python3` with PIL, plus `wf-recorder`, `ffmpeg` and `pactl` to record. Plug in first: style transitions and the keeptabs pulse are skipped on battery, so the script aborts there.

## The stage

The video opens on an empty `DEMO_OUTPUT` and launches a session named "Demo" from the session picker. That session is personal config, not part of this repo: add it in your `custom/sessions.lua` with the editor and the repo page on the output's first workspace, the agent on its second, and three app windows on its fifth for the `:layout` beat:

```lua
local demo_stage = os.getenv("HOME") .. "/dotfiles/demo/stage-tmux.sh"
Sessions.add("🌵 Demo", {
  Sessions.term({ monitor = 2, ws = 1, exec = demo_stage .. " dotfiles", class_suffix = "tmux-dotfiles" }),
  { monitor = 2, ws = 1, cmd = "firefox --private-window https://github.com/uhs-robert/oasis-dots", class = "firefox", delay = 1500 },
  Sessions.term({ monitor = 2, ws = 2, exec = demo_stage .. " agent", class_suffix = "tmux-agent", delay = 3000 }),
  Sessions.term({ monitor = 2, ws = 5, exec = demo_stage .. " monitor", class_suffix = "tmux-monitor", delay = 3500 }),
  Sessions.term({ monitor = 2, ws = 5, exec = demo_stage .. " git", class_suffix = "tmux-git", delay = 4000 }),
  Sessions.term({ monitor = 2, ws = 5, exec = demo_stage .. " readme", class_suffix = "tmux-readme", delay = 4500 }),
})
```

`stage-tmux.sh` builds the tmux sessions in this repo: `dotfiles` (Neovim's dashboard beside yazi on `home/`), `agent` (Claude Code on Sonnet, `DEMO_AGENT_CMD`), and `monitor` (btop), `git` (lazygit) and `readme` (glow). Their names are also the kitty titles, which the overview beat searches for.

## Usage

```sh
demo/showcase.sh list               # beat names
demo/showcase.sh stage              # weather, DND, Moonlight with Sync Neovim, follow-style sounds, a pinned wallpaper, Neovim style, overlay
demo/showcase.sh beat palettes      # rehearse one beat, with its off-camera setup
demo/showcase.sh all                # every beat, no recording
demo/showcase.sh record             # stage, one clip per beat into ~/Videos/Recordings/showcase-<time>/, restore, edit
demo/showcase.sh edit <dir>         # cut a recording folder's clips into showcase.mp4
demo/showcase.sh hero <dir>         # the README hero (palettes, the turn and the styles beat) as hero.webp
demo/showcase.sh restore            # put back style, palette, Sync Neovim, DND, sounds, weather and the wallpaper rotator
demo/showcase.sh reset              # end the stage's tmux sessions and close its windows
demo/showcase.sh --dry-run record   # print every step without running it
```

Beats after `session` expect its windows, and `keeptabs` waits for the agent that `kickoff` started. Rehearse a beat on its own, then `restore` and `reset` to start the take from an empty output.

The region beat finds the dashboard logo in a screenshot of the output and steers the selector onto its exact edges (`DEMO_REGION_RECT="x y w h"` overrides the detection; the screenshot is kept in `$XDG_RUNTIME_DIR/oasis-demo/`).

Each clip is filmed with the default sink's monitor as audio (`DEMO_AUDIO=none` for silence). `edit` speeds up the app start-up in the `session` clip and joins the rest with hard cuts, so one bad beat can be re-filmed alone and the folder edited again.

## Tuning

Everything is an environment variable with a default at the top of the script: `DEMO_OUTPUT`, `DEMO_PASSWORD` (letters only, no `q`), `DEMO_FPS`, `DEMO_OUT_DIR`, `DEMO_AUDIO`, `DEMO_LOCATION`, `DEMO_SESSION_QUERY`, `DEMO_SEARCH_TEXT`, `DEMO_AGENT_PROMPT`, `DEMO_START_STYLE`, `DEMO_PALETTES`, `DEMO_STYLES` (`id:filter` pairs), `DEMO_WALLPAPER` (one image for the whole take; empty pins whatever the output shows at `stage`), `DEMO_FAST_MAX`, and one `T_*` variable per delay, for example `T_SURFACE_HOLD=2 demo/showcase.sh beat styles`.

The protected terminal is `DEMO_PROTECT_PID` (default `$KITTY_PID`). kitty shares one pid across its windows, so only the stage's own terminals (`kitty-tmux-dotfiles`, `kitty-tmux-agent`) are excluded, by class, and `DEMO_PROTECT_ADDR` pins exact window addresses.
