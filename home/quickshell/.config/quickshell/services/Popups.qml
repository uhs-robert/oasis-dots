// home/quickshell/.config/quickshell/services/Popups.qml
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    property string open_name: ""
    property var open_anchor: null
    property var default_anchors: ({})

    // Lets a module register the item its popup anchors to when opened without a click (IPC).
    function register_default(name, item) {
        default_anchors[name] = item;
    }

    function open(name, anchor_item) {
        open_anchor = anchor_item || default_anchors[name] || null;
        open_name = name;
    }

    function close() {
        open_name = "";
        open_anchor = null;
    }

    function toggle(name, anchor_item) {
        if (open_name === name) close();
        else open(name, anchor_item);
    }
}
