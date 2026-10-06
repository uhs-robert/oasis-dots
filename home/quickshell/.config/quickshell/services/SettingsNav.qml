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
        // Checked before `requested` is set, since setting it switches an open popup's section at once.
        if (!Quickshell.screens.some(s => s.name === screen_name)) return false;
        // Moving an open Settings to another screen closes it first; the section is requested only once it reopens, or the closing popup would use it up.
        if (Popups.open_name === "settings" && Popups.open_screen_name !== screen_name) {
            Popups.close();
            Qt.callLater(() => root.show(section_id, screen_name));
            return true;
        }
        root.requested = section_id;
        return Popups.open_on("settings", screen_name, true);
    }

    function command(name, value) {
        root.pane_command(name, value);
    }
}
