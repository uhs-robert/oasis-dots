// home/quickshell/.config/quickshell/services/SettingsNav.qml
pragma Singleton
import QtQuick
import Quickshell

// Opens the settings popup, optionally on a named section.
Singleton {
    id: root

    property string requested: ""

    function open(section_id) {
        root.requested = section_id;
        Popups.open("settings", null);
    }
}
