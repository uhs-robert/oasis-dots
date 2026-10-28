.pragma library

// Settings sections in sidebar order; `source` is relative to the settings folder.
var list = [
    { id: "style", group: "Appearance", label: "Style", glyph: "󰏘", keywords: "theme bar cava paint hot corners overview osd volume brightness popup edge left right side colors color scheme palette oasis swatch neovim flush frame screen", source: "sections/StyleSection.qml" },
    { id: "wallpaper", group: "Appearance", label: "Wallpaper", glyph: "󰋩", keywords: "background image rotate rotation interval pin pinned monitor season time of day weather hyprpaper", source: "sections/WallpaperSection.qml" },
    { id: "theme", group: "Appearance", label: "Theme options", glyph: "󰒓", keywords: "scanlines glow dither font effects style options opacity transparency islands frame corner skins picker overview osd workspaces icons text size", source: "sections/ThemeOptionsSection.qml" },
    { id: "audio", group: "Appearance", label: "Theme audio", glyph: "󰕾", keywords: "sound chiptune notification cursor confirm cancel volume effects pack", source: "sections/AudioSection.qml" },
    { id: "bar", group: "Bar", label: "Bar modules", glyph: "󰕮", keywords: "edit editor bar modules directory", source: "sections/BarModulesSection.qml" },
    { id: "datetime", group: "Bar", label: "Date & time", glyph: "󰥔", keywords: "clock calendar week first day monday sunday locale time format 12 24 hour connect sync google meetings events account ical feed calendar-sync rbw keyring", source: "sections/DateTimeSection.qml" },
    { id: "weather", group: "Bar", label: "Weather", glyph: "󰖙", keywords: "forecast location latitude longitude coordinates city temperature celsius fahrenheit units days alerts ip", source: "sections/WeatherSection.qml" },
    { id: "media", group: "Bar", label: "Media", glyph: "󰎆", keywords: "cava music player visualizer line marquee scroll title artist album island battery position seek volume mpris", source: "sections/MediaSection.qml" },
    { id: "displays", group: "System", label: "Displays", glyph: "󰍹", keywords: "monitors resolution refresh scale rotate orientation arrange position enable disable screen", source: "sections/DisplaysSection.qml" },
    { id: "apps", group: "System", label: "Default apps", glyph: "󰀻", keywords: "terminal browser editor file manager mime xdg associations mail pdf", source: "sections/DefaultAppsSection.qml" },
    { id: "power", group: "System", label: "Power", glyph: "󰐥", keywords: "idle dim lock suspend sleep lid button battery ac profile hypridle", source: "sections/PowerSection.qml" },
    { id: "sessions", group: "System", label: "Sessions", glyph: "󰆍", keywords: "session launcher layout windows workspace save restore picker", source: "sections/SessionsSection.qml" },
    { id: "lock", group: "System", label: "Lock & login", glyph: "󰌾", keywords: "lock screen skin tint backdrop music volume login greeter greetd session sync", source: "sections/LockLoginSection.qml" },
    { id: "input", group: "Input", label: "Typing", glyph: "󰌌", keywords: "vim insert normal mode typing search picker start remember query which key delay", source: "sections/InputSection.qml" },
    { id: "keyboard", group: "Input", label: "Keyboard", glyph: "󰥻", keywords: "layout variant xkb caps lock escape repeat rate delay", source: "sections/KeyboardSection.qml" },
    { id: "voice", group: "Input", label: "Voice", glyph: "󰍬", keywords: "voice cortana wake word hey whisper listener mic call media pause microphone voxcmd voxtype duck music dictation type mode sensitivity speech", source: "sections/VoiceSection.qml" },
    { id: "mouse", group: "Input", label: "Mouse & touchpad", glyph: "󰍽", keywords: "pointer sensitivity speed natural scroll tap click disable while typing focus follows mouse keyboard cursor hjkl wasd wl-kbptr", source: "sections/MouseSection.qml" }
];

// Ids of sections merged into others, still taken by `settings open`: the section and the heading or tab to open on.
var aliases = {
    colors: { id: "style", part: "Colors" },
    clock: { id: "datetime", part: "Format" },
    calendar: { id: "datetime", part: "Calendar" },
    login: { id: "lock", part: "Login" }
};

// The section `id` (or an alias) opens, as { index, part }; index is -1 for an unknown id.
function resolve(id) {
    const alias = aliases[id];
    const target = alias ? alias.id : id;
    for (let i = 0; i < list.length; i++) {
        if (list[i].id === target) return { index: i, part: alias ? alias.part : "" };
    }
    return { index: -1, part: "" };
}
