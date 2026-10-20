# Weather

`weather/` holds `WeatherState`, its IPC handler and fixtures, `Astro.js`, the weather popup, the oasis bar's `Horizon` sun arc, its icons in `icons/` and the per-style layouts in `views/` (see `views/README.md`).

Settings > Weather sets the location, units and forecast days. Automatic looks the place up from your IP address over HTTPS (ipwho.is), cached and repeated at most once a day; Manual takes a latitude, longitude and optional place name. Changes apply at once and are saved to `weather.local.json` in the Quickshell state folder (`$XDG_STATE_HOME/quickshell/`, or `~/.local/state/quickshell/`), which overrides the tracked `weather.json` defaults. You can still edit either file by hand: `latitude` and `longitude` (a number or `"auto"`), `location_name` (replaces the looked-up name), `unit` (`fahrenheit` or `celsius`, which also picks mph or km/h and inches or mm), and `days` (1 to 16).

Weather alerts come from the US National Weather Service (api.weather.gov), so the Alerts tab only appears for US locations; elsewhere no alert request is made. When no forecast has loaded and the last fetch failed, the bar shows `n/a` and the tooltip and popup header give the reason; with data already loaded it keeps showing it as stale.

## Weather views

Each style draws its own popup layout in `features/weather/views/<token>/`; `views/README.md` maps tokens to styles.

Test data lives in `features/weather/WeatherFixture.js` (`base`, `alerts1`, `alerts3`, `aqi-bad`, `rain`, `night`), shaped like the data `WeatherState` builds.

To see a fixture in the live popup, `qs-ipc call weather preview alerts3` (then open the popup), `qs-ipc call weather previewing`, and `qs-ipc call weather preview off`. While a preview is on, weather fetches are paused; `off` restores the real data and refetches.
