pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.theme
import qs.features.settings
import "../../styles/neovim/widgets/Modes.js" as Modes

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

    // Set from the which-key window in shell.qml.
    property bool whichkey_open: false
    // Which-key's own open delay (HyprVim's which_key.delay_ms, via Settings > Input), 0 when unset.
    readonly property int whichkey_delay: HyprInputSettings.value("which_key_delay_ms") || 0
    // A little past the delay, so a HUD that opens on schedule beats the indicator instead of flashing under it.
    readonly property int delay_slack: 60
    // False from entering a submap until the which-key delay passes without the HUD opening, and from the HUD opening until 250 ms after it closes; a quick reopen then does not flicker the indicator.
    property bool indicator_clear: true
    readonly property bool indicator_shown: root.active && root.indicator_clear

    onSubmap_nameChanged: {
        // Not root.active: that binding may not have followed the new name yet.
        if (root.submap_name === "") {
            settle.stop();
            root.indicator_clear = true;
        } else if (!root.whichkey_open) {
            root.indicator_clear = false;
            settle.interval = root.whichkey_delay + root.delay_slack;
            settle.restart();
        }
    }

    onWhichkey_openChanged: {
        if (root.whichkey_open) {
            settle.stop();
            root.indicator_clear = false;
        } else {
            settle.interval = 250;
            settle.restart();
        }
    }

    Timer {
        id: settle
        onTriggered: root.indicator_clear = true
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "submap") root.submap_name = event.data;
        }
    }
}
