<p align="center">
  <img
    src="https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/svg/1f3ae.svg"
    width="128" height="128" alt="Logo" />
</p>
<h1 align="center">steam-appid.yazi</h1>

<p align="center">
  <a href="https://github.com/uhs-robert/steam-appid.yazi/stargazers"><img src="https://img.shields.io/github/stars/uhs-robert/steam-appid.yazi?colorA=192330&colorB=khaki&style=for-the-badge&cacheSeconds=4300" alt="Stargazers"></a>
  <a href="https://github.com/sxyazi/yazi" target="_blank" rel="noopener noreferrer"><img alt="Yazi 0.25+" src="https://img.shields.io/badge/Yazi-0.25%2B-blue?style=for-the-badge&cacheSeconds=4300&labelColor=192330" alt="Yazi"></a>
  <a href="https://github.com/uhs-robert/steam-appid.yazi/issues"><img src="https://img.shields.io/github/issues/uhs-robert/steam-appid.yazi?colorA=192330&colorB=skyblue&style=for-the-badge&cacheSeconds=4300" alt="Issues"></a>
  <a href="https://github.com/uhs-robert/steam-appid.yazi/contributors"><img src="https://img.shields.io/github/contributors/uhs-robert/steam-appid.yazi?colorA=192330&colorB=8FD1C7&style=for-the-badge&cacheSeconds=4300" alt="Contributors"></a>
  <a href="https://github.com/uhs-robert/steam-appid.yazi/network/members"><img src="https://img.shields.io/github/forks/uhs-robert/steam-appid.yazi?colorA=192330&colorB=CFA7FF&style=for-the-badge&cacheSeconds=4300" alt="Forks"></a>
</p>

<p align="center">
  A <a href="https://github.com/sxyazi/yazi">Yazi</a> linemode plugin that resolves Steam AppIDs to game names.<br /><i>Browse your <code>steamapps</code> folder and see game names instead of raw IDs.</i>
</p>

<table>
  <tr>
    <td align="center"><img src="assets/before.png" alt="Before plugin screenshot" width="auto"><br><strong>BEFORE</strong></td>
    <td align="center"><img src="assets/after.png" alt="After plugin screenshot" width="auto"><br><strong>AFTER</strong></td>
  </tr>
</table>

<p align="center">
  <a href="./NEWS.md">✨ What's New / 🚨 Breaking Changes</a>
</p>

## 🎮 No More AppID Lookups

Steam stores game data in folders and files by numeric AppID like `1091500/`, etc. These IDs are meaningless at a glance.

When modding, you often need to navigate `steamapps/compatdata/` or the main `steamapps/` folder to inspect/edit game files.

**This plugin resolves those IDs to game names inline so you don't have to cross-reference IDs against a database or SteamDB.**

## ⚙️ How it works

The plugin reads `appmanifest_<id>.acf` files from your `steamapps` directory and displays the `name` field inline. It activates for:

- **`appmanifest_*.acf` files** inside `steamapps/`
- **Numeric ID folders** inside `steamapps/downloading/`, `compatdata/`, `shadercache/`, and `temp/`

Game names are cached in memory for the session, so repeated lookups don't hit disk.

## 📋 Requirements

| Dependency                             | Requirement                        |
| -------------------------------------- | ---------------------------------- |
| [Yazi](https://github.com/sxyazi/yazi) | 0.25+                              |
| Steam                                  | at least one `steamapps` directory |

## 📦 Installation & Setup

#### 1. Install the plugin

```sh
ya pkg add uhs-robert/steam-appid
```

#### 2. Register the linemode

Add the following to your `~/.config/yazi/init.lua`:

```lua
local steam_appid = require("steam-appid")
steam_appid.setup()

function Linemode:steam_appid()
  return steam_appid.linemode(self)
end
```

#### 3. Enable the linemode

Add the following to your `~/.config/yazi/yazi.toml`:

```toml
[mgr]
linemode = "steam_appid"
```

## 🛠️ Configuration

All options are optional. Defaults shown below.

| Option            | Type       | Default                          | Description                                                                                      |
| ----------------- | ---------- | -------------------------------- | ------------------------------------------------------------------------------------------------ |
| `steamapps_paths` | `string[]` | `~/.local/share/Steam/steamapps` | Paths to search for `appmanifest_*.acf` files. Add extra entries for additional Steam libraries. |
| `icon`            | `string`   | Nerd font `Steam` icon           | Icon prepended to the game name. Set to `""` to disable.                                         |

### Handling Multiple Steam Libraries

```lua
steam_appid.setup({
  steamapps_paths = {
    os.getenv("HOME") .. "/.local/share/Steam/steamapps",
    "/mnt/games/Steam/steamapps",
  },
})
```
