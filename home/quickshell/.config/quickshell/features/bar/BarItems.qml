pragma Singleton
import QtQuick
import Quickshell

// Where each live bar module sits, for the bar editor's overlay: "screen|entry" -> the module Item, "screen|bar" -> the
// screen's first Bar and "screen|second_bar" -> its second. A screen shows each module once across both its bars, so the
// key needs no edge. Each item keeps the Bar that registered it, so one of a screen's two bars going away forgets only its
// own, and the editor can tell which bar a module is on.
// Kept apart from BarEditor so Bar.qml can publish into it without importing the editor.
Singleton {
    id: root

    property var items: ({})
    property var owners: ({})
    // Bumped on every change, so a binding that looked an item up looks again.
    property int revision: 0

    function key_of(screen_name, entry) {
        return screen_name + "|" + entry.base + (entry.arg ? ":" + entry.arg : "");
    }

    function register(key, item, owner) {
        root.items[key] = item;
        root.owners[key] = owner;
        root.revision++;
    }

    // What a Bar that went away registered (its monitor unplugged, or its screen lost the second bar).
    function forget_owner(owner) {
        for (const key of Object.keys(root.items)) {
            if (root.owners[key] !== owner) continue;
            delete root.items[key];
            delete root.owners[key];
        }
        root.revision++;
    }

    function item_of(screen_name, entry) {
        const _ = root.revision;
        return root.items[screen_name + "|" + entry] || null;
    }

    // The Bar that shows `entry` on the screen, or null.
    function bar_of(screen_name, entry) {
        const _ = root.revision;
        return root.owners[screen_name + "|" + entry] || null;
    }
}
