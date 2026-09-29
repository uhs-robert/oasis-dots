.pragma library

// Settings sections in sidebar order; `source` is relative to the settings folder.
var list = [
    { id: "style", group: "Appearance", label: "Style", glyph: "󰏘", keywords: "theme bar cava paint", source: "sections/StyleSection.qml" },
    { id: "bar", group: "Bar", label: "Bar modules", glyph: "󰕮", keywords: "modules hide show order reorder monitor layout panel", source: "sections/BarModulesSection.qml" },
    { id: "lock", group: "Lock & Login", label: "Lock screen", glyph: "󰌾", keywords: "skin tint backdrop music", source: "sections/LockSection.qml" },
    { id: "login", group: "Lock & Login", label: "Login screen", glyph: "󰍂", keywords: "greeter greetd session sync", source: "sections/LoginSection.qml" }
];

function index_of(id) {
    for (let i = 0; i < list.length; i++) {
        if (list[i].id === id) return i;
    }
    return -1;
}
