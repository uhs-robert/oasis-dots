// home/quickshell/.config/quickshell/services/SubmapState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../theme"

Singleton {
    id: root

    property string submap_name: ""
    readonly property bool active: submap_name !== ""

    // Keyed by the `name =` field in hypr/keymaps/submaps/*/init.lua.
    readonly property var color_map: ({
        "Leader": Theme.theme_secondary,
        "Applications": Theme.blue,
        "Go": Theme.cyan,
        "System": Theme.bright_red,
        "Delete": Theme.red,
        "Notifications": Theme.magenta,
        "Screenshot": Theme.bright_blue,
        "Windows": Theme.theme_primary,
        "Groups": Theme.bright_cyan,
        "Cursor": Theme.bright_yellow,
        "Quick Click": Theme.bright_yellow,
        "Resize": Theme.blue,
        "Move": Theme.bright_green,
        "Zoom": Theme.bright_magenta,
        "Marks": Theme.yellow,
        "Monitors": Theme.cyan,
    })

    readonly property color submap_color: color_map[submap_name] || Theme.theme_secondary

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "submap") root.submap_name = event.data;
        }
    }
}
