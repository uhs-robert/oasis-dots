# Lua Theme System - Phase 1 POC

## Overview

This is a proof-of-concept Lua-based theme system that generates Hyprland and Waybar configuration files from a single palette definition.

## Directory Structure

```
theme/
├── main.lua                          # Main entry point
├── lib/
│   ├── utils.lua                     # Utility functions
│   ├── generators.lua                # Theme generators for each app
│   └── theme.lua                     # Theme management logic
├── palettes/
│   └── oasis_lagoon_dark.lua        # Theme palette definitions
├── output/
│   ├── hypr-theme.conf              # Generated Hyprland theme
│   ├── waybar-theme.css             # Generated Waybar CSS
│   └── rofi-theme.rasi              # Generated Rofi theme
└── README.md                         # This file
```

## How It Works

1. **Palette Definition** (`palettes/*.lua`): Single source of truth for all colors
2. **Modular Architecture** (`lib/`): Separate modules for utilities, generators, and theme management
3. **Main Controller** (`main.lua`): Entry point that orchestrates theme switching
4. **Output Files** (`output/`): Generated configs that can be imported by your existing configs

### Supported Applications

✅ **Hyprland** - Window manager colors, borders, shadows
✅ **Waybar** - Status bar styling
✅ **Rofi** - Application launcher colors

## Usage

### Quick Commands

```bash
cd ~/.config/hypr/theme

# Show rofi theme picker (recommended!)
./main.lua --menu

# List available themes
./main.lua --list

# Apply a specific theme by name
./main.lua oasis_lagoon_dark

# Apply current/default theme
./main.lua
```

### What Each Command Does

**`./main.lua --menu`** (or `-m`)
- Opens a rofi menu with all available themes
- Shows current theme
- Select a theme to apply it instantly
- Auto-reloads Hyprland and Waybar

**`./main.lua --list`** (or `-l`)
- Lists all themes in `palettes/` directory
- Shows which theme is currently active

**`./main.lua <theme_name>`**
- Directly applies the specified theme
- Generates config files
- Reloads services automatically

### 2. Test Hyprland Theme

Two test configs have been created that use the generated themes:

**Hyprland:**
```bash
# View the test config
cat ~/.config/hypr/hyprland.conf.lua-test

# Test by loading it (this won't affect your current session)
# You would need to restart Hyprland with this config to test
```

**Waybar:**
```bash
# Test waybar with the new theme
pkill waybar
waybar -c ~/.config/waybar/config.jsonc -s ~/.config/waybar/style.css.lua-test &
```

### 3. Compare Colors

**Original Palette** (from waybar/style.css):
- bg_core: #101825
- primary: #1CA0FD (was #42a5f5 in some files)
- secondary: #FFA247

**Generated Palette** (from theme):
- bg_core: #101825
- primary: #1CA0FD
- secondary: #FFA247

Note: The generated palette uses colors from `oasis_lagoon_dark.lua` which may differ slightly from your current manually-maintained configs.

## Backups Created

- `hyprland.conf.backup` - Original hyprland config
- `waybar/style.css.backup` - Original waybar style

## Next Steps

If Phase 1 looks good:

1. **Adjust palette** if colors don't match exactly
2. **Add more apps** (rofi, swaync, kitty)
3. **Create additional themes** (catppuccin, nord, etc.)
4. **Add auto-reload** functionality
5. **Create theme switcher** keybinding

## Advantages of This Approach

✅ **Single source of truth**: Change colors once, all apps update
✅ **Type safety**: Lua catches errors before generating configs
✅ **Easy theme switching**: Just change one line in main.lua
✅ **Maintainable**: No more manually syncing colors across 5+ files
✅ **Extensible**: Easy to add new apps or color schemes

## Adding to Hyprland Keybindings

Add this to your Hyprland config for quick theme switching:

```conf
# Theme switcher
bind = $mainMod, T, exec, ~/.config/hypr/theme/main.lua --menu
```

Now press `Super + T` to open the theme picker!

## Creating New Themes

1. Copy an existing palette:
   ```bash
   cp palettes/oasis_lagoon_dark.lua palettes/my_theme.lua
   ```

2. Edit the colors in `my_theme.lua`

3. The new theme will automatically appear in the theme picker!

## How It Works

1. **Palette files** (`.lua`) define colors once
2. **`main.lua`** reads the palette and generates:
   - `output/hypr-theme.conf` - Hyprland format (`0xff...`)
   - `output/waybar-theme.css` - CSS format (`#...`)
3. **Config files** import the generated themes
4. **Services reload** automatically when theme changes

## Regenerating Themes

Anytime you modify a palette file, just run:

```bash
./main.lua
```

And all output files will be regenerated with the new colors.
