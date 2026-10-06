// home/quickshell/.config/quickshell/services/SettingsNav.qml
pragma Singleton
import QtQuick
import Quickshell

// Opens the settings popup, optionally on a named section, and relays hands-off commands to it.
Singleton {
    id: root

    property string requested: ""

    // A command for the open popup's pane: "cursor", "step", "activate" or "back"; `value` is the row index or step delta.
    signal pane_command(string name, int value)

    function open(section_id) {
        root.requested = section_id;
        Popups.open("settings", null);
    }

    // Opens on `screen` without taking keyboard or pointer input; false when that screen does not exist.
    function show(section_id, screen_name) {
        root.requested = section_id;
        const opened = Popups.open_on("settings", screen_name, true);
        if (!opened) root.requested = "";
        return opened;
    }

    function command(name, value) {
        root.pane_command(name, value);
    }
}
