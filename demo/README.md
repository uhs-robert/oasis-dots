# Showcase video kit

A scripted take for the README video: `showcase.sh` drives the real desktop, and a standalone overlay (`overlay/`, run with `qs -p`) shows each keybind as key caps before it fires. It is separate from the live bar and never loaded by it. Run everything from a terminal on another output than `DEMO_OUTPUT` (default: the landscape 1920x1080 output, so nothing is scaled; set it to a connector name to choose); the script refuses to type into that terminal or to start while it sits on the output.

Needs `hyprctl`, `jq`, `wtype`, `qs`, `tmux`, `grim`, `python3` with PIL, plus `wf-recorder`, `ffmpeg` and `pactl` to record. Plug in first: style transitions and the keeptabs pulse are skipped on battery, so the script aborts there.

## The stage

The video opens on an empty `DEMO_OUTPUT` and launches a session named "Demo" from the session picker. That session is personal config, not part of this repo: add it in your `custom/sessions.lua` with Neovim beside yazi on the output's first workspace, the agent on its second, btop and lazygit on its third, and the repo page on its fifth (the overview beat carries the two onto it for the `:layout` beat):

```lua
local demo_stage = os.getenv("HOME") .. "/dotfiles/demo/stage-tmux.sh"
local function demo_term(ws, session, delay)
  return Sessions.term({ monitor = 2, ws = ws, exec = demo_stage .. " " .. session, class_suffix = "tmux-" .. session, delay = delay })
end
Sessions.add("🌵 Demo", {
  demo_term(1, "dotfiles"),
  demo_term(1, "files", 1000),
  demo_term(2, "agent", 1500),
  demo_term(3, "monitor", 2000),
  demo_term(3, "git", 2500),
  { monitor = 2, ws = 5, cmd = "firefox --private-window https://github.com/uhs-robert/oasis-dots", class = "firefox", delay = 3000 },
})
```

`stage-tmux.sh` builds one-pane tmux sessions in this repo: `dotfiles` (Neovim's dashboard), `files` (yazi on `home/`), `agent` (Claude Code on Sonnet, `DEMO_AGENT_CMD`), `monitor` (btop) and `git` (lazygit). Their names are also the kitty titles, which the overview beat searches for.

## Usage

```sh
demo/showcase.sh list               # beat names
demo/showcase.sh stage              # weather, DND, Moonlight with Sync Neovim, follow-style sounds, a pinned wallpaper, Neovim style, overlay
demo/showcase.sh beat palettes      # rehearse one beat, with its off-camera setup
demo/showcase.sh all                # every beat, no recording
demo/showcase.sh record             # stage, one continuous take into ~/Videos/Recordings/showcase-<time>/, restore, edit
demo/showcase.sh edit <dir>         # loudness-normalise the take into showcase.mp4
demo/showcase.sh hero <dir> [s-e ...] # the README hero as hero.webp: palettes through styles, or the given second ranges
demo/showcase.sh restore            # put back style, palette, Sync Neovim, DND, sounds, weather and the wallpaper rotator
demo/showcase.sh reset              # end the stage's tmux sessions and close its windows
demo/showcase.sh --dry-run record   # print every step without running it
```

Beats after `session` expect its windows, and `keeptabs` waits for the agent that `kickoff` started. Rehearse a beat on its own, then `restore` and `reset` to start the take from an empty output.

The region beat finds the dashboard logo in a screenshot of the output and steers the selector onto its exact edges (`DEMO_REGION_RECT="x y w h"` overrides the detection; the screenshot is kept in `$XDG_RUNTIME_DIR/oasis-demo/`).

The take is one continuous recording with the default sink's monitor as audio (`DEMO_AUDIO=none` for silence): background music plays throughout, so nothing is cut or sped up and every step runs on camera. `record` notes when each beat starts in `marks.txt`, which `hero` uses to cut its loop.

## Tuning

Everything is an environment variable with a default at the top of the script: `DEMO_OUTPUT`, `DEMO_PASSWORD` (letters only, no `q`), `DEMO_FPS`, `DEMO_OUT_DIR`, `DEMO_AUDIO`, `DEMO_LOCATION`, `DEMO_SESSION_QUERY`, `DEMO_SEARCH_TEXT`, `DEMO_AGENT_PROMPT`, `DEMO_START_STYLE`, `DEMO_PALETTES`, `DEMO_STYLES` (`id:filter` pairs), `DEMO_WALLPAPER` (one image for the whole take; empty pins whatever the output shows at `stage`), `DEMO_MUSIC_PLAYER` and `DEMO_MUSIC_AT` (background music started when the unlock ends, for the cava bar), and one `T_*` variable per delay, for example `T_SURFACE_HOLD=2 demo/showcase.sh beat styles`.

The protected terminal is `DEMO_PROTECT_PID` (default `$KITTY_PID`). kitty shares one pid across its windows, so only the stage's own terminals (`kitty-tmux-dotfiles`, `kitty-tmux-agent`) are excluded, by class, and `DEMO_PROTECT_ADDR` pins exact window addresses.
