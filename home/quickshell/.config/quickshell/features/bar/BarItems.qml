pragma Singleton
import QtQuick
import Quickshell

// Where each live bar module sits, for the bar editor's overlay: "screen|entry" -> the module Item, and "screen|bar" -> the Bar.
// Kept apart from BarEditor so Bar.qml can publish into it without importing the editor.
Singleton {
    id: root

    property var items: ({})
    // Bumped on every change, so a binding that looked an item up looks again.
    property int revision: 0

    function key_of(screen_name, entry) {
        return screen_name + "|" + entry.base + (entry.arg ? ":" + entry.arg : "");
    }

    function register(key, item) {
        root.items[key] = item;
        root.revision++;
    }

    // The bar of a screen that went away.
    function forget_screen(screen_name) {
        for (const key of Object.keys(root.items)) {
            if (key.indexOf(screen_name + "|") === 0) delete root.items[key];
        }
        root.revision++;
    }

    function item_of(screen_name, entry) {
        const _ = root.revision;
        return root.items[screen_name + "|" + entry] || null;
    }
}
