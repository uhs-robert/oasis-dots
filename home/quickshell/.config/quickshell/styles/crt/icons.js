.pragma library

// The CRT icon set: phosphor-terminal vector icons (a blocky bell, a modem with signal LEDs, a floppy, a cassette, a block-character battery bar) for the bar, keyed by icon name, then by variant.
// Each entry is a viewBox of w x h (h is always 24); "body" is SVG path data filled with the icon's tint, "accent" is path data filled with its highlight and drawn on top.
// Shapes sit on a 2-unit character-cell grid; the floppy has 1-unit scanline gaps cut through its fill. A missing icon or variant falls back to the module's Nerd Font glyph. The clock keeps its VT100 lamp meeting marker, so there is no meeting icon.
var vectors = {
    "notifications": {
        "normal": {"w": 22, "h": 24, "body": "M8 2h6v2h-6ZM6 4h10v2h-10ZM4 6h14v6h-14ZM2 12h18v4h-18ZM0 16h22v2h-22Z", "accent": "M8 18h6v2h-6Z"},
        "dnd": {"w": 22, "h": 24, "body": "M8 2h6v2h-6ZM6 4h2v2h-2ZM14 4h2v2h-2ZM4 6h2v6h-2ZM16 6h2v6h-2ZM2 12h2v4h-2ZM18 12h2v4h-2ZM0 16h22v2h-22ZM8 18h6v2h-6Z"}
    },
    "volume": {
        "muted": {"w": 20, "h": 24, "body": "M6 4h2v2h-2ZM4 6h4v2h-4ZM11 8h2v2h-2ZM17 8h2v2h-2ZM13 10h4v4h-4ZM0 8h8v8h-8ZM11 14h2v2h-2ZM17 14h2v2h-2ZM4 16h4v2h-4ZM6 18h2v2h-2Z"},
        "low": {"w": 20, "h": 24, "body": "M6 4h2v2h-2ZM4 6h4v2h-4ZM0 8h8v8h-8ZM4 16h4v2h-4ZM6 18h2v2h-2Z", "accent": "M10 9h2v6h-2Z"},
        "mid": {"w": 20, "h": 24, "body": "M6 4h2v2h-2ZM4 6h4v2h-4ZM0 8h8v8h-8ZM4 16h4v2h-4ZM6 18h2v2h-2Z", "accent": "M10 9h2v6h-2ZM14 6h2v12h-2Z"},
        "high": {"w": 20, "h": 24, "body": "M6 4h2v2h-2ZM4 6h4v2h-4ZM0 8h8v8h-8ZM4 16h4v2h-4ZM6 18h2v2h-2Z", "accent": "M10 9h2v6h-2ZM14 6h2v12h-2ZM18 3h2v18h-2Z"}
    },
    "network": {
        "wifi_0": {"w": 29, "h": 24, "body": "M13 1h6v2h-6ZM15 3h2v2h-2ZM0 5h21v2h-21ZM3 16h3v2h-3ZM7 16h3v2h-3ZM11 16h3v2h-3ZM15 16h3v2h-3ZM0 7h2v12h-2ZM19 7h2v12h-2ZM0 19h21v2h-21Z"},
        "wifi_1": {"w": 29, "h": 24, "body": "M13 1h6v2h-6ZM15 3h2v2h-2ZM0 5h21v2h-21ZM7 16h3v2h-3ZM11 16h3v2h-3ZM15 16h3v2h-3ZM0 7h2v12h-2ZM19 7h2v12h-2ZM0 19h21v2h-21Z", "accent": "M3 14h3v4h-3Z"},
        "wifi_2": {"w": 29, "h": 24, "body": "M13 1h6v2h-6ZM15 3h2v2h-2ZM0 5h21v2h-21ZM11 16h3v2h-3ZM15 16h3v2h-3ZM0 7h2v12h-2ZM19 7h2v12h-2ZM0 19h21v2h-21Z", "accent": "M7 12h3v6h-3ZM3 14h3v4h-3Z"},
        "wifi_3": {"w": 29, "h": 24, "body": "M13 1h6v2h-6ZM15 3h2v2h-2ZM0 5h21v2h-21ZM15 16h3v2h-3ZM0 7h2v12h-2ZM19 7h2v12h-2ZM0 19h21v2h-21Z", "accent": "M11 10h3v8h-3ZM7 12h3v6h-3ZM3 14h3v4h-3Z"},
        "wifi_4": {"w": 29, "h": 24, "body": "M13 1h6v2h-6ZM15 3h2v2h-2ZM0 5h21v2h-21ZM0 7h2v12h-2ZM19 7h2v12h-2ZM0 19h21v2h-21Z", "accent": "M15 8h3v10h-3ZM11 10h3v8h-3ZM7 12h3v6h-3ZM3 14h3v4h-3Z"},
        "wired": {"w": 29, "h": 24, "body": "M13 1h6v2h-6ZM15 3h2v2h-2ZM0 5h21v2h-21ZM24 8h5v2h-5ZM19 7h2v5h-2ZM24 10h3v2h-3ZM19 12h10v2h-10ZM24 14h3v2h-3ZM24 16h5v2h-5ZM0 7h2v12h-2ZM19 14h2v5h-2ZM0 19h21v2h-21Z", "accent": "M4 13h4v4h-4ZM11 13h4v4h-4Z"},
        "offline": {"w": 29, "h": 24, "body": "M13 1h6v2h-6ZM15 3h2v2h-2ZM0 5h21v2h-21ZM23 10h2v2h-2ZM27 10h2v2h-2ZM25 12h2v2h-2ZM23 14h2v2h-2ZM27 14h2v2h-2ZM3 16h3v2h-3ZM7 16h3v2h-3ZM11 16h3v2h-3ZM15 16h3v2h-3ZM0 7h2v12h-2ZM19 7h2v12h-2ZM0 19h21v2h-21Z"}
    },
    "bluetooth": {
        "on": {"w": 10, "h": 24, "body": "M4 3h2v2h-2ZM4 5h4v2h-4ZM0 7h2v2h-2ZM4 7h2v2h-2ZM8 7h2v2h-2ZM2 9h6v2h-6ZM4 11h2v2h-2ZM2 13h6v2h-6ZM0 15h2v2h-2ZM4 15h2v2h-2ZM8 15h2v2h-2ZM4 17h4v2h-4ZM4 19h2v2h-2Z", "accent": "M4 3h2v18h-2Z"},
        "blocked": {"w": 18, "h": 24, "body": "M4 3h2v2h-2ZM4 5h4v2h-4ZM0 7h2v2h-2ZM4 7h2v2h-2ZM8 7h2v2h-2ZM2 9h6v2h-6ZM12 9h2v2h-2ZM16 9h2v2h-2ZM4 11h2v2h-2ZM14 11h2v2h-2ZM2 13h6v2h-6ZM12 13h2v2h-2ZM16 13h2v2h-2ZM0 15h2v2h-2ZM4 15h2v2h-2ZM8 15h2v2h-2ZM4 17h4v2h-4ZM4 19h2v2h-2Z", "accent": "M4 3h2v18h-2Z"}
    },
    "battery": {
        "level_0": {"w": 22, "h": 24, "body": "M0 4h17v2h-17ZM15 6h2v2h-2ZM15 8h4v8h-4ZM3 15h2v2h-2ZM6 15h2v2h-2ZM9 15h2v2h-2ZM12 15h2v2h-2ZM0 6h2v12h-2ZM15 16h2v2h-2ZM0 18h17v2h-17Z"},
        "level_1": {"w": 22, "h": 24, "body": "M0 4h17v2h-17ZM15 6h2v2h-2ZM15 8h4v8h-4ZM6 15h2v2h-2ZM9 15h2v2h-2ZM12 15h2v2h-2ZM0 6h2v12h-2ZM15 16h2v2h-2ZM0 18h17v2h-17Z", "accent": "M3 7h2v10h-2Z"},
        "level_2": {"w": 22, "h": 24, "body": "M0 4h17v2h-17ZM15 6h2v2h-2ZM15 8h4v8h-4ZM9 15h2v2h-2ZM12 15h2v2h-2ZM0 6h2v12h-2ZM15 16h2v2h-2ZM0 18h17v2h-17Z", "accent": "M3 7h2v10h-2ZM6 7h2v10h-2Z"},
        "level_3": {"w": 22, "h": 24, "body": "M0 4h17v2h-17ZM15 6h2v2h-2ZM15 8h4v8h-4ZM12 15h2v2h-2ZM0 6h2v12h-2ZM15 16h2v2h-2ZM0 18h17v2h-17Z", "accent": "M3 7h2v10h-2ZM6 7h2v10h-2ZM9 7h2v10h-2Z"},
        "level_4": {"w": 22, "h": 24, "body": "M0 4h17v2h-17ZM15 6h2v2h-2ZM15 8h4v8h-4ZM0 6h2v12h-2ZM15 16h2v2h-2ZM0 18h17v2h-17Z", "accent": "M3 7h2v10h-2ZM6 7h2v10h-2ZM9 7h2v10h-2ZM12 7h2v10h-2Z"},
        "full": {"w": 22, "h": 24, "body": "M0 4h17v2h-17ZM15 6h2v2h-2ZM15 8h4v8h-4ZM0 6h2v12h-2ZM15 16h2v2h-2ZM0 18h17v2h-17Z", "accent": "M0 4h17v2h-17ZM15 6h2v2h-2ZM15 8h4v8h-4ZM3 7h2v10h-2ZM6 7h2v10h-2ZM9 7h2v10h-2ZM12 7h2v10h-2ZM0 6h2v12h-2ZM15 16h2v2h-2ZM0 18h17v2h-17Z"},
        "charging": {"w": 22, "h": 24, "body": "M0 4h17v2h-17ZM15 6h2v2h-2ZM15 8h4v8h-4ZM9 15h2v2h-2ZM12 15h2v2h-2ZM0 6h2v12h-2ZM15 16h2v2h-2ZM0 18h17v2h-17Z", "accent": "M20 7h2v4h-2ZM19 11h3v2h-3ZM3 7h2v10h-2ZM6 7h2v10h-2ZM19 13h2v4h-2Z"}
    },
    "system": {
        "cpu": {"w": 20, "h": 24, "body": "M6 4h2v2h-2ZM12 4h2v2h-2ZM4 6h12v2h-12ZM2 8h4v2h-4ZM14 8h4v2h-4ZM4 10h2v4h-2ZM14 10h2v4h-2ZM2 14h4v2h-4ZM14 14h4v2h-4ZM4 16h12v2h-12ZM6 18h2v2h-2ZM12 18h2v2h-2Z", "accent": "M8 10h4v4h-4Z"},
        "mem": {"w": 24, "h": 24, "body": "M0 6h24v2h-24ZM0 8h2v6h-2ZM22 8h2v6h-2ZM0 14h24v2h-24ZM4 16h2v2h-2ZM8 16h2v2h-2ZM12 16h2v2h-2ZM16 16h2v2h-2ZM20 16h2v2h-2Z", "accent": "M4 11h4v2h-4ZM10 11h4v2h-4ZM16 11h4v2h-4Z"},
        "temp": {"w": 12, "h": 24, "body": "M2 2h8v2h-8ZM2 4h2v8h-2ZM8 4h2v8h-2ZM0 12h4v2h-4ZM8 12h4v2h-4ZM0 14h2v4h-2ZM10 14h2v4h-2ZM0 18h4v2h-4ZM8 18h4v2h-4ZM2 20h8v2h-8Z", "accent": "M4 8h4v6h-4ZM2 14h8v4h-8ZM4 18h4v2h-4Z"}
    },
    "updates": {
        "official": {"w": 20, "h": 24, "body": "M0 2h18v2h-18ZM0 4h4v3h-4ZM14 4h6v3h-6ZM0 8h4v2h-4ZM14 8h6v2h-6ZM0 10h20v3h-20ZM0 14h2v5h-2ZM18 14h2v5h-2ZM0 20h20v2h-20Z", "accent": "M6 6h6v2h-6ZM4 16h12v2h-12Z"},
        "aur": {"w": 30, "h": 24, "body": "M0 2h30v2h-30ZM4 6h22v2h-22ZM4 9h22v1h-22ZM4 10h3v1h-3ZM13 10h4v1h-4ZM23 10h3v1h-3ZM9 10h2v2h-2ZM19 10h2v2h-2ZM7 12h16v1h-16ZM7 13h6v1h-6ZM17 13h6v1h-6ZM4 11h2v4h-2ZM24 11h2v4h-2ZM9 14h2v2h-2ZM19 14h2v2h-2ZM4 15h3v1h-3ZM13 15h4v1h-4ZM23 15h3v1h-3ZM4 16h22v1h-22ZM0 4h2v16h-2ZM28 4h2v16h-2ZM10 18h10v2h-10ZM0 20h30v2h-30Z", "accent": "M9 12h2v2h-2ZM19 12h2v2h-2Z"}
    },
    "media": {
        "normal": {"w": 16, "h": 24, "body": "M4 5h12v4h-12ZM4 9h2v6h-2ZM14 9h2v6h-2ZM0 15h6v4h-6ZM10 15h6v4h-6Z", "accent": "M0 15h6v4h-6ZM10 15h6v4h-6Z"}
    },
    "recording": {
        "scrolling": {"w": 20, "h": 24, "body": "M0 2h6v2h-6ZM14 2h6v2h-6ZM0 4h2v4h-2ZM18 4h2v4h-2ZM0 16h2v4h-2ZM18 16h2v4h-2ZM0 20h6v2h-6ZM14 20h6v2h-6Z", "accent": "M9 7h2v6h-2ZM5 11h2v2h-2ZM13 11h2v2h-2ZM7 13h6v2h-6ZM9 15h2v2h-2Z"},
        "counting": {"w": 18, "h": 24, "body": "M6 1h6v2h-6ZM8 3h2v2h-2ZM4 5h10v2h-10ZM2 7h4v2h-4ZM12 7h4v2h-4ZM0 9h4v2h-4ZM14 9h4v2h-4ZM0 11h2v6h-2ZM16 11h2v6h-2ZM0 17h4v2h-4ZM14 17h4v2h-4ZM2 19h4v2h-4ZM12 19h4v2h-4ZM4 21h10v2h-10Z", "accent": "M8 8h2v4h-2ZM8 12h6v2h-6Z"},
        "default": {"w": 14, "h": 24, "body": "M4 5h6v2h-6ZM2 7h10v2h-10ZM0 9h14v6h-14ZM2 15h10v2h-10ZM4 17h6v2h-6Z", "accent": "M5 10h4v4h-4Z"}
    },
    "voxtype": {
        "idle": {"w": 12, "h": 24, "body": "M4 2h4v2h-4ZM2 4h8v6h-8ZM4 10h4v2h-4ZM0 10h2v4h-2ZM10 10h2v4h-2ZM2 14h2v2h-2ZM8 14h2v2h-2ZM4 16h4v4h-4ZM2 20h8v2h-8Z", "accent": "M5 3h2v6h-2Z"},
        "stopped": {"w": 20, "h": 24, "body": "M4 2h4v2h-4ZM2 4h8v6h-8ZM14 9h2v2h-2ZM18 9h2v2h-2ZM4 10h4v2h-4ZM16 11h2v2h-2ZM0 10h2v4h-2ZM10 10h2v4h-2ZM14 13h2v2h-2ZM18 13h2v2h-2ZM2 14h2v2h-2ZM8 14h2v2h-2ZM4 16h4v4h-4ZM2 20h8v2h-8Z"}
    },
    "tray": {
        "chevron": {"w": 10, "h": 24, "body": "M6 5h4v2h-4ZM4 7h4v2h-4ZM2 9h4v2h-4ZM0 11h4v2h-4ZM2 13h4v2h-4ZM4 15h4v2h-4ZM6 17h4v2h-4Z"}
    }
};
