// home/quickshell/.config/quickshell/services/SubmapState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../theme"
import "../components/neovim/Modes.js" as Modes

Singleton {
    id: root

    property string submap_name: ""
    readonly property bool active: submap_name !== ""

    // Keyed by the `name =` field in hypr/keymaps/submaps/*/init.lua.
    readonly property var color_map: ({
        "Leader": Theme.syntax_statement,
        "Applications": Theme.syntax_func,
        "Go": Theme.syntax_identifier,
        "System": Theme.syntax_constant,
        "Delete": Theme.syntax_exception,
        "Notifications": Theme.syntax_builtin_var,
        "Screenshot": Theme.syntax_regex,
        "Windows": Theme.syntax_type,
        "Groups": Theme.syntax_conditional,
        "Cursor": Theme.syntax_macro,
        "Quick Click": Theme.syntax_macro,
        "Resize": Theme.syntax_builtin_func,
        "Move": Theme.syntax_preproc,
        "Zoom": Theme.bright_cyan,
        "Marks": Theme.syntax_operator,
        "Monitors": Theme.syntax_bracket,
        "Bar": Theme.theme_primary_light,
        "YANK": Theme.syntax_special,
        "CHANGE": Theme.syntax_string,
        "DELETE": Theme.syntax_exception,
        "REGISTERS": Theme.syntax_builtin_const,
        "MARKS": Theme.syntax_operator,
        "SET-MARK": Theme.syntax_operator,
        "DELETE-MARK": Theme.syntax_operator,
    })

    readonly property color submap_color: color_map[submap_name] || Theme.theme_secondary
    // The colour the bar shows for the current submap: the lualine mode colour (chip, z, buffers), else the submap tab's.
    readonly property color bar_color: Style.bar_lualine ? Modes.color(root.submap_name, Theme, root.submap_color) : root.submap_color

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "submap") root.submap_name = event.data;
        }
    }
}
