pragma Singleton
import QtQuick
import Quickshell

// Per-bar fills of the first and last buffers, so the chip's arrow and the island's end cap can join them, and of the
// right island's first component, for that island's cap. Keyed by key_of(screen, edge): a screen with two bars draws a
// statusline on each, and one bar's fills must not reach the other's caps.
Singleton {
    id: root

    property var first_fill: ({})
    property var last_fill: ({})
    property var right_first_fill: ({})

    function key_of(screen_name, edge) {
        return screen_name + "|" + edge;
    }

    function set_first_fill(key, color) {
        const next = Object.assign({}, root.first_fill);
        next[key] = color;
        root.first_fill = next;
    }

    function set_right_first_fill(key, color) {
        const next = Object.assign({}, root.right_first_fill);
        next[key] = color;
        root.right_first_fill = next;
    }

    function set_last_fill(key, color) {
        const next = Object.assign({}, root.last_fill);
        next[key] = color;
        root.last_fill = next;
    }
}
