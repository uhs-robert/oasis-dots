.pragma library

// Settings sections in sidebar order; `source` is relative to the settings folder.
var list = [
    { id: "style", group: "Appearance", label: "Style", glyph: "󰏘", keywords: "theme bar cava paint", source: "sections/StyleSection.qml" },
    { id: "bar", group: "Bar", label: "Bar modules", glyph: "󰕮", keywords: "modules hide show order reorder monitor layout panel", source: "sections/BarModulesSection.qml" },
    { id: "displays", group: "System", label: "Displays", glyph: "󰍹", keywords: "monitors resolution refresh scale rotate orientation arrange position enable disable screen", source: "sections/DisplaysSection.qml" },
    { id: "lock", group: "Lock & Login", label: "Lock screen", glyph: "󰌾", keywords: "skin tint backdrop music", source: "sections/LockSection.qml" },
    { id: "login", group: "Lock & Login", label: "Login screen", glyph: "󰍂", keywords: "greeter greetd session sync", source: "sections/LoginSection.qml" },
    { id: "apps", group: "System", label: "Default apps", glyph: "󰀻", keywords: "terminal browser editor file manager mime xdg associations mail pdf", source: "sections/DefaultAppsSection.qml" },
    { id: "power", group: "System", label: "Power", glyph: "󰐥", keywords: "idle dim lock suspend sleep lid button battery ac profile hypridle", source: "sections/PowerSection.qml" }
];

function index_of(id) {
    for (let i = 0; i < list.length; i++) {
        if (list[i].id === id) return i;
    }
    return -1;
}
