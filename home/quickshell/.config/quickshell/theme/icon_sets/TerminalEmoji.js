.pragma library

// The Terminal icon set: colour emoji, drawn in Noto Color Emoji, keyed by icon name, then by variant like OasisVectors.js. Each entry is { "text": "..." }.
// Emoji cannot show a signal level, so every wifi level but wifi_0 shares one glyph.
// There is no Bluetooth emoji, so a dot and headphones stand in for it. Emoji ignore the bar's tint, so each state the modules show only by tint has its own sign: a blue dot is on with nothing connected, headphones are connected, 📴 is off, 🚫 is rfkill-blocked.
// Voxtype recording is a speaking head, not 🔴, which already means screen recording.
// The tray chevron has to rotate, so it is not here and keeps its Nerd Font glyph. The clock keeps its bracket_tag meeting marker, so there is no meeting icon.
// Every emoji is a single code point (plus VS16 where the base is text-presented), never a ZWJ sequence, so each draws as one glyph.
var icons = {
    "bluetooth": {
        "on": {"text": "🔵"},
        "connected": {"text": "🎧"},
        "off": {"text": "📴"},
        "blocked": {"text": "🚫"}
    },
    "notifications": {
        "normal": {"text": "🔔"},
        "dnd": {"text": "🔕"}
    },
    "volume": {
        "muted": {"text": "🔇"},
        "low": {"text": "🔈"},
        "mid": {"text": "🔉"},
        "high": {"text": "🔊"}
    },
    "network": {
        "wifi_0": {"text": "📵"},
        "wifi_1": {"text": "📶"},
        "wifi_2": {"text": "📶"},
        "wifi_3": {"text": "📶"},
        "wifi_4": {"text": "📶"},
        "wired": {"text": "🔌"},
        "offline": {"text": "🚫"}
    },
    "battery": {
        "level_0": {"text": "🪫"},
        "level_1": {"text": "🔋"},
        "level_2": {"text": "🔋"},
        "level_3": {"text": "🔋"},
        "level_4": {"text": "🔋"},
        "full": {"text": "🔋"},
        "charging": {"text": "⚡"}
    },
    "system": {
        "cpu": {"text": "🧠"},
        "mem": {"text": "💾"},
        "temp": {"text": "🌡️"}
    },
    "updates": {
        "official": {"text": "📦"},
        "aur": {"text": "🛠️"}
    },
    "media": {
        "normal": {"text": "🎵"}
    },
    "recording": {
        "scrolling": {"text": "📜"},
        "counting": {"text": "⏱️"},
        "default": {"text": "🔴"}
    },
    "voxtype": {
        "idle": {"text": "🎙️"},
        "recording": {"text": "🗣️"},
        "transcribing": {"text": "⏳"},
        "stopped": {"text": "🤐"}
    }
};
