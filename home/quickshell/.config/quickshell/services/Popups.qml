// home/quickshell/.config/quickshell/services/Popups.qml
pragma Singleton
import QtQuick
import Quickshell
import "../theme"

Singleton {
    id: root

    property string open_name: ""
    property var open_anchor: null
    property color open_color: Theme.bg_mantle
    property var default_anchors: ({})
    property var default_colors: ({})

    // Lets a module register the item/color its popup anchors to when opened without a click (IPC).
    function register_default(name, item, color) {
        default_anchors[name] = item;
        default_colors[name] = color;
    }

    function open(name, anchor_item, color) {
        open_anchor = anchor_item || default_anchors[name] || null;
        open_color = color || default_colors[name] || Theme.bg_mantle;
        open_name = name;
    }

    function close() {
        open_name = "";
        open_anchor = null;
    }

    function toggle(name, anchor_item, color) {
        if (open_name === name) close();
        else open(name, anchor_item, color);
    }
}
