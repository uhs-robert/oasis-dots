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
    // Popup name to reopen on Backspace, e.g. "start" for popups opened from the Start menu.
    property string back_name: ""
    // Consumed by StartPopup on open: an actions index to land straight in confirm mode for, or -1.
    property int pending_confirm: -1

    // screen_name -> { module_name: { item, color } }, so each bar keeps its own anchors.
    property var default_anchors: ({})

    // screen_name -> ordered popup names in bar order, kept by Bar for Ctrl+H/L walking.
    property var popup_order: ({})

    // Lets a module register the item/color its popup anchors to when opened without a click (IPC).
    // `owner` is the registering module; it defaults to the anchor item (the clock has no module).
    function register_default(name, item, color, screen_name, owner, back_to) {
        if (!default_anchors[screen_name]) default_anchors[screen_name] = {};
        default_anchors[screen_name][name] = { item: item, color: color, owner: owner || item, back_to: back_to || "" };
    }

    function register_order(screen_name, names) {
        popup_order[screen_name] = names;
    }

    // Called when a bar is destroyed so a popup never anchors to a deleted item.
    function unregister_screen(screen_name) {
        if (open_screen_name === screen_name) close();
        delete default_anchors[screen_name];
        delete popup_order[screen_name];
    }

    // Removes an entry only if its owner registered it: a rebuilt module shares the island
    // item with the one being destroyed, so matching on the item would drop the new entry.
    function unregister(name, screen_name, owner) {
        const entry = default_anchors[screen_name] && default_anchors[screen_name][name];
        if (!entry || entry.owner !== owner) return;
        delete default_anchors[screen_name][name];
        if (open_screen_name === screen_name && open_name === name) close();
    }

    // Quickshell nulls a JS reference to a QObject once it's destroyed, so a plain truthy check finds stale entries.
    function find_in_screen(screen_name, name) {
        const entry = default_anchors[screen_name] && default_anchors[screen_name][name];
        return entry && entry.item ? Object.assign({ screen_name: screen_name }, entry) : null;
    }

    // Prefers the focused monitor's bar, falling back to any bar that has this module.
    function find_default(name) {
        const focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        if (focused) {
            const found = root.find_in_screen(focused, name);
            if (found) return found;
        }
        for (const screen_name in default_anchors) {
            const found = root.find_in_screen(screen_name, name);
            if (found) return found;
        }
        return null;
    }

    // Anchors are island bodies; read the Island's color, since a shaded body is transparent.
    function anchor_color(found) {
        const island = found.item ? found.item.parent : null;
        return island && island.bg_color !== undefined ? island.bg_color : found.color;
    }

    // Steps to the next (delta 1) or previous (delta -1) module's popup in that screen's bar order, wrapping.
    function walk(delta) {
        const screen_name = root.open_screen_name;
        const order = root.popup_order[screen_name] || [];
        if (order.length === 0) return;
        let idx = order.indexOf(root.open_name);
        if (idx === -1) {
            if (root.back_name === "") return;
            idx = order.indexOf(root.back_name);
            if (idx === -1) return;
        }
        const n = order.length;
        for (let step = 1; step <= n; step++) {
            const candidate = order[((idx + delta * step) % n + n) % n];
            const found = root.find_in_screen(screen_name, candidate);
            if (found) {
                root.open(candidate, found.item, root.anchor_color(found), screen_name, found.back_to);
                return;
            }
        }
    }

    function open(name, anchor_item, color, screen_name, back_to) {
        let back = back_to || "";
        if (anchor_item) {
            open_anchor = anchor_item;
            open_color = color || Theme.bg_mantle;
            open_screen_name = screen_name || "";
        } else {
            const found = root.find_default(name);
            open_anchor = found ? found.item : null;
            open_color = found ? root.anchor_color(found) : (color || Theme.bg_mantle);
            // A popup with no module (the docked picker) opens on the screen it names.
            open_screen_name = found ? found.screen_name : (screen_name || "");
            if (found && !back) back = found.back_to || "";
        }
        open_name = name;
        back_name = back;
    }

    function close() {
        open_name = "";
        open_anchor = null;
        open_screen_name = "";
        back_name = "";
    }

    // Reopens the popup that opened the current one, keeping the same anchor/color/screen.
    function back() {
        if (root.back_name === "") return;
        const found = root.find_in_screen(root.open_screen_name, root.back_name);
        root.open(root.back_name, root.open_anchor, root.open_color, root.open_screen_name, found ? found.back_to : "");
    }

    function toggle(name, anchor_item, color, screen_name) {
        if (open_name === name) close();
        else open(name, anchor_item, color, screen_name);
    }

    // Keybind workspace switches never touch the scrim, so close here too.
    Connections {
        target: Hyprland
        enabled: root.open_name !== ""
        function onRawEvent(event) {
            if (event.name === "workspacev2") root.close();
        }
    }
}
