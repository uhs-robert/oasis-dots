# Hyprland Lua Scripts

Modular Lua-based scripts for Hyprland workspace and application management.

## 🚀 Scripts

### assign-workspaces.lua

Assigns specific workspaces to monitors based on hardware descriptions and manages XWayland primary monitor configuration.

**Usage:**

```bash
./assign-workspaces.lua [--assign] [--watch]
```

**Options:**

- `--assign` - Run workspace assignment once
- `--watch` - Watch for monitor events and auto-reassign (uses event listener)
- No args - Runs both assign and watch

**Features:**

- ✅ Hardware description-based monitor identification (survives replugs)
- ✅ Automatic workspace-to-monitor assignment
- ✅ XWayland primary monitor configuration
- ✅ Event-driven reassignment on monitor hotplug
- ✅ PID file-based duplicate prevention
- ✅ Graceful degradation when monitors are missing

### auto-launch-apps.lua

Interactive rofi-based application launcher with predefined workspace layouts and smart window placement.

**Usage:**

```bash
./auto-launch-apps.lua [--startup]
```

**Options:**

- `--startup` - Startup mode (shows menu on workspace 1, waits for windows before cleanup)
- No args - Interactive mode (shows menu on current monitor)

**Features:**

- ✅ Rofi menu for setup selection
- ✅ Smart workspace allocation per monitor
- ✅ Firefox multi-window distribution
- ✅ Config-driven setup definitions (see `config/app-setups.lua`)
- ✅ Workspace preloading for reliable window placement
- ✅ Retry logic for failed launches

## 📋 Library Modules

### lib/hyprctl.lua

Wrapper for Hyprland IPC via `hyprctl` with JSON parsing support.

### lib/logger.lua

Unified logging to systemd journal and stderr.

### lib/monitor.lua

Monitor discovery, workspace range calculation, and assignment validation.

### lib/process.lua

Process management utilities including PID files, duplicate detection, and condition waiting.

### lib/utils.lua

**Shared utility library** used by both `lua/` scripts and the `theme/` system.

## ⚙️ Configuration

### config/app-setups.lua

Define reusable app blocks and complete setup configurations.

**Structure:**

```lua
Config.apps = {
    firefox_triple = {
        { monitor = "CENTER", increment = true, cmd = "firefox" },
        { monitor = "LAPTOP", increment = true, cmd = "firefox" },
        { monitor = "LEFT", increment = true, cmd = "firefox" }
    },
    email = {
        { monitor = "LEFT", increment = true, cmd = "flatpak run eu.betterbird.Betterbird" }
    }
}

Config.setups = {
    ["🌐 Browsing"] = {
        Config.apps.firefox_triple,
        tmuxifier("config")
    }
}
```

**Adding New Setups:**

1. Define reusable app blocks in `Config.apps` (optional)
2. Add setup to `Config.setups` with emoji + name
3. Use `{ monitor = "NAME", increment = true, cmd = "command" }` format
4. Helper functions available: `tmuxifier(session, monitor)`, `tmux_session(name, monitor)`
