# Weather views

`WeatherPopup` picks a folder here from the style's `weather_header` token (`styles/<style>/tokens.js`). A token's folder holds the views that style redraws: the Hourly, Sun & Moon, Air and Alerts views, and usually a header and day column (`hero` draws its header as `WeatherHero` and `lsp` as `WeatherLsp`, with no `Header` file); any view a token does not redraw falls back to the plain one in `shared/`. The popup's `layout_views` table lists which views each token owns.

| token | style | what it draws |
| --- | --- | --- |
| `battle` | nes | A Dragon Quest battle screen: slime sprites for the days, message window, sun and moon in pixel art |
| `hero` | modern | Gradient area chart and hour pills in the modern style's hero card |
| `hev` | halflife | The HEV suit readout: health cross, shield and angled bars, with an HEV voice line |
| `lsp` | neovim | Neovim buffers: `:checkhealth`-style Air, diagnostics and an inlay-hint gutter |
| `memcard` | ps1 | Memory card save blocks with icons and gauges |
| `mode7` | snes | A SNES RPG menu window, with a Mode 7 floor under the days |
| `oasis` | oasis | Desert scenes: a dune ridge for Air, palms on the cursor hour, the moon pool |
| `pokedex` | gameboy | A Pokedex entry with a pixel photo and stat bars |
| `ring` | reticle | A ticked ring gauge around the temperature, with leader-line callouts |
| `scan` | metroid | A Metroid Scan Visor logbook, each alert a locked-on threat |
| `scope` | tie | A sensor scope: wind bearing and precipitation as contacts, the temperature as the locked target |
| `status` | ff7 | A Final Fantasy VII status menu with Materia slots |
| `towers` | ps2 | The PS2 clock screen: a thin glowing temperature, readings below like the system browser |
| `watch` | goldeneye | The GoldenEye pause watch face and mission-style alerts |
| `weatherstar` | crt | WeatherStar 4000 screens: yellow titles over bevelled blue panels |
| `wttr` | terminal | wttr.in text tables with ASCII sky art |

A view that another feature's code also draws lives in `styles/<style>/widgets/` (`DqWindow`, `BattleGauge`, `DexStatBar`, `ScanLock`, `TickGauge`, `WsPanel`, `TowerFloor`), and a view used by more than one token lives in `shared/`.
