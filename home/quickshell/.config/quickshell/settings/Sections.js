.pragma library

// Settings sections in sidebar order; `source` is relative to the settings folder.
var list = [
    { id: "style", group: "Appearance", label: "Style", glyph: "󰏘", keywords: "theme bar cava paint hot corners overview", source: "sections/StyleSection.qml" },
    { id: "colors", group: "Appearance", label: "Colors", glyph: "󰸌", keywords: "color scheme palette oasis theme swatch", source: "sections/ColorsSection.qml" },
    { id: "theme", group: "Appearance", label: "Theme options", glyph: "󰒓", keywords: "scanlines glow dither font effects style options", source: "sections/ThemeOptionsSection.qml" },
    { id: "bar", group: "Bar", label: "Bar modules", glyph: "󰕮", keywords: "modules hide show order reorder monitor layout panel", source: "sections/BarModulesSection.qml" },
    { id: "weather", group: "Bar", label: "Weather", glyph: "󰖙", keywords: "forecast location latitude longitude coordinates city temperature celsius fahrenheit units days alerts ip", source: "sections/WeatherSection.qml" },
    { id: "displays", group: "System", label: "Displays", glyph: "󰍹", keywords: "monitors resolution refresh scale rotate orientation arrange position enable disable screen", source: "sections/DisplaysSection.qml" },
    { id: "apps", group: "System", label: "Default apps", glyph: "󰀻", keywords: "terminal browser editor file manager mime xdg associations mail pdf", source: "sections/DefaultAppsSection.qml" },
    { id: "power", group: "System", label: "Power", glyph: "󰐥", keywords: "idle dim lock suspend sleep lid button battery ac profile hypridle", source: "sections/PowerSection.qml" },
    { id: "audio", group: "Sound", label: "Theme audio", glyph: "󰕾", keywords: "sound music chiptune notification cursor confirm cancel volume music effects pack", source: "sections/AudioSection.qml" },
    { id: "lock", group: "Lock & Login", label: "Lock screen", glyph: "󰌾", keywords: "skin tint backdrop music", source: "sections/LockSection.qml" },
    { id: "login", group: "Lock & Login", label: "Login screen", glyph: "󰍂", keywords: "greeter greetd session sync", source: "sections/LoginSection.qml" }
];

function index_of(id) {
    for (let i = 0; i < list.length; i++) {
        if (list[i].id === id) return i;
    }
    return -1;
}
