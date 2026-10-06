# Wallpaper rotator

Rotates wallpapers through hyprpaper, picking from folders that match the season, the part of the day and the weather. Every monitor gets a different image, a new monitor gets one as it is plugged in, and recently shown images are skipped so small folders do not repeat.

No wallpapers ship with this repo, since the images are other artists' copyrighted work. Bring your own collection.

## Setting up a collection

The collection lives in `~/Pictures/Wallpapers/Pixel Art` (change it with `wallpaper_dir`, see [Settings](#settings)). Image files sit at its top level; folders hold links to them, so one image can show in several places without being copied.

```
Pixel Art/
  Deep Forest - Day.png
  Deep Forest Rain - Night.png
  Winter Forest Snow - Dawn.png
  Any/
    Day/
      Deep Forest - Day.png -> ../../Deep Forest - Day.png
    Night/
      Rain/
        Deep Forest Rain - Night.png -> ../../../Deep Forest Rain - Night.png
  Winter/
    Dawn/
      Snow/
        Winter Forest Snow - Dawn.png -> ../../../Winter Forest Snow - Dawn.png
```

There is one layout, `<Season>/<Period>/<Weather>/`, and exactly one folder for each combination:

| Level | Folder names | Notes |
|---|---|---|
| Season | `Any`, `Spring`, `Summer`, `Fall`, `Winter` | `Any` shows in every season |
| Period | `Dawn`, `Day`, `Evening`, `Night` | Always required |
| Weather | `Rain`, `Snow`, `Cloudy` | Optional, only inside a period |

Names are case sensitive. An image that suits every part of the day goes into each period folder it fits.

At any moment the rotator draws from `Any/<Period>` and `<Season>/<Period>`. A weather folder inside either one joins only while that weather is current. So `Fall/Night/Rain` shows only on rainy fall nights, `Any/Night/Rain` on rainy nights in any season, and `Any/Day` on any day in any weather.

### Adding an image

Copy the file to the top of the collection, then link it from inside the real folder:

```bash
cd -P ~/Pictures/Wallpapers/"Pixel Art"
mkdir -p Fall/Night/Rain
ln -sr "Deep Forest Rain - Night.png" Fall/Night/Rain/
```

`ln -sr` writes the right relative path at any depth. `cd -P` matters when `~/Pictures/Wallpapers` is itself a symlink, for example when a stow package provides it: without it, `ln -sr` builds the link through that symlink, which only works on the machine it was made on. Link to the top-level file rather than to another link.

New and removed images are picked up at the next rotation; no restart is needed.

### Checking it

```bash
lua ~/.config/hypr/extensions/wallpaper/init.lua --audit
```

It prints each folder's image count (`thin` below 3), any image no folder uses, and any folder outside the layout, such as a typo or a leftover from an older layout.

## How it picks

**Periods.** By default, dawn starts at 06:00, day at 11:00, evening at 16:00 and night at 19:00 (`start_hours`). With location turned on they follow the sun instead: dawn 15 minutes before sunrise, day 4 hours after it, evening 2 hours 45 minutes before sunset and night 15 minutes after it, refreshed every 4 hours.

**Seasons.** Spring starts in March, summer in June, fall in September and winter in December (`season_start_months`). South of the equator they flip, judged from your coordinates or, with location off, your system timezone.

**Weather.** Read from the Quickshell bar's cache, `~/.cache/quickshell/weather.json`, so it needs the bar running. A cache older than an hour, or none at all, counts as no weather.

| Folder | Weather |
|---|---|
| `Rain` | Drizzle, rain, freezing rain, showers, thunderstorms |
| `Snow` | Snow, snow grains, snow showers |
| `Cloudy` | Overcast, fog |
| none | Clear, mostly clear, partly cloudy |

While a weather matches, each monitor shows an image from its weather folders with 60% odds (`weather_chance`), otherwise one from the regular folders.

**Rotation.** Every 15 minutes (`interval_minutes`) and as each period starts. A change of weather shows at the next rotation. The last 12 images shown (`history_size`) are skipped while enough others remain; weather images are exempt, since those folders are small. If both folders for the current period are empty, it falls back to the whole collection.

**Location.** Off by default. Turn it on with `wallpaper_location = true` in your machine profile (see `config/machines/README.md`) or `location_enabled = true` in your settings. Coordinates then come from, in order: `manual_lat`/`manual_lon`, the Quickshell cache, an IP lookup at `ipinfo.io`, and a guess from the system timezone. Sun times come from `sunwait` if installed, then the Quickshell cache, then `open-meteo.com`. With a fresh Quickshell cache, no network calls are made.

## Settings

Defaults live in `config.lua` next to this file. Override them in `~/.config/hypr/custom/wallpaper.lua`, which only needs the values you change:

```lua
-- custom/wallpaper.lua
return {
  wallpaper_dir = os.getenv("HOME") .. "/Pictures/Walls",
  interval_minutes = 30,
  weather_chance = 0.4,
}
```

| Setting | Default | Meaning |
|---|---|---|
| `wallpaper_dir` | `~/Pictures/Wallpapers/Pixel Art` | Root of the collection |
| `interval_minutes` | `15` | Minutes between rotations |
| `history_size` | `12` | Recent images to skip; `0` allows repeats |
| `rotation_enabled` | `true` | `false` applies one set and exits |
| `rotation` | `true` | `false` keeps running but stops timed rotation |
| `time_of_day_enabled` | `true` | `false` rotates through the whole collection |
| `seasons_enabled` | `true` | `false` uses only `Any` |
| `weather_enabled` | `true` | `false` skips weather folders |
| `weather_chance` | `0.6` | Odds per monitor of a weather image while one matches |
| `weather_max_age_minutes` | `60` | Ignore an older weather cache |
| `start_hours` | `dawn = 6, day = 11, evening = 16, night = 19` | Period starts when location is off |
| `season_start_months` | `spring = 3, summer = 6, fall = 9, winter = 12` | Season starts, northern hemisphere |
| `location_enabled` | `false` | Follow the sun; see Location above |
| `manual_lat`, `manual_lon` | unset | Fixed coordinates, used first |

Settings > Appearance > Wallpaper in the Quickshell bar sets rotation on or off, the interval, the time of day, season and weather toggles and the collection folder (`wallpaper_dir`), and pins an image to a monitor. It writes `~/.local/state/hypr/wallpaper.json` (under `$XDG_STATE_HOME`), which the rotator re-reads every couple of seconds, so those changes need no restart. Precedence, lowest to highest: `config.lua`, `custom/wallpaper.lua`, the Settings page, command-line flags.

A `wallpaper_dir` saved by the page must name an existing folder (a leading `~` is expanded), otherwise it is ignored; clearing it in the page goes back to the value from the config files. Changing it counts like a pool toggle and, with rotation on, picks new images at once.

A pin is stored against the monitor's description (`hyprctl -j monitors`), so it follows the screen across ports. A pinned monitor keeps its image and is left out of every pick; no other monitor shows the same image while the pool allows. A pin whose file is missing is ignored. With rotation off the process keeps running but stops timed rotation; startup, a plugged-in monitor and `SUPER + Q` then `W` still pick for unpinned monitors. The rotator also writes `wallpaper-status.json` beside it for the page to read.

`custom/wallpaper.lua` and the other settings are read once, so restart the rotator after changing them:

```bash
pkill -f 'wallpaper/init.lua'
hyprctl dispatch "hl.dsp.exec_cmd('lua ~/.config/hypr/extensions/wallpaper/init.lua')"
```

Other places that shape it:

- `wallpaper_enabled = false` in a machine profile stops the rotator from starting on that machine.
- `~/.config/hypr/custom/hyprpaper.conf` replaces the shipped `hyprpaper.conf` when the rotator starts hyprpaper. Keep `ipc = true` in it, since the rotator sets wallpapers over IPC.
- `SUPER + Q` then `W`, or `r` in the Settings page, skips to the next set; the running rotator takes it over and restarts its interval.

Files under `custom/` are gitignored; to track them in your own repo, see `custom/README.md`.

## Command line

```
lua ~/.config/hypr/extensions/wallpaper/init.lua [options]

--once, -o              Apply one set and exit
--audit                 Check the collection, then exit
--monitor NAME          Apply to one monitor only (implies --once)
--verbose, -v           Log what it picks and why
--config PATH           Use this settings file instead of custom/wallpaper.lua
--interval MIN          Minutes between rotations
--dir PATH              Use one folder, ignoring periods, seasons and weather
--season NAME           Force spring, summer, fall or winter
--no-seasons            Ignore season folders
--weather NAME          Force rain, snow or cloudy
--no-weather            Ignore weather folders
--dawn-hour H, --day-hour H, --evening-hour H, --night-hour H
                        Static period start hours
--location              Follow the sun
--no-location           Use static period hours
--latitude LAT, --longitude LON, --coordinates LAT,LON
                        Fixed coordinates
```

## Troubleshooting

`--once -v` applies a set right away and logs the period, season and weather it resolved, which folders it read and what it picked:

```
[wallpaper] Period fall night rain -> Any/Night, Fall/Night, Fall/Night/Rain; monitors=3; pool=25; weather=1
```

- **Wrong period, season or weather:** check that line; force one with `--season` or `--weather` to test a folder.
- **Images from every period at once:** both folders for the current period are empty or misnamed, so it fell back to the whole collection. Run `--audit`.
- **No weather images when it is raining:** the Quickshell bar is not running, or its cache is over an hour old.
- **A new monitor stays blank:** run `--monitor NAME --once`.
