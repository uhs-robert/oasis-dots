# Agents

Runs every AI coding agent (Claude Code, Codex, Gemini, Qwen, Aider, opencode) in one systemd cgroup with memory and CPU limits. A runaway agent, its test run or a browser it starts then slows down or dies on its own. It cannot freeze the desktop or make the kernel kill something else.

Stow it with `just stow agents` (it is an optional package, under `# ai` in `packages/stow.ini`), then open a new shell. Type `claude` as before. Nothing else changes.

## What it does

- `~/.local/share/agent-shims/bin` holds one symlink per agent, named after it. Your shell and Hyprland put this folder first on `PATH`, so `claude` runs the shim.
- The shim runs `agent-run`, which finds the real `claude` further down `PATH` and starts it in a scope of its own under `agents.slice`. A scope keeps the agent in your terminal: the working directory, environment, input and exit code are unchanged.
- Each session is its own scope with `OOMPolicy=continue`. An out-of-memory kill takes the one process that grew, never the whole session.
- An agent started by another agent (Claude starting Codex) is already in the slice and runs directly, with no second scope.
- With no `systemd-run` or no user manager (a container, a bare TTY), the agent runs without limits. The shim never stops an agent from starting.

Check that a session is capped with `systemctl --user status agents.slice`. Its sessions are listed under it as `run-*.scope`.

## Limits

| Key | Default | Meaning |
| --- | --- | --- |
| `MemoryHigh` | `75%` | Above this share of RAM the kernel throttles the agents and reclaims their memory. |
| `MemoryMax` | `85%` | At this share the kernel kills a process inside the slice. |
| `CPUWeight` | `50` | The agents' share of contended CPU. The desktop has the default of 100, so it wins. |
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
X-LockedCPUQuota=50%
```

The memory and CPU keys apply at once. Sessions started before you stowed this package stay uncapped until you restart them.

## Add or remove an agent

The shim folder is the list. To add an agent, add a symlink to `../../../bin/agent-run` in `home/agents/.local/share/agent-shims/bin/`, named after the agent's command. Then run `just restow agents`. To leave one out, delete its symlink.

Ollama has no shim on purpose: it runs as the system service `ollama.service`, so a shim on the client caps nothing. Cap it with a drop-in for that service (`sudo systemctl edit ollama.service`, with `MemoryMax=` and `CPUWeight=`).

## What escapes

- An agent started by full path (`~/.local/bin/claude`) or by a program that ignores `PATH`, such as some editor plugins.
- A program an agent hands to the desktop with `hyprctl dispatch` or another Hyprland exec. It runs in Hyprland's cgroup, not the slice.
- A session already running when you stow or change the package, until you restart it.

## Opt out

Run `just unstow agents` and open a new shell. Agents then run in your terminal's cgroup again. Running sessions keep their scope until they exit.

## Code

- `.local/bin/agent-run`: the launcher. `AGENT_RUN_SLICE` and `AGENT_RUN_CGROUP_FILE` override the slice and the cgroup file, for tests and one-off runs.
- `.local/share/agent-shims/bin/`: the shims, relative symlinks to `agent-run`.
- `.config/systemd/user/agents.slice`: the slice and its default limits. The package is in `NO_FOLD_PACKAGES` (see [the installer](../../lib/install/README.md#stowing)).
- The `PATH` entries: the end of `home/zsh/.zshrc` and `home/bash/.bashrc`, and `build_path` in `home/hypr/.config/hypr/config/env/init.lua`.
- `tests/agent_run.sh`: the launcher against a stub `systemd-run`, run by the `agent-run` check step.
