# Agents

Runs every AI coding agent (Claude Code, Codex, Gemini, Qwen, Aider, opencode) in one systemd cgroup with memory and CPU limits. A runaway agent, its test run or a browser it starts then slows down or dies on its own, inside the slice. The memory limits cap the agents only: they reserve no memory for the rest of the machine, which can still run short on its own. The CPU limits cap the agents and rank the user manager below the login session.

Stow it with `just stow agents` (it is an optional package, under `# ai` in `packages/stow.ini`), then open a new shell. Type `claude` as before. Nothing else changes.

## What it does

- `~/.local/share/agent-shims/bin` holds one symlink per installed agent, named after it. Your shell and Hyprland put this folder first on `PATH`, so `claude` runs the shim.
- `agent-shims` writes that folder. It adds a shim for each agent it finds on `PATH` and removes the shim of an agent that is gone. Stowing the package runs it, and topgrade runs it first on every run. An agent you install later is capped from the next topgrade run, or at once after `agent-shims`.
- The shim runs `agent-run`, which finds the real `claude` further down `PATH` and starts it in a scope of its own under `agents.slice`. A scope keeps the agent in your terminal: the working directory, environment, input and exit code are unchanged.
- Each session is its own scope with `OOMPolicy=continue`. An out-of-memory kill takes the one process that grew, never the whole session.
- An agent started by another agent (Claude starting Codex) is already in the slice and runs directly, with no second scope.
- With no `systemd-run`, no user manager (a container, a bare TTY) or a user manager that refuses the scope, the agent runs without limits. The shim never stops an agent from starting.

Check that a session is capped with `systemctl --user status agents.slice`. Its sessions are listed under it as `run-*.scope`.

## Limits

| Key | Default | Meaning |
| --- | --- | --- |
| `MemoryHigh` | `75%` | Above this share of RAM the kernel throttles the agents and reclaims their memory. |
| `MemoryMax` | `85%` | At this share the kernel kills a process inside the slice. |
| `CPUWeight` | `50` | The agents' share of contended CPU against other apps under your user manager (terminals, browsers), which have the default of 100. Hyprland runs in the login session, a sibling of the user manager: `just system-apply` or the installer ships a drop-in (`system/etc/systemd/system/user@.service.d/50-cpuweight.conf`, `CPUWeight=50`) that ranks the whole user manager, agents included, below the session. |
| `X-UnlockedCPUQuota` | `87%` | The CPU cap while the screen is unlocked, as a share of all threads (87% is 14 of 16). systemd ignores this key. The lock screen reads it. An empty value leaves the slice uncapped while unlocked. |
| `X-LockedCPUQuota` | `62%` | The CPU cap while the screen is locked, as a share of all threads (62% is 10 of 16). systemd ignores this key. The lock screen reads it. |

Change them with a drop-in, which the repo never touches:

```bash
systemctl --user edit agents.slice
```

```ini
[Slice]
MemoryHigh=60%
MemoryMax=70%
CPUWeight=30
X-UnlockedCPUQuota=75%
X-LockedCPUQuota=50%
```

The memory and CPU keys apply at once, except the two `X-` keys, which the lock screen applies the next time the bar starts, the screen locks or unlocks. A `CPUQuota=` you set yourself wins over either share when it is tighter, and a lock never raises the cap above the unlocked one. Sessions started before you stowed this package stay uncapped until you restart them.

## Add or remove an agent

The `agents` list in `.local/bin/agent-shims` names the agents. To add one, add its command to the list, then run `agent-shims`. To leave one out, remove it from the list and delete its shim. Only installed agents get a shim, because a shim for a missing one puts a dead command on `PATH`: topgrade then runs that agent's update step and fails.

Ollama has no shim on purpose: it runs as the system service `ollama.service`, so a shim on the client caps nothing. Cap it with a drop-in for that service (`sudo systemctl edit ollama.service`, with `MemoryMax=` and `CPUWeight=`).

## What escapes

- An agent started by full path (`~/.local/bin/claude`) or by a program that ignores `PATH`, such as some editor plugins.
- A program an agent hands to the desktop with `hyprctl dispatch` or another Hyprland exec. It runs in Hyprland's cgroup, not the slice.
- A program that calls `systemd-run --user --scope` without `--slice`: its scope lands in `app.slice`, outside the cap. The desertfox key tests are the known case.
- A session already running when you stow or change the package, until you restart it.

## Opt out

Run `just unstow agents` and open a new shell. It removes the shims too. Agents then run in your terminal's cgroup again. Running sessions keep their scope until they exit.

## Code

- `.local/bin/agent-run`: the launcher. `AGENT_RUN_SLICE` and `AGENT_RUN_CGROUP_FILE` override the slice and the cgroup file, for tests and one-off runs.
- `.local/bin/agent-shims`: writes the shims, symlinks to `~/.local/bin/agent-run`. `AGENT_SHIMS_DIR` and `AGENT_RUN` override the folder and the launcher, for tests. `stow_packages` in `lib/install/stow.sh` runs it on stow and runs `--remove` on unstow, and `uninstall.sh` runs `--remove`. The topgrade pre-command is in `home/topgrade/.config/topgrade.toml`.
- `.config/systemd/user/agents.slice`: the slice and its default limits. The package is in `NO_FOLD_PACKAGES` (see [the installer](../../lib/install/README.md#stowing)).
- The `PATH` entries: the end of `home/zsh/.zshrc` and `home/bash/.bashrc`, and `build_path` in `home/hypr/.config/hypr/config/env/init.lua`.
- `tests/agent_run.sh`: the launcher against a stub `systemd-run`, run by the `agent-run` check step. `tests/agent_shims.sh`: `agent-shims` against stub agents.
