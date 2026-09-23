// home/quickshell/.config/quickshell/services/Popups.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../theme"

Singleton {
    id: root

    property string open_name: ""
    property var open_anchor: null
    property color open_color: Theme.bg_mantle
    property string open_screen_name: ""

    // screen_name -> { module_name: { item, color } }, so each bar keeps its own anchors.
    property var default_anchors: ({})

    // Lets a module register the item/color its popup anchors to when opened without a click (IPC).
    function register_default(name, item, color, screen_name) {
        if (!default_anchors[screen_name]) default_anchors[screen_name] = {};
        default_anchors[screen_name][name] = { item: item, color: color };
    }

    // Called when a bar is destroyed so a popup never anchors to a deleted item.
    function unregister_screen(screen_name) {
        if (open_screen_name === screen_name) close();
        delete default_anchors[screen_name];
    }

    // Removes a module's own entry only if it still points at that module's item, so a
    // reload that already replaced the entry with a fresh module never gets clobbered.
    function unregister(name, screen_name, item) {
        const entry = default_anchors[screen_name] && default_anchors[screen_name][name];
        if (!entry || entry.item !== item) return;
        delete default_anchors[screen_name][name];
        if (open_screen_name === screen_name && open_name === name) close();
    }

    // Prefers the focused monitor's bar, falling back to any bar that has this module.
    // Dead/destroyed items are skipped so a stale entry never gets handed out.
    function find_default(name) {
        const focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        // Quickshell nulls a JS reference to a QObject once it's destroyed, so a plain truthy check finds stale entries.
        const is_live = entry => !!(entry && entry.item);
        if (focused && default_anchors[focused] && is_live(default_anchors[focused][name])) {
            return Object.assign({ screen_name: focused }, default_anchors[focused][name]);
        }
        for (const screen_name in default_anchors) {
            if (is_live(default_anchors[screen_name][name])) {
                return Object.assign({ screen_name: screen_name }, default_anchors[screen_name][name]);
            }
        }
        return null;
    }

    function open(name, anchor_item, color, screen_name) {
        if (anchor_item) {
            open_anchor = anchor_item;
            open_color = color || Theme.bg_mantle;
            open_screen_name = screen_name || "";
        } else {
            const found = root.find_default(name);
            open_anchor = found ? found.item : null;
            open_color = found ? found.color : (color || Theme.bg_mantle);
            open_screen_name = found ? found.screen_name : "";
        }
        open_name = name;
    }

    function close() {
        open_name = "";
        open_anchor = null;
        open_screen_name = "";
    }

    function toggle(name, anchor_item, color, screen_name) {
        if (open_name === name) close();
        else open(name, anchor_item, color, screen_name);
    }
}
