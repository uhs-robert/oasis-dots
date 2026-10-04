.pragma library

// One entry per bar module; order is the settings list order. section is the lualine right-island section.
var modules = [
    { name: "start", file: "StartButton.qml", popup: true, section: "x", args: [] },
    { name: "workspaces", file: "Workspaces.qml", popup: false, section: "x", args: [] },
    { name: "clock", file: "Clock.qml", popup: true, section: "z", args: [] },
    { name: "tray", file: "Tray.qml", popup: true, section: "x", args: [] },
    { name: "volume", file: "Volume.qml", popup: true, section: "x", args: [] },
    { name: "battery", file: "Battery.qml", popup: true, section: "x", args: [] },
    { name: "bluetooth", file: "Bluetooth.qml", popup: true, section: "y", args: [] },
    { name: "system", file: "System.qml", popup: true, section: "x", args: ["cpu", "memory", "temperature"] },
    { name: "network", file: "Network.qml", popup: true, section: "y", args: [] },
    { name: "weather", file: "Weather.qml", popup: true, section: "x", args: [] },
    { name: "keeptabs", file: "Keeptabs.qml", popup: true, section: "x", args: [] },
    { name: "updates", file: "Updates.qml", popup: true, section: "x", args: [] },
    { name: "voxtype", file: "Voxtype.qml", popup: false, section: "y", args: [] },
    { name: "recording", file: "Recording.qml", popup: false, section: "y", args: [] },
    { name: "notifications", file: "Notifications.qml", popup: true, section: "z", args: [] },
    { name: "media", file: "Media.qml", popup: true, section: "x", args: [] }
];

var names = modules.map(m => m.name);

function find(name) {
    return modules.find(m => m.name === name) || null;
}

function has_popup(name) {
    const m = find(name);
    return !!m && m.popup;
}
